require_relative '../rails_helper'

RSpec.describe 'Project custom field configuration', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  # --- Authorization (T-AUTH / T-UI-1) -----------------------------------
  describe 'settings tab visibility' do
    it 'shows the tab to an admin (T-AUTH-1)' do
      as(dcf_admin)
      get settings_project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('tab-custom_field_configuration')
    end

    it 'shows the tab to a permission holder (T-AUTH-2)' do
      as(dcf_manager(project))
      get settings_project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('tab-custom_field_configuration')
    end

    it 'hides the tab from a user without the permission (T-AUTH-3)' do
      role = dcf_create_role(permissions: [:edit_project])
      user = dcf_create_user('editor')
      dcf_add_member(user, project, role)
      as(user)
      get settings_project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('tab-custom_field_configuration')
    end
  end

  describe 'direct access control' do
    let(:field) { dcf_list_field(values: %w[A B], is_for_all: true) }

    it 'returns 403 to a non-member on a field action (T-AUTH-4)' do
      as(dcf_create_user('stranger'))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 403 for a manager acting on another project (T-AUTH-5)' do
      dcf_manager(project) # manager of `project`
      other = dcf_create_project(name: 'Other')
      manager = dcf_manager(project)
      as(manager)
      get custom_field_configuration_field_path(other, field)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # In Redmine, the "read-only" project state is CLOSED (read:true permissions
  # remain reachable); truly archived projects deny all access at the core
  # level. The require_active_project guard blocks writes on both.
  describe 'closed (read-only) projects (T-AUTH-7/9)' do
    let(:closed) { dcf_create_project(name: 'Closed', status: :closed) }
    let(:field) { dcf_list_field(values: %w[A B], is_for_all: true) }

    it 'allows reading the values screen' do
      as(dcf_manager(closed))
      get custom_field_configuration_field_path(closed, field)
      expect(response).to have_http_status(:ok)
    end

    it 'forbids write actions with error_project_archived' do
      as(dcf_manager(closed))
      post custom_field_configuration_add_value_path(closed, field), params: { value: 'C' }
      expect(response).to have_http_status(:forbidden)
      expect(field.reload.possible_values).to eq(%w[A B])
    end
  end

  # --- Relevance / format gating (T-REL / T-SET) -------------------------
  describe 'format and relevance gating' do
    it 'returns 422 for an unsupported format (T-REL-5)' do
      bool = IssueCustomField.create!(name: 'Bool', field_format: 'bool', is_for_all: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, bool)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 for a field not relevant to the project (T-REL-6)' do
      other = dcf_create_project(name: 'Other')
      field = dcf_list_field(is_for_all: false, projects: [other])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 for a standard field when the kill-switch is off (T-SET-2/T-REL-8)' do
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('manage_standard_custom_fields' => '0')
      field = dcf_list_field(format: 'list', is_for_all: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 on the dependency screen of a standard list (T-REL-9)' do
      field = dcf_list_field(format: 'list', is_for_all: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, field)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # --- Functional flows --------------------------------------------------
  describe 'value operations' do
    let(:field) { dcf_list_field(values: %w[A B], is_for_all: false, projects: [project]) }

    it 'adds a value and redirects back to the field screen' do
      as(dcf_manager(project))
      post custom_field_configuration_add_value_path(project, field), params: { value: 'C' }
      expect(response).to redirect_to(custom_field_configuration_field_path(project, field))
      expect(field.reload.possible_values).to eq(%w[A B C])
    end

    it 'reorders without JS via a form submit (T-UI-2)' do
      as(dcf_manager(project))
      patch custom_field_configuration_reorder_values_path(project, field),
            params: { ordered_values: %w[B A] }
      expect(response).to have_http_status(:redirect)
      expect(field.reload.possible_values).to eq(%w[B A])
    end

    it 'sets a default value via a form submit and redirects back (T-DEF-3)' do
      as(dcf_manager(project))
      patch custom_field_configuration_set_default_value_path(project, field),
            params: { default_value: 'B' }
      expect(response).to redirect_to(custom_field_configuration_field_path(project, field))
      expect(field.reload.default_value).to eq('B')
    end

    it 'rejects an out-of-range default value with 422 (T-DEF-3)' do
      as(dcf_manager(project))
      patch custom_field_configuration_set_default_value_path(project, field),
            params: { default_value: 'ZZ' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t(:error_invalid_default_value))
      expect(field.reload.default_value).to be_blank
    end

    it 'forbids setting a default on a closed project (T-DEF-3)' do
      closed = dcf_create_project(name: 'Closed2', status: :closed)
      closed_field = dcf_list_field(values: %w[A B], is_for_all: true)
      as(dcf_manager(closed))
      patch custom_field_configuration_set_default_value_path(closed, closed_field),
            params: { default_value: 'A' }
      expect(response).to have_http_status(:forbidden)
      expect(closed_field.reload.default_value).to be_blank
    end
  end

  describe 'screen rendering' do
    it 'renders the values screen for a list field with an add form' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t(:label_add_value))
    end

    it 'renders a default-value form on a non-child field (T-DEF-3)' do
      field = dcf_list_field(values: %w[A B], default_value: 'A', is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response.body).to include(I18n.t(:label_dcf_default_value))
      expect(response.body).to include('name="default_value"')
    end

    it 'omits the default-value form on a depending child field (T-DEF-3)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, child)
      expect(response.body).not_to include('name="default_value"')
    end

    it 'renders a multi-select per-parent default for a multiple child field (T-UI-7)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true, multiple: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, child)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="default_value_dependencies[A][]"')
      expect(response.body).to match(/<select[^>]*\bmultiple\b/)
    end

    it 'renders a single-select per-parent default for a single-value child field (T-UI-7)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true, multiple: false)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, child)
      expect(response.body).to include('name="default_value_dependencies[A]"')
    end

    it 'lists a relevant field on the overview with its format label (T-UI-6)' do
      dcf_list_field(format: 'depending_list', name: 'Listed', values: %w[A], is_for_all: true)
      as(dcf_admin)
      get settings_project_path(project)
      expect(response.body).to include('Listed')
      expect(response.body).not_to include('translation missing')
    end

    it 'renders the dependency matrix for a depending field with a parent (T-UI-4)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, child)
      expect(response).to have_http_status(:ok)
    end

    it 'saves a dependency mapping and redirects' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: true)
      as(dcf_manager(project))
      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => ['c1'] } }
      expect(response).to have_http_status(:redirect)
      expect(child.reload.value_dependencies).to eq('A' => ['c1'])
    end

    it 'saves multiple per-parent defaults submitted as an array (T-UI-7)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true, multiple: true)
      as(dcf_manager(project))
      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => %w[c1 c2] },
                      default_value_dependencies: { 'A' => %w[c1 c2] } }
      expect(response).to have_http_status(:redirect)
      expect(child.reload.default_value_dependencies).to eq('A' => %w[c1 c2])
    end

    it 'shows the confirmation panel for a cross-project rename (T-UI-3)' do
      field = dcf_list_field(values: %w[A B], is_for_all: true)
      as(dcf_manager(project))
      patch custom_field_configuration_rename_value_path(project, field),
            params: { old_value: 'A', new_value: 'A2' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t(:text_dcf_confirm_understand))
      expect(field.reload.possible_values).to eq(%w[A B])
    end
  end

  # --- Permission label (T-PERM-LABEL) -----------------------------------
  describe 'permission label' do
    it 'uses the short permission label' do
      expect(I18n.t(:permission_manage_project_custom_field_configuration)).to eq('Manage custom fields')
    end
  end

  # --- Security (T-SEC) --------------------------------------------------
  describe 'mass-assignment protection (T-SEC-1/2/3)' do
    it 'ignores out-of-scope params and changes only the value surface' do
      field = dcf_list_field(values: %w[A], is_for_all: true)
      as(dcf_manager(project))
      post custom_field_configuration_add_value_path(project, field),
           params: { value: 'B', field_format: 'bool', visible: '0', is_for_all: '0',
                     is_required: '1', editable: '1' }
      field.reload
      expect(field.possible_values).to eq(%w[A B])
      expect(field.field_format).to eq('list')
      expect(field.is_for_all).to be true
    end
  end

  # --- Audit table fail-closed (T-AUD-8) ---------------------------------
  describe 'missing audit table' do
    it 'fails closed with a 500 error' do
      field = dcf_list_field(is_for_all: true)
      allow(RedmineDependingCustomFields::ConfigAuditEvent).to receive(:table_exists?).and_return(false)
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  # --- Empty state (T-UI-5) ----------------------------------------------
  describe 'empty overview' do
    it 'renders the empty state when no fields are manageable' do
      as(dcf_admin)
      get settings_project_path(project)
      expect(response.body).to include(I18n.t(:text_no_manageable_custom_fields))
    end
  end
end
