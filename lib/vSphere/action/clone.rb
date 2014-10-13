require 'rbvmomi'
require 'i18n'
require 'vSphere/util/vim_helpers'
require 'vSphere/util/machine_helpers'

module VagrantPlugins
  module VSphere
    module Action
      class Clone
        include Util::VimHelpers
        include Util::MachineHelpers

        def initialize(app, env)
          @app = app
        end

        def call(env)
          machine = env[:machine]
          config = machine.provider_config
          connection = env[:vSphere_connection]
          network_config = get_network_config machine
          name = get_name machine, config, network_config, env[:root_path]
          dc = get_datacenter connection, machine
          template = dc.find_vm config.template_name
          raise Errors::VSphereError, :'missing_template' if template.nil?
          vm_base_folder = get_vm_base_folder dc, template, config
          raise Errors::VSphereError, :'invalid_base_path' if vm_base_folder.nil?

          begin
            location = get_location connection, machine, config, template
            spec = RbVmomi::VIM.VirtualMachineCloneSpec :location => location, :powerOn => true, :template => false
            customization_info = get_customization_spec_info_by_name connection, machine
            if customization_info.nil?
              spec.customization = set_customization_spec(machine, config, network_config)
            else
              spec.customization = get_customization_spec(network_config, customization_info)
            end

            network_spec = get_network_spec network_config, dc, template
            vm_spec = RbVmomi::VIM.VirtualMachineConfigSpec
            vm_spec.deviceChange = network_spec unless network_spec.nil?

            vm_spec.numCPUs = config.cpu_num unless config.cpu_num.nil?
            vm_spec.memoryMB = config.memory unless config.memory.nil?

            spec.config = vm_spec

            env[:ui].info I18n.t('vsphere.creating_cloned_vm')
            env[:ui].info " -- #{config.clone_from_vm ? "Source" : "Template"} VM: #{template.pretty_path}"
            env[:ui].info " -- Target VM: #{vm_base_folder.pretty_path}/#{name}"

            new_vm = template.CloneVM_Task(:folder => vm_base_folder, :name => name, :spec => spec).wait_for_completion
          rescue Exception => e
            raise Errors::VSphereError.new, e.message
          end

          #TODO: handle interrupted status in the environment, should the vm be destroyed?

          machine.id = new_vm.config.uuid

          # wait for SSH to be available
          wait_for_ssh env

          env[:ui].info I18n.t('vsphere.vm_clone_success')

          @app.call env
        end

        private

        def get_network_config(machine)

          network_config = []

          private_networks = machine.config.vm.networks.find_all { |n| n[0].eql? :private_network }
          public_networks = machine.config.vm.networks.find_all { |n| n[0].eql? :public_network }
          network_config.concat(private_networks)
          network_config.concat(public_networks)

          network_config
        end

        def get_network_spec(network_config, dc, template)

          network_spec = []

          # assign the private network IP to the NIC
          cards = template.config.hardware.device.grep(RbVmomi::VIM::VirtualEthernetCard)
          network_config.each_index do |idx|
            nic_name = network_config[idx][1][:nic]
            nic_type = network_config[idx][1][:type]

            if !nic_name.nil?
            # First we must find the specified network
              network = dc.network.find { |f| f.name == nic_name } or
                  abort "Could not find network with name #{nic_name} to join vm to"

              card = cards[idx] or abort "could not find network card to customize"

              if !nic_type.nil? and nic_type == "vDS"

                switch_port = RbVmomi::VIM.DistributedVirtualSwitchPortConnection(
                              :switchUuid => network.config.distributedVirtualSwitch.uuid,
                              :portgroupKey => network.key)
                card.backing = RbVmomi::VIM.VirtualEthernetCardDistributedVirtualPortBackingInfo(
                               :port => switch_port)
              else
                card.backing = RbVmomi::VIM.VirtualEthernetCardNetworkBackingInfo(
                               :deviceName => nic_name)
              end

              dev_spec = RbVmomi::VIM.VirtualDeviceConfigSpec(:device => card, :operation => "edit")
              network_spec << dev_spec
            end

          end

          network_spec
        end


        def set_customization_spec(machine, config, network_config)

          nic_map = []

          global_ip_settings = RbVmomi::VIM.CustomizationGlobalIPSettings(
                               :dnsServerList => config.dns_server_list,
                               :dnsSuffixList => config.dns_suffix_list)

          prep = RbVmomi::VIM.CustomizationLinuxPrep(
                 :domain => config.domain.to_s,
                 :hostName => RbVmomi::VIM.CustomizationFixedName(
                              :name => machine.name.to_s))

          network_config.each_index do |idx|
            ip = network_config[idx][1][:ip]
            netmask = network_config[idx][1][:netmask]
            gateway = network_config[idx][1][:gateway]
            if not gateway.nil?
              gateways = [gateway]
            else
              gateways = gateway
            end

            # Check for sanity and validation of network parameters.

            if !ip && netmask
              raise Errors::VSphereError, :"netmask specified but ip missing"
            end

            if ip && !netmask
              raise Errors::VSphereError, :"ip specified but netmask missing"
            end

            # if no ip and no netmask, let's default to dhcp
            if !ip && !netmask
              adapter = RbVmomi::VIM.CustomizationIPSettings(
                        :ip => RbVmomi::VIM.CustomizationDhcpIpGenerator())
            else
              adapter = RbVmomi::VIM.CustomizationIPSettings(
                        :gateway => gateways,
                        :ip => RbVmomi::VIM.CustomizationFixedIp(
                               :ipAddress => ip),
                        :subnetMask => netmask)
            end

            nic_map << RbVmomi::VIM.CustomizationAdapterMapping(
                       :adapter => adapter)
          end

          customization_spec = RbVmomi::VIM.CustomizationSpec(
                               :globalIPSettings => global_ip_settings,
                               :identity => prep,
                               :nicSettingMap => nic_map)

          customization_spec
        end

        def get_customization_spec(network_config, spec_info)
          customization_spec = spec_info.spec.clone

          # find all the configured private networks
          return customization_spec if network_config.nil?

          # make sure we have enough NIC settings to override with the private network settings
          raise Errors::VSphereError, :'too_many_private_networks' if network_config.length > customization_spec.nicSettingMap.length

          # assign the private network IP to the NIC
          network_config.each_index do |idx|
            customization_spec.nicSettingMap[idx].adapter.ip.ipAddress = network_config[idx][1][:ip]
          end

          customization_spec
        end

        def get_location(connection, machine, config, template)
          if config.linked_clone
            # The API for linked clones is quite strange. We can't create a linked
            # straight from any VM. The disks of the VM for which we can create a
            # linked clone need to be read-only and thus VC demands that the VM we
            # are cloning from uses delta-disks. Only then it will allow us to
            # share the base disk.
            #
            # Thus, this code first create a delta disk on top of the base disk for
            # the to-be-cloned VM, if delta disks aren't used already.
            disks = template.config.hardware.device.grep(RbVmomi::VIM::VirtualDisk)
            disks.select { |disk| disk.backing.parent == nil }.each do |disk|
              spec = {
                  :deviceChange => [
                      {
                          :operation => :remove,
                          :device => disk
                      },
                      {
                          :operation => :add,
                          :fileOperation => :create,
                          :device => disk.dup.tap { |new_disk|
                            new_disk.backing = new_disk.backing.dup
                            new_disk.backing.fileName = "[#{disk.backing.datastore.name}]"
                            new_disk.backing.parent = disk.backing
                          },
                      }
                  ]
              }
              template.ReconfigVM_Task(:spec => spec).wait_for_completion
            end

            location = RbVmomi::VIM.VirtualMachineRelocateSpec(:diskMoveType => :moveChildMostDiskBacking)
          else
            location = RbVmomi::VIM.VirtualMachineRelocateSpec

            datastore = get_datastore connection, machine
            location[:datastore] = datastore unless datastore.nil?
          end
          location[:pool] = get_resource_pool(connection, machine) unless config.clone_from_vm
          location
        end

        def get_name(machine, config, network_config, root_path)
          return config.name unless config.name.nil?

          prefix = "#{machine.name}"
          prefix.gsub!(/[^-a-z0-9_\.]/i, "")

          if network_config.nil? or network_config.empty?
            # milliseconds + random number suffix to allow for simultaneous `vagrant up` of the same box in different dirs
            prefix += "_#{(Time.now.to_f * 1000.0).to_i}_#{rand(100000)}"
          else
            network_config.each_index do |idx|
              ipaddr = network_config[idx][1][:ip]
              prefix += "_" + ipaddr
            end
          end
          prefix
        end

        def get_vm_base_folder(dc, template, config)
          if config.vm_base_path.nil?
            template.parent
          else
            dc.vmFolder.traverse(config.vm_base_path, RbVmomi::VIM::Folder, create=true)
          end
        end
      end
    end
  end
end
