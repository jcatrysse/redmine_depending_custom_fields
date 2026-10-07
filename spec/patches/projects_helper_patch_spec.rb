require_relative '../rails_helper'

# The settings-tab patch must chain through super (prepend), because other
# plugins (redmine_agile, redmine_contacts) prepend on project_settings_tabs as
# well. The old alias_method chain, loaded after such a prepend, captured the
# other plugin's method instead of core's and Project → Settings raised
# NoMethodError (super). See Integration Spec §4 and T-INT-4.
RSpec.describe RedmineDependingCustomFields::Patches::ProjectsHelperPatch do
  let(:patch) { described_class }
  let(:project) { dcf_create_project(name: 'Tabs') }

  def tab_names(host)
    host.project_settings_tabs.map { |t| t[:name] }
  end

  describe 'on ProjectsHelper' do
    # What the settings view sees: ProjectsHelper as loaded, with every patch.
    let(:helper) do
      host = Object.new.extend(ProjectsHelper)
      host.define_singleton_method(:params) { {} }
      host.instance_variable_set(:@project, project)
      host
    end

    after { User.current = nil }

    it 'is prepended, and core project_settings_tabs is left as core defines it' do
      expect(ProjectsHelper.ancestors.index(patch)).to be < ProjectsHelper.ancestors.index(ProjectsHelper)

      owners = []
      method = ProjectsHelper.instance_method(:project_settings_tabs)
      while method
        owners << method.owner
        method = method.super_method
      end
      expect(owners).to include(patch)
      expect(owners.last).to eq(ProjectsHelper)
      core = ProjectsHelper.instance_method(:project_settings_tabs)
      core = core.super_method until core.owner == ProjectsHelper
      expect(core.source_location.first).to eq(Rails.root.join('app/helpers/projects_helper.rb').to_s)
    end

    it 'keeps the dcf_* view helpers available in the settings view' do
      expect(ProjectsHelper.include?(ProjectCustomFieldConfigurationHelper)).to be true
      expect(ProjectsController._helpers.include?(ProjectCustomFieldConfigurationHelper)).to be true
      expect(helper).to respond_to(:dcf_field_scope)
    end

    # Through ProjectsHelper alone the helpers did not reach
    # ProjectsController::HelperMethods once redmine_custom_workflows had loaded
    # ProjectsController first (HTTP 500, undefined dcf_relevant_custom_fields),
    # so they are registered on the controller itself.
    it 'registers the dcf_* view helpers on ProjectsController directly' do
      expect(ProjectsController).to receive(:helper).with(ProjectCustomFieldConfigurationHelper).and_call_original
      load File.expand_path('../../lib/redmine_depending_custom_fields/patches/projects_helper_patch.rb', __dir__)
    end

    it 'shows the tab to an admin' do
      User.current = dcf_admin
      expect(tab_names(helper)).to include('info', 'custom_field_configuration')
    end

    it 'shows the tab to a member holding the permission' do
      User.current = dcf_manager(project)
      expect(tab_names(helper)).to include('custom_field_configuration')
    end

    it 'hides the tab from a member without the permission' do
      User.current = dcf_plain_member(project)
      expect(tab_names(helper)).not_to include('custom_field_configuration')
    end

    it 'hides the tab from a non-member' do
      User.current = dcf_create_user("out-#{SecureRandom.hex(3)}")
      expect(tab_names(helper)).not_to include('custom_field_configuration')
    end
  end

  # A stand-in for ProjectsHelper with another plugin's prepend on the same
  # method, in the load order that broke (the other plugin first).
  describe 'next to another plugin patching the same method' do
    let(:core) do
      Module.new do
        def project_settings_tabs
          [{ name: 'info' }]
        end
      end
    end
    let(:other_plugin) do
      Module.new do
        def project_settings_tabs
          super << { name: 'other_plugin' }
        end
      end
    end

    def host_for(mod)
      host = Object.new.extend(mod)
      host.instance_variable_set(:@project, project)
      host
    end

    before { User.current = dcf_admin }
    after { User.current = nil }

    it 'chains through the other plugin when that one was loaded first' do
      core.prepend(other_plugin)
      core.prepend(patch)
      expect(tab_names(host_for(core))).to eq(%w[info other_plugin custom_field_configuration])
    end

    it 'chains through the other plugin when that one is loaded after' do
      core.prepend(patch)
      core.prepend(other_plugin)
      expect(tab_names(host_for(core))).to eq(%w[info custom_field_configuration other_plugin])
    end

    it 'adds the tab once when applied twice (no recursion)' do
      core.prepend(other_plugin)
      core.prepend(patch)
      core.prepend(patch)
      expect(tab_names(host_for(core))).to eq(%w[info other_plugin custom_field_configuration])
    end
  end
end
