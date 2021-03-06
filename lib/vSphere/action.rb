require 'vagrant'
require 'vagrant/action/builder'

module VagrantPlugins
  module VSphere
    module Action
      include Vagrant::Action::Builtin

      #Vagrant commands
      def self.action_destroy
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsRunning do |env, b2|
            if [:result]
                b2.use PowerOff
                next
            end
          end
          b.use Destroy
        end
      end

      def self.action_provision
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            if !env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env, b3|
              if !env[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use Provision
              b3.use SyncedFolders
            end
          end
        end
      end

      def self.action_ssh
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            if !env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env, b3|
              if !env[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use SSHExec
            end
          end
        end
      end

      def self.action_ssh_run
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            if !env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env, b3|
              if !env[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use SSHRun
            end
          end
        end
      end

      def self.action_clone
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            if env[:result]
              b2.use MessageAlreadyCreated
              next
            end

            b2.use Clone
          end
          b.use Call, IsRunning do |env, b2|
            if !env[:result]
              b2.use PowerOn
            end
          end

          b.use TakeSnapshot
          b.use PowerOff
          b.use CloseVSphere
        end
      end

      def self.action_up
        Vagrant::Action::Builder.new.tap do |b|
          b.use HandleBox
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            if env[:result]
              b2.use MessageAlreadyCreated
              next
            end

            b2.use RevertSnapshot
          end
          b.use Call, IsRunning do |env, b2|
            if !env[:result]
              b2.use PowerOn
            end

            b2.use MountToolsInstaller
            b2.use Provision
            b2.use SyncedFolders
          end

          b.use CloseVSphere
        end
      end

      def self.action_up_force
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            b2.use RevertSnapshot
          end

          b.use Call, IsRunning do |env, b2|
            if !env[:result]
              b2.use PowerOn
              b2.use MountToolsInstaller
            end

            b2.use Provision
            b2.use SyncedFolders
            b2.use SetHostname
          end

          b.use CloseVSphere
        end
      end

      def self.action_halt
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use Call, IsCreated do |env, b2|
            if !env[:result]
              b2.use MessageNotCreated
              next
            end

            b2.use Call, IsRunning do |env, b3|
              if !env[:result]
                b3.use MessageNotRunning
                next
              end

              b3.use PowerOff
            end
          end
          b.use CloseVSphere
        end
      end

      #vSphere specific actions
      def self.action_get_state
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use GetState
          b.use CloseVSphere
        end
      end

      def self.action_get_ssh_info
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectVSphere
          b.use GetSshInfo
          b.use CloseVSphere
        end
      end

      #autoload
      action_root = Pathname.new(File.expand_path('../action', __FILE__))
      autoload :Clone, action_root.join('clone')
      autoload :TakeSnapshot, action_root.join('take_snapshot')
      autoload :RevertSnapshot, action_root.join('revert_snapshot')
      autoload :MountToolsInstaller, action_root.join('mount_tools_installer')
      autoload :UnmountToolsInstaller, action_root.join('unmount_tools_installer')
      autoload :CloseVSphere, action_root.join('close_vsphere')
      autoload :ConnectVSphere, action_root.join('connect_vsphere')
      autoload :Destroy, action_root.join('destroy')
      autoload :GetSshInfo, action_root.join('get_ssh_info')
      autoload :GetState, action_root.join('get_state')
      autoload :IsCreated, action_root.join('is_created')
      autoload :IsRunning, action_root.join('is_running')
      autoload :MessageAlreadyCreated, action_root.join('message_already_created')
      autoload :MessageNotCreated, action_root.join('message_not_created')
      autoload :MessageNotRunning, action_root.join('message_not_running')
      autoload :PowerOff, action_root.join('power_off')
      autoload :PowerOn, action_root.join('power_on')
    end
  end
end
