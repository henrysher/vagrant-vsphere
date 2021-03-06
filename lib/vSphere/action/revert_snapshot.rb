require 'rbvmomi'
require 'i18n'
require 'vSphere/util/vim_helpers'
require 'vSphere/util/machine_helpers'

module VagrantPlugins
  module VSphere
    module Action
      class RevertSnapshot
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

          env[:ui].info I18n.t('vsphere.waiting_for_vm_revert_snapshot')

          begin
            snapshot = find_snapshot vm.snapshot.rootSnapshotList,config.snapshot_name
          rescue Exception => e
            raise Errors::VSphereError.new, e.message
          end

          tries = 10
          begin
            snapshot.snapshot.RevertToSnapshot_Task(:suppressPowerOn => true).wait_for_completion
          rescue Exception => e
            if e.message.include?("undefined method `wait_for_completion'")
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

          ##TODO: handle interrupted status in the environment, should the vm be destroyed?
          machine.id = vm.config.uuid
          env[:ui].info I18n.t('vsphere.vm_revert_snapshot_success')          

          @app.call env
        end

        private

        def find_snapshot(root_snapshots, snapshot_name)
          result = root_snapshots.find {|x| x.name == snapshot_name}
          if result
            return result
          end

          for root_snapshot in root_snapshots
            child_snapshots = root_snapshot.childSnapshotList
            if child_snapshots
              result = find_snapshot(child_snapshots, snapshot_name)
              if result
                return result
              end
            end
          end
          return nil
        end
      end
    end
  end
end
