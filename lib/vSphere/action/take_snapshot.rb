require 'rbvmomi'
require 'i18n'
require 'vSphere/util/vim_helpers'
require 'vSphere/util/machine_helpers'

module VagrantPlugins
  module VSphere
    module Action
      class TakeSnapshot
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
          raise Errors::VSphereError, :message => I18n.t('errors.missing_vm') if vm.nil?

          if not vm.snapshot
            snapshot = nil
          else
            snapshot = find_snapshot vm.snapshot.rootSnapshotList,config.snapshot_name
          end

          if not snapshot.nil?
            env[:ui].error I18n.t('errors.snapshot_exist')
            # FIXME
            raise Errors::VSphereError
          end

          begin
            vm.CreateSnapshot_Task(:description => config.snapshot_desc,
                                   :memory => false,
                                   :name => config.snapshot_name,
                                   :quiesce => false
                                  ).wait_for_completion
          rescue Exception => e
            puts e.message
            raise Errors::VSphereError, :message => e.message
          end

          #TODO: handle interrupted status in the environment, should the vm be destroyed?
          machine.id = vm.config.uuid
          env[:ui].info I18n.t('vsphere.vm_take_snapshot_success')          

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
