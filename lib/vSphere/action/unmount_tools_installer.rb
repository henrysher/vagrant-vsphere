require 'rbvmomi'
require 'i18n'
require 'vSphere/util/vim_helpers'
require 'vSphere/util/machine_helpers'

module VagrantPlugins
  module VSphere
    module Action
      class UnmountToolsInstaller
        include Util::VimHelpers
        include Util::MachineHelpers

        def initialize(app, env)
          @app = app
        end

        def call(env)
          config = env[:machine].provider_config
          connection = env[:vSphere_connection]
          machine = env[:machine]

          vm = get_vm_by_uuid env[:vSphere_connection], env[:machine]
          raise Errors::VSphereError, I18n.t('errors.missing_vm') if vm.nil?

          # FIXME
          begin
            vm.MountToolsInstaller()
          rescue Exception => e
          end

          # FIXME
          tries = 10
          begin
            vm.UnmountToolsInstaller()
          rescue Exception => e
            # FIXME
            if e.message.include?("InvalidState")
              tries -= 1
              if tries > 0
                sleep(1)
                retry
              else
                raise Errors::VSphereError.new, e.message
              end
            else
              raise Errors::VSphereError.new, e.message
            end
          end

          #TODO: handle interrupted status in the environment, should the vm be destroyed?
          machine.id = vm.config.uuid
          env[:ui].info I18n.t('vsphere.vm_unmount_tools_installer_success')          

          @app.call env
        end

      end
    end
  end
end
