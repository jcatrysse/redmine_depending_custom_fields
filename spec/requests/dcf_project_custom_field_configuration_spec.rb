require_relative '../rails_helper'
require 'ripper'

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

    # The sortable submits a plain form PATCH, so this covers the endpoint
    # contract independently of any JS driver (T-UI-2).
    it 'reorders via a form submit (T-UI-2)' do
      as(dcf_manager(project))
      patch custom_field_configuration_reorder_values_path(project, field),
            params: { ordered_values: %w[B A] }
      expect(response).to have_http_status(:redirect)
      expect(field.reload.possible_values).to eq(%w[B A])
    end

    # Regression for the UX defect this change fixes: moving a value across
    # several positions used to need one round trip per step. A drag submits the
    # whole target order at once — one request, one audit event (T-ORD-6).
    it 'moves a value across several positions in a single request (T-ORD-6)' do
      long = dcf_list_field(values: %w[A B C D E], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      patch custom_field_configuration_reorder_values_path(project, long),
            params: { ordered_values: %w[E A B C D],
                      state_hash: RedmineDependingCustomFields::BaseService.state_hash(long) }
      expect(response).to redirect_to(custom_field_configuration_field_path(project, long))
      expect(long.reload.possible_values).to eq(%w[E A B C D])
    end

    it 'moves an enumeration value across several positions in one request (T-ORD-7)' do
      enum = dcf_enum_field(names: %w[X Y Z])
      ids = enum.enumerations.order(:position).map { |e| e.id.to_s }
      as(dcf_manager(project))
      patch custom_field_configuration_reorder_values_path(project, enum),
            params: { ordered_values: [ids[2], ids[0], ids[1]],
                      state_hash: RedmineDependingCustomFields::BaseService.state_hash(enum) }
      expect(response).to have_http_status(:redirect)
      expect(enum.reload.enumerations.order(:position).map(&:name)).to eq(%w[Z X Y])
    end

    it 'rejects a drag submitted against a stale state_hash (T-CONC-1)' do
      as(dcf_manager(project))
      patch custom_field_configuration_reorder_values_path(project, field),
            params: { ordered_values: %w[B A], state_hash: 'stale' }
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include(I18n.t(:error_stale_edit))
      expect(field.reload.possible_values).to eq(%w[A B])
    end

    it 'rejects an incomplete order without touching the values (T-ORD-3)' do
      as(dcf_manager(project))
      patch custom_field_configuration_reorder_values_path(project, field),
            params: { ordered_values: %w[B] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t(:error_reorder_mismatch))
      expect(field.reload.possible_values).to eq(%w[A B])
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

  # --- Enumeration batch editor (T-ACT) ----------------------------------
  describe 'enumeration values screen' do
    let(:enum_field) { dcf_enum_field(names: %w[X Y]) }
    let(:first_value) { enum_field.enumerations.order(:position).first }

    # Attribute order differs between Rails versions, so match on the tag's
    # attributes rather than on a literal rendering.
    def inputs(body, type, name)
      body.scan(/<input\b[^>]*>/)
          .select { |i| i.include?(%(name="#{name}")) && i.include?(%(type="#{type}")) }
    end

    def payload(field, overrides = {})
      params = {}
      field.enumerations.order(:position).each_with_index do |enum, idx|
        over = overrides[enum.id] || {}
        params[enum.id.to_s] = {
          name: over.fetch(:name, enum.name),
          position: over.fetch(:position, idx + 1).to_s,
          active: (over.key?(:active) ? over[:active] : enum.active?) ? '1' : '0'
        }
      end
      params
    end

    it 'renders one batch form with a single Save for the whole table (T-ACT-13)' do
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, enum_field)
      expect(response).to have_http_status(:ok)
      form = response.body[%r{<form[^>]*dcf-enumerations-form.*?</form>}m]
      expect(form).to be_present
      expect(form).to include('/enumerations')
      # Exactly one submit button in the whole table form — core's shape.
      expect(form.scan(/<input[^>]*type="submit"/).length).to eq(1)
      # Per row: a hidden position, a hidden active "0" and the checkbox.
      enum_field.enumerations.each do |e|
        expect(form).to include(%(name="enumerations[#{e.id}][position]"))
        expect(form).to include(%(name="enumerations[#{e.id}][name]"))
        expect(inputs(form, 'hidden', "enumerations[#{e.id}][active]").first).to include('value="0"')
        expect(inputs(form, 'checkbox', "enumerations[#{e.id}][active]").length).to eq(1)
      end
      # The static Yes/No readout is replaced by the control itself.
      expect(response.body).not_to include("<td>#{I18n.t(:general_text_Yes)}</td>")
    end

    it 'reflects the current state in the checkboxes (T-ACT-13)' do
      first_value.update!(active: false)
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, enum_field)
      boxes = enum_field.enumerations.order(:position).map do |e|
        inputs(response.body, 'checkbox', "enumerations[#{e.id}][active]").first
      end
      expect(boxes.compact.length).to eq(2)
      expect(boxes.count { |b| b.include?('checked') }).to eq(1)
    end

    # Delete must be a link, not a nested form: forms cannot nest, and this is
    # exactly what core's delete_link does on the same screen.
    it 'renders Delete as a link inside the batch form (T-ACT-25)' do
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, enum_field)
      form = response.body[%r{<form[^>]*dcf-enumerations-form.*?</form>}m]
      expect(form.scan('<form').length).to eq(1)    # the outer form only, none nested
      expect(form).to include('data-method="delete"')
      expect(form).to include(%(enumeration_id=#{first_value.id}))
    end

    # The enumeration table stages positions in its own form; only the list
    # family still submits a drag straight away.
    it 'stages positions instead of shipping a reorder form (T-ACT-26)' do
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, enum_field)
      expect(response.body).to include('class="dcf-position"')
      expect(response.body).not_to include('dcf-reorder-form')
      expect(response.body.scan('dcf-sort-handle').length).to eq(2)
    end

    it 'leaves the list family on its per-row forms and live drag (T-ACT-26)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response.body).not_to include('dcf-enumerations-form')
      expect(response.body).not_to include('class="dcf-position"')
      expect(response.body).to include('dcf-reorder-form')
    end

    it 'saves a deactivation and reports it in the flash (T-ACT-1)' do
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { active: false }),
                      state_hash: RedmineDependingCustomFields::BaseService.state_hash(enum_field) }
      expect(response).to redirect_to(custom_field_configuration_field_path(project, enum_field))
      expect(flash[:notice]).to eq(I18n.t(:notice_values_saved))
      expect(first_value.reload.active).to be false
    end

    it 'saves a rename, a deactivation and a reorder together (T-ACT-20)' do
      x, y = enum_field.enumerations.order(:position).to_a
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field,
                                            x.id => { name: 'X2', position: 2, active: false },
                                            y.id => { position: 1 }) }
      expect(response).to have_http_status(:redirect)
      expect(enum_field.reload.enumerations.order(:position).map(&:name)).to eq(%w[Y X2])
      expect(x.reload.active).to be false
    end

    it 'drops a deactivated value from the default-value picker (T-ACT-14)' do
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { active: false }) }
      get custom_field_configuration_field_path(project, enum_field)
      picker = response.body[%r{<select[^>]*name="default_value".*?</select>}m]
      expect(picker).to be_present
      expect(picker).not_to include(%(value="#{first_value.id}"))
      expect(picker).to include(%(value="#{enum_field.enumerations.order(:position).last.id}"))
    end

    # Empty-state guard: every value can legitimately be switched off, and the
    # screen (rows, default picker, add form) must still render.
    it 'still renders the screen when every value is deactivated (T-ACT-16)' do
      enum_field.enumerations.update_all(active: false)
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, enum_field)
      expect(response).to have_http_status(:ok)
      boxes = enum_field.enumerations.map { |e| inputs(response.body, 'checkbox', "enumerations[#{e.id}][active]").first }
      expect(boxes.compact.length).to eq(2)
      expect(boxes.none? { |b| b.include?('checked') }).to be true
      expect(response.body).to include(I18n.t(:text_dcf_no_default))
      expect(response.body).to include(I18n.t(:label_add_value))
    end

    it 'returns 422 on a list field (T-ACT-3)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, field),
            params: { enumerations: {} }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t(:error_format_unsupported))
    end

    it 'returns 422 for a submit that does not cover every row (T-ACT-21)' do
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field).except(first_value.id.to_s) }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t(:error_reorder_mismatch))
    end

    it 'returns 422 and keeps everything on a blank name (T-ACT-22)' do
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { name: '  ' }) }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t(:error_value_blank))
      expect(first_value.reload.name).to eq('X')
    end

    it 'returns 409 on a stale state_hash (T-ACT-9)' do
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { active: false }),
                      state_hash: 'stale' }
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include(I18n.t(:error_stale_edit))
      expect(first_value.reload.active).to be true
    end

    it 'returns 403 for a user without the permission (T-ACT-12)' do
      as(dcf_create_user('outsider'))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { active: false }) }
      expect(response).to have_http_status(:forbidden)
      expect(first_value.reload.active).to be true
    end

    it 'forbids the save on a closed project (T-ACT-15)' do
      closed = dcf_create_project(name: 'ClosedAct', status: :closed)
      as(dcf_manager(closed))
      patch custom_field_configuration_update_enumerations_path(closed, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { active: false }) }
      expect(response).to have_http_status(:forbidden)
      expect(first_value.reload.active).to be true
    end

    it 'ignores out-of-scope params on the batch save (T-SEC-1)' do
      as(dcf_manager(project))
      patch custom_field_configuration_update_enumerations_path(project, enum_field),
            params: { enumerations: payload(enum_field, first_value.id => { active: false }),
                      field_format: 'bool', is_for_all: '0', is_required: '1' }
      enum_field.reload
      expect(enum_field.field_format).to eq('enumeration')
      expect(enum_field.is_for_all).to be true
      expect(enum_field.is_required).to be false
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

    # Changed by WP-27 (was: the matrix select default_value_dependencies[A][]
    # with multiple): the editor root carries the multiple flag, the form
    # posts only dependencies_json.
    it 'renders the editor in project mode for a multiple child field (T-UI-7)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true, multiple: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, child)
      expect(response).to have_http_status(:ok)
      root = Nokogiri::HTML(response.body).at_css('form[enctype="multipart/form-data"] fieldset[data-dcf-editor]')
      expect([root['data-dcf-editor-mode'], root['data-dcf-editor-multiple']]).to eq(%w[project 1])
      expect(response.body).to include('name="dependencies_json"')
      expect(response.body).not_to include('default_value_dependencies[')
      expect(response.body).not_to include('data-dcf-parent-values')
    end

    # Changed by WP-27 (was: the matrix select default_value_dependencies[A]).
    it 'renders the editor in project mode for a single-value child field (T-UI-7)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true, multiple: false)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, child)
      root = Nokogiri::HTML(response.body).at_css('form[enctype="multipart/form-data"] fieldset[data-dcf-editor]')
      expect([root['data-dcf-editor-mode'], root['data-dcf-editor-multiple']]).to eq(%w[project 0])
      expect(response.body).to include('name="dependencies_json"')
      expect(response.body).not_to include('default_value_dependencies[')
      expect(response.body).not_to include('data-dcf-parent-values')
    end

    it 'lists a relevant field on the overview with its format label (T-UI-6)' do
      dcf_list_field(format: 'depending_list', name: 'Listed', values: %w[A], is_for_all: true)
      as(dcf_admin)
      get settings_project_path(project)
      expect(response.body).to include('Listed')
      expect(response.body).not_to include('translation missing')
    end

    # Changed by WP-27 (was: the dependency matrix, status 200 only): the
    # editor root, its assets once each from the head hook. Changed by WP-28
    # (was: the body does not include dcf_config): dcf_config.css exactly
    # once, from the view (T-ASSET-1).
    it 'renders the dependency editor for a depending field with a parent (T-UI-4)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: true)
      as(dcf_manager(project))
      get custom_field_configuration_field_dependencies_path(project, child)
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css('fieldset[data-dcf-editor][data-dcf-editor-mode="project"]').size).to eq(1)
      asset = ->(name, ext) { /#{name}(-[0-9a-f]{7,}\.#{ext}|\.#{ext}\?\d+)\z/ }
      srcs = doc.css('script[src]').map { |node| node['src'] }
      hrefs = doc.css('link[rel=stylesheet]').map { |node| node['href'] }
      expect(srcs.grep(asset.call('dcf_dependency_editor', 'js')).size).to eq(1)
      expect(srcs.grep(asset.call('dcf_dependency_editor_model', 'js')).size).to eq(1)
      expect(hrefs.grep(asset.call('dcf_dependency_editor', 'css')).size).to eq(1)
      expect(hrefs.grep(asset.call('dcf_config', 'css')).size).to eq(1)
    end

    # Renamed by WP-27 (was: 'saves a dependency mapping and redirects').
    # Changed by WP-34 (UD-23): confirm '1' on the global child; was no confirm.
    it 'saves a dependency mapping and redirects (legacy nested params, deprecated)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: true)
      as(dcf_manager(project))
      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => ['c1'] }, confirm: '1' }
      expect(response).to have_http_status(:redirect)
      expect(child.reload.value_dependencies).to eq('A' => ['c1'])
    end

    # Renamed by WP-27 (was: '... submitted as an array (T-UI-7)').
    # Changed by WP-34 (UD-23): confirm '1' on the global child; was no confirm.
    it 'saves multiple per-parent defaults submitted as an array (T-UI-7, legacy nested params, deprecated)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true, multiple: true)
      as(dcf_manager(project))
      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => %w[c1 c2] },
                      default_value_dependencies: { 'A' => %w[c1 c2] }, confirm: '1' }
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

  # --- Drag-and-drop reorder markup (T-ORD-8..12) ------------------------
  # No JS driver is available (Test Plan §"no test may depend on a JS driver"),
  # so the sortable is covered by asserting the hooks it needs.
  describe 'reorder affordances on the values screen' do
    it 'renders drag handles, the reorder form and the sortable script (T-ORD-8)' do
      field = dcf_list_field(values: %w[A B C], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/dcf_value_reorder.*\.js/)
      expect(response.body).to include('class="list dcf-values"')
      expect(response.body).to include('dcf-reorder-form')
      expect(response.body.scan('dcf-sort-handle').length).to eq(3)
      expect(response.body).to include('data-dcf-value="A"')
    end

    # The drag handle is the only reorder control, exactly as in core — no
    # Redmine version ships up/down reorder buttons (`reorder_links` does not
    # exist in 5.1-7.0; only `reorder_handle` does).
    it 'renders no per-row up/down reorder buttons (T-ORD-13)' do
      field = dcf_list_field(values: %w[A B C], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      # One reorder form for the sortable; no button_to forms posting to it.
      expect(response.body.scan('dcf-reorder-form').length).to eq(1)
      expect(response.body.scan(%r{class="button_to"[^>]*action="[^"]*values/reorder"}).length).to eq(0)
      expect(response.body).not_to include('Move up')
      expect(response.body).not_to include('Move down')
    end

    it 'identifies enumeration rows by id (T-ORD-9)' do
      enum = dcf_enum_field(names: %w[X Y])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, enum)
      expect(response).to have_http_status(:ok)
      enum.enumerations.each { |e| expect(response.body).to include(%(data-dcf-value="#{e.id}")) }
      expect(response.body.scan('dcf-sort-handle').length).to eq(2)
    end

    it 'omits the handle and the reorder form when there is nothing to reorder (T-ORD-10)' do
      field = dcf_list_field(values: %w[Only], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('dcf-sort-handle')
      expect(response.body).not_to include('dcf-reorder-form')
    end

    # The drag target form is submitted natively by the sortable, so it must
    # carry its own CSRF token. Forgery protection is disabled in the test env,
    # which would hide a missing token until production (T-ORD-12).
    it 'includes an authenticity token in the drag target form (T-ORD-12)' do
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      form = response.body[%r{<form[^>]*dcf-reorder-form.*?</form>}m]
      expect(form).to be_present
      expect(form).to include('name="authenticity_token"')
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it 'escapes value identifiers in the row data attribute (T-ORD-11)' do
      field = dcf_list_field(values: ['A', '"><script>alert(1)</script>'],
                             is_for_all: false, projects: [project])
      as(dcf_manager(project))
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('<script>alert(1)</script>')
      expect(response.body).to include('data-dcf-value="&quot;&gt;&lt;script&gt;')
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

  # --- Storage errors and flash escaping (WP-12, SP-06, SP-09) -----------
  # The page heading prints the field name escaped as well, so the checks
  # target the flash box.
  describe 'storage errors on project pages (WP-12)' do
    let(:limits) { RedmineDependingCustomFields::StorageLimits }
    let(:markup) { '<img src=x onerror=alert(1)>' }
    let(:secret_sql) do
      "Mysql2::Error: Data too long for column 'possible_values' at row 1: " \
        "UPDATE `custom_fields` SET `possible_values` = '--- SECRET_VALUE_42'"
    end

    def stub_limit_at_stored(column, field)
      bytes = CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql).bytesize
      allow(limits).to receive(:column_limit).and_return(nil)
      allow(limits).to receive(:column_limit).with(column).and_return(bytes)
    end

    def flash_box
      Nokogiri::HTML(response.body).at_css('#flash_error')
    end

    def expect_escaped_flash(name)
      expect(response).to have_http_status(422)
      box = flash_box
      expect(box).not_to be_nil
      expect(box.css('img')).to be_empty
      expect(box.inner_html).to include(ERB::Util.html_escape(name))
      expect(box.text).to include(name)
      expect(response.body).not_to include('&amp;lt;')
      expect(response.body).not_to include(name)
    end

    it 'escapes the field name once in the values page flash (T-SIZE-1, T-DEPJ-22)' do
      field = dcf_list_field(name: markup, values: %w[A B], is_for_all: false, projects: [project])
      stub_limit_at_stored('possible_values', field)
      as(dcf_manager(project))

      post custom_field_configuration_add_value_path(project, field), params: { value: 'SECRET_VAL_9' }

      expect_escaped_flash(markup)
      size = limits.serialized_bytesize(CustomField, 'possible_values', %w[A B SECRET_VAL_9])
      limit = limits.column_limit('possible_values')
      expect(flash_box.text.strip).to eq(I18n.t(:error_dcf_values_too_large, field: markup,
                                                size: limits.delimited(size), limit: limits.delimited(limit)))
      expect(response.body).not_to include('SECRET_VAL_9')
      expect(field.reload.possible_values).to eq(%w[A B])
    end

    it 'escapes the field name once in the German flash with German number delimiters' do
      values = ['A', 'B' * 1_200]
      field = dcf_list_field(name: markup, values: values, is_for_all: false, projects: [project])
      stub_limit_at_stored('possible_values', field)
      manager = dcf_manager(project)
      manager.update_column(:language, 'de')
      as(manager)
      # Changed by WP-31 (was: 1,500 characters): a new value has at most
      # 255 characters (error_dcf_value_length).
      added = 'C' * 255

      # The request switches the locale; with_locale puts it back.
      I18n.with_locale(I18n.locale) do
        post custom_field_configuration_add_value_path(project, field), params: { value: added }
      end

      expect_escaped_flash(markup)
      expect(flash_box.text).to include("Die Werte des Feldes \u201E#{markup}\u201C")
      size, limit = I18n.with_locale(:de) do
        [limits.delimited(limits.serialized_bytesize(CustomField, 'possible_values', values + [added])),
         limits.delimited(limits.column_limit('possible_values'))]
      end
      expect([size, limit]).to all(include('.'))
      expect(flash_box.text.strip)
        .to eq(I18n.t(:error_dcf_values_too_large, locale: :de, field: markup, size: size, limit: limit))
    end

    it 'shows the storage failure escaped on the project audit page' do
      field = dcf_list_field(name: markup, values: %w[A B], is_for_all: false, projects: [project])
      stub_limit_at_stored('possible_values', field)
      as(dcf_manager(project))
      post custom_field_configuration_add_value_path(project, field), params: { value: 'C' }

      get custom_field_configuration_audit_path(project)

      expect(response).to have_http_status(200)
      table = Nokogiri::HTML(response.body).at_css('table')
      expect(table.css('img')).to be_empty
      expect(table.text).to include(markup)
      expect(table.text).to match(/possible_values: \d+ bytes exceeds \d+ \(custom field #\d+\)/)
    end

    # Changed by WP-34 (UD-23): confirm '1' (global child; the storage error
    # comes only on a confirmed save); was no confirm.
    it 'escapes the field name once in the dependency page flash (T-SIZE-2)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: markup, values: %w[c1], parent: parent, is_for_all: true)
      stub_limit_at_stored('format_store', child)
      as(dcf_manager(project))

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => ['c1'] }, confirm: '1' }

      expect_escaped_flash(markup)
      expect(child.reload.value_dependencies).to eq({})
    end

    it 'names a visible child of a rename cascade, escaped once' do
      parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: markup, values: %w[c1], parent: parent, is_for_all: true)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1] })
      stub_limit_at_stored('format_store', child)
      as(dcf_manager(project))

      patch custom_field_configuration_rename_value_path(project, parent),
            params: { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }

      expect_escaped_flash(markup)
      expect(parent.reload.possible_values).to eq(%w[A B])
    end

    it 'never names a child hidden from the manager role' do
      parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Secret child', values: %w[c1], parent: parent,
                             is_for_all: true)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1] })
      child.update!(visible: false, role_ids: [dcf_create_role.id])
      stub_limit_at_stored('format_store', child)
      as(dcf_manager(project))

      patch custom_field_configuration_rename_value_path(project, parent),
            params: { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }

      expect(response).to have_http_status(422)
      expect(flash_box.text.strip).to eq(I18n.t(:error_save_failed))
      expect(response.body).not_to include('Secret child')
      row = RedmineDependingCustomFields::ConfigAuditEvent.order(:id).last
      expect([row.status, row.error_message]).to eq(%w[validation_failed error_dcf_mapping_too_large])
    end

    it 'shows the ValueTooLong text without database content (T-SIZE-4, SP-09)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      allow_any_instance_of(IssueCustomField).to receive(:save!)
        .and_raise(ActiveRecord::ValueTooLong.new(secret_sql, sql: secret_sql))
      log = StringIO.new
      logger = ActiveSupport::Logger.new(log)
      allow(Rails).to receive(:logger).and_return(logger)
      as(dcf_manager(project))

      # The controller and SQL loggers are set at boot, not read from Rails.logger.
      saved = [ActionController::Base.logger, ActiveRecord::Base.logger]
      begin
        ActionController::Base.logger = logger
        ActiveRecord::Base.logger = logger
        post custom_field_configuration_add_value_path(project, field), params: { value: 'C' }
      ensure
        ActionController::Base.logger, ActiveRecord::Base.logger = saved
      end

      expect(log.string).to include('Processing by ProjectCustomFieldConfigurationController#add_value')
      expect(log.string).to include('dcf_config_audit_events')
      expect(response).to have_http_status(422)
      expect(flash_box.text.strip).to eq(I18n.t(:error_dcf_value_too_long))
      # Core writes user_preferences with an UPDATE, so the log check names the table.
      ['SECRET_VALUE_42', 'Data too long', 'UPDATE `custom_fields`', 'Mysql2'].each do |text|
        expect(response.body).not_to include(text)
        expect(log.string).not_to include(text)
      end
      expect(response.body).not_to include('UPDATE')
      expect(field.reload.possible_values).to eq(%w[A B])
    end

    it 'keeps 409 for a stale dependency save (dcf_status_code)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1], parent: parent, is_for_all: true)
      as(dcf_manager(project))

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => ['c1'] }, state_hash: 'stale' }

      expect(response).to have_http_status(409)
      expect(flash_box.text.strip).to eq(I18n.t(:error_stale_edit))
    end

    it 'keeps 422 with the unchanged text for a rejected value' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      as(dcf_manager(project))

      post custom_field_configuration_add_value_path(project, field), params: { value: 'A' }

      expect(response).to have_http_status(422)
      expect(flash_box.text.strip).to eq(I18n.t(:error_value_duplicate))
    end

    it 'escapes the render_error message once (fr, an apostrophe)' do
      field = dcf_list_field(values: %w[A B], is_for_all: true)
      allow(RedmineDependingCustomFields::ConfigAuditEvent).to receive(:table_exists?).and_return(false)
      manager = dcf_manager(project)
      manager.update_column(:language, 'fr')
      as(manager)

      # The request switches the locale; with_locale puts it back.
      I18n.with_locale(I18n.locale) do
        get custom_field_configuration_field_path(project, field)
      end

      expect(response).to have_http_status(500)
      text = I18n.t(:error_dcf_audit_table_missing, locale: :fr)
      expect(text).to include("'")
      expect(response.body).to include('La table d&#39;audit')
      expect(response.body).not_to include('&amp;#39;')
      expect(Nokogiri::HTML(response.body).at_css('#errorExplanation').text.strip).to eq(text)
    end
  end

  describe 'translate_error (SP-06)' do
    let(:subject_controller) { ProjectCustomFieldConfigurationController.new }

    def translate(error_or_key)
      subject_controller.send(:translate_error, error_or_key)
    end

    def storage_error(field)
      RedmineDependingCustomFields::OperationError.new(:error_dcf_values_too_large,
                                                       interpolations: { field: field, size: '1', limit: '2' })
    end

    it 'escapes every interpolation exactly once and returns a plain String' do
      out = translate(storage_error('<b>&'))
      expect(out).to include('&lt;b&gt;&amp;')
      expect(out).not_to include('&amp;lt;')
      expect(out.class).to eq(String)
      expect(out).not_to be_html_safe
      expect(translate(storage_error('R&D'))).to include('R&amp;D')
      expect(translate(storage_error('R&D'))).not_to include('R&amp;amp;D')
    end

    it 'escapes an html_safe value as well' do
      expect(translate(storage_error('<b>x</b>'.html_safe))).to include('&lt;b&gt;x&lt;/b&gt;')
    end

    it 'turns every value into text without calling it' do
      expect(translate(storage_error(5))).to include('"5"')
      expect(translate(storage_error(nil))).to include('""')
      expect(translate(storage_error('%{limit}'))).to include('"%{limit}"')
      expect(translate(storage_error(-> { raise 'called' }))).to include('Proc')
    end

    it 'drops I18n option keys, the locale included, from the interpolations' do
      text = I18n.t(:error_dcf_values_too_large, field: 'F', size: '1', limit: '2')
      [{ scope: 'evil', default: 'x' }, { locale: 'de' }, { 'locale' => 'zz' }, { raise: true }].each do |options|
        error = RedmineDependingCustomFields::OperationError.new(
          :error_dcf_values_too_large, interpolations: { field: 'F', size: '1', limit: '2' }.merge(options)
        )
        expect(translate(error)).to eq(text)
      end
    end

    it 'keeps the text of a Symbol and falls back to the key' do
      expect(translate(:error_stale_edit)).to eq(I18n.t(:error_stale_edit))
      expect(translate(RedmineDependingCustomFields::OperationError.new(:error_stale_edit)))
        .to eq(I18n.t(:error_stale_edit))
      expect(translate(:missing_key)).to eq('missing_key')
    end

    it 'translates every error key of the services in the four locales' do
      dir = File.expand_path('../../app/services/redmine_depending_custom_fields', __dir__)
      keys = Dir[File.join(dir, '*.rb')].flat_map { |file| File.read(file).scan(/:(error_\w+)/).flatten }.uniq
      expect(keys).to include('error_dcf_values_too_large', 'error_dcf_mapping_too_large', 'error_dcf_value_too_long')
      %w[en de fr nl].each do |locale|
        I18n.with_locale(locale) do
          keys.each do |key|
            # Changed by WP-31: error_dcf_value_length interpolates max.
            error = RedmineDependingCustomFields::OperationError.new(
              key.to_sym, interpolations: { field: 'F', size: '1', limit: '2', max: '255' }
            )
            out = translate(error)
            expect(out).to be_a(String)
            expect(out).not_to include('translation missing')
            expect(out).not_to eq(key)
          end
        end
      end
    end

    # A static scan without the comments; an assignment or a call may span
    # lines, and l( may appear only in translate_error itself.
    it 'sends every flash and error page message through translate_error (S4)' do
      file = File.expand_path('../../app/controllers/project_custom_field_configuration_controller.rb', __dir__)
      tokens = Ripper.lex(File.read(file))
      source = tokens.map { |token| token[1] == :on_comment ? token[2][/\n\z/].to_s : token[2] }.join
      flashes = source.scan(/\bflash(?:\.now)?\[[^\]]*\]\s*=\s*(\w+)/).flatten
      expect(flashes.size).to be >= 5
      expect(flashes.size).to eq(source.scan(/\bflash(?:\.now)?\[/).size)
      expect(flashes.uniq).to eq(['translate_error'])
      errors = source.scan(/\brender_error\(\s*message:\s*(\w+)/).flatten
      expect(errors.size).to eq(source.scan(/\brender_error\(/).size)
      expect(errors.uniq).to eq(['translate_error'])
      expect(source).not_to match(/translate_error\(e\.key/)
      helper = source[/^  def translate_error\b.*?^  end$/m]
      expect(helper).to match(/\bl\(/)
      expect(source.sub(helper, '')).not_to match(/\bl\(/)
    end
  end

  # --- WP-27: the dependency page on the shared editor -------------------
  # Project design 3 and 15 (T-DEPJ-1..25), editor design 7, UD-16, UD-17,
  # UD-23, SP-01, SP-17, SP-20b, gap 1, gap 2.
  describe 'dependency page on the shared editor (WP-27)' do
    include DcfStoredCycle

    let(:payload) { RedmineDependingCustomFields::DependencyPayload }
    let(:limits) { RedmineDependingCustomFields::StorageLimits }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
    let(:max_bytes) { payload::MAX_BYTES }
    let(:manager) { dcf_manager(project) }
    let(:multipart) { { 'CONTENT_TYPE' => 'multipart/form-data' } }
    let(:parent) { dcf_list_field(name: "Country-#{SecureRandom.hex(3)}", values: %w[Belgium France Germany]) }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}",
                             values: %w[Antwerp Brussels Paris Lyon], parent: parent)
      dcf_set_dependencies(field, value_dependencies: { 'Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris] },
                                  default_value_dependencies: { 'Belgium' => 'Brussels' })
    end
    let(:original) { [{ 'Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris] }, { 'Belgium' => 'Brussels' }] }

    before { as(manager) }

    def doc
      Nokogiri::HTML(response.body)
    end

    def root
      doc.at_css('fieldset[data-dcf-editor]')
    end

    def attr_json(name)
      JSON.parse(root["data-dcf-editor-#{name}"])
    end

    def hidden_values
      doc.css('input[name="dependencies_json"]').map { |input| [input['id'], input['value']] }
    end

    def flash_error
      doc.at_css('#flash_error').text.strip
    end

    def rendered_state_hash
      doc.at_css('input[name="state_hash"]')['value']
    end

    def state_hash(field)
      RedmineDependingCustomFields::BaseService.state_hash(CustomField.find(field.id))
    end

    def json(vd, dd = {}, extra = {})
      JSON.generate({ 'value_dependencies' => vd, 'default_value_dependencies' => dd }.merge(extra))
    end

    def stored(field)
      record = CustomField.find(field.id)
      [record.value_dependencies.to_hash, record.default_value_dependencies.to_hash]
    end

    def stored_mapping(field)
      vd, dd = stored(field)
      { 'value_dependencies' => vd, 'default_value_dependencies' => dd }
    end

    def raw_store(field)
      CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
    end

    def rows(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def page_path(field, in_project = project)
      custom_field_configuration_field_dependencies_path(in_project, field)
    end

    # The browser's PATCH: multipart, the current state hash unless given.
    def save(field, raw, state: nil, extra: {}, in_project: project)
      params = { dependencies_json: raw, state_hash: state || state_hash(field) }.merge(extra)
      patch custom_field_configuration_update_dependencies_path(in_project, field), params: params, headers: multipart
    end

    def stub_limit_at_stored(field)
      bytes = raw_store(field).bytesize
      allow(limits).to receive(:column_limit).and_return(nil)
      allow(limits).to receive(:column_limit).with('format_store').and_return(bytes)
    end

    def data_names(node)
      node.attribute_nodes.map(&:name)
    end

    # Writes a mapping as stored data (orphans included), without callbacks.
    def store_raw(field, vd, dd = {})
      store = CustomField.find(field.id).format_store.to_hash
                         .merge('value_dependencies' => vd, 'default_value_dependencies' => dd)
      CustomField.where(id: field.id)
                 .update_all(['format_store = ?', CustomField.type_for_attribute('format_store').serialize(store)])
      CustomField.find(field.id)
    end

    describe 'GET' do
      # Changed by WP-34 (UD-23): the child is global, so the form also holds
      # the unchecked required confirm box (6 names at most); was at most 5
      # names without confirm.
      it 'renders the editor in a multipart PATCH form with a blank input, the stored mapping and Save disabled ' \
         '(T-DEPJ-10, T-DEPJ-19, UD-16)' do
        get page_path(child)

        expect(response).to have_http_status(200)
        form = doc.at_css('form[enctype="multipart/form-data"]')
        expect(form['action']).to eq(custom_field_configuration_update_dependencies_path(project, child))
        expect(form.at_css('input[name="_method"]')['value']).to eq('patch')
        expect(form.css('fieldset[data-dcf-editor]').size).to eq(1)
        expect([root['data-dcf-editor-mode'], root['data-dcf-editor-always-submit']]).to eq(%w[project 1])
        expect(root['data-dcf-editor-parent-name']).to eq(parent.name)
        expect(root['data-dcf-editor-dirty']).to be_nil
        expect(root['data-dcf-editor-conflict-mapping']).to be_nil
        expect(attr_json('mapping')).to eq(stored_mapping(child))
        expect(hidden_values).to eq([['dcf_dependencies_json', '']])
        names = form.css('[name]').map { |n| n['name'] }.uniq
        expect(names - %w[_method authenticity_token utf8 state_hash dependencies_json confirm]).to eq([])
        expect(names.size).to be <= 6
        expect(form.css('input[type=checkbox][name=confirm][required]').map { |box| box['checked'] }).to eq([nil])
        saves = form.css('input[type=submit]')
        expect(saves.size).to eq(1)
        expect([saves.first['disabled'], saves.first['data-dcf-editor-submit'], saves.first['name']])
          .to eq(['disabled', '1', nil])
        expect(form.at_css('noscript').text).to include(I18n.t(:text_dcf_editor_noscript))
        expect(rendered_state_hash).to eq(state_hash(child))
        expect(doc.at_css('p.info').text).to include(parent.name)
        expect(data_names(root).grep(/\Adata-dcf-editor-(base|values-url|parent-source|values-source|multiple-source|
                                      allow-add-values|echo|pending|submit-gate)\z/x)).to eq([])
        expect(doc.css('[name^="value_dependencies"], [name^="default_value_dependencies"]')).to be_empty
        expect(response.body).not_to include('dependencies-matrix')
        expect(doc.xpath('//@*').map(&:name).grep(/\Adata-dcf-parent/)).to eq([])
        expect(response.body).not_to include('data-dcf-blank', 'data-dcf-required-none', 'Tick the allowed child')
        expect(response.body).not_to match(/translation[ _]missing/i)
      end

      it 'escapes markup values once in the mapping attribute (T-DEPJ-10)' do
        markup = '"><script>alert(1)</script>'
        field = dcf_list_field(format: 'depending_list', name: "Mark-#{SecureRandom.hex(3)}", values: [markup, '&amp;'],
                               parent: parent)
        field = dcf_set_dependencies(field, value_dependencies: { 'Belgium' => [markup, '&amp;'] })

        get page_path(field)

        expect(response.body).not_to include('<script>alert(1)</script>')
        expect(attr_json('mapping')['value_dependencies']).to eq('Belgium' => [markup, '&amp;'])
        expect(attr_json('child-values').map { |v| v['key'] }).to eq([markup, '&amp;'])
      end

      it 'shows the global or shared warning through dcf_flash_box and none for a project-only field (T-DEPJ-11)' do
        other = dcf_create_project(name: "Other-#{SecureRandom.hex(3)}")
        global = child
        shared = dcf_list_field(format: 'depending_list', name: "Shared-#{SecureRandom.hex(3)}", values: %w[c1],
                                parent: parent, is_for_all: false, projects: [project, other])
        own = dcf_list_field(format: 'depending_list', name: "Own-#{SecureRandom.hex(3)}", values: %w[c1],
                             parent: parent, is_for_all: false, projects: [project])
        { global => :text_global_field_warning, shared => :text_shared_field_warning, own => nil }.each do |field, key|
          get page_path(field)
          banners = doc.css('div.flash.warning:not([id])')
          if key
            expect(banners.size).to eq(1)
            expect(banners.first.text.strip).to eq(I18n.t(key))
            expect(banners.first.css('svg').size).to eq(Redmine::VERSION::MAJOR >= 6 ? 1 : 0)
          else
            expect(banners).to be_empty
          end
          expect(response.body).not_to include(other.name)
        end
      end

      it 'renders text_dcf_parent_missing and no editor for a dangling, other-type, other-family or own parent ' \
         '(T-DEPJ-12, T-DEPJ-25, gap 2)' do
        other_type = dcf_list_field(name: "PCF-#{SecureRandom.hex(3)}", values: %w[A], type: ProjectCustomField)
        other_family = dcf_enum_field(name: "Fam-#{SecureRandom.hex(3)}", names: %w[A])
        allow(payload).to receive(:parse).and_call_original
        [99_999_999, other_type, other_family, :own].each do |pointer|
          field = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[c1],
                                 parent: parent)
          field = dcf_store_parent(field, pointer == :own ? field : pointer)

          get page_path(field)

          expect(response).to have_http_status(200), pointer.to_s
          expect(doc.at_css('p.nodata').text.strip).to eq(I18n.t(:text_dcf_parent_missing))
          expect(doc.css('fieldset[data-dcf-editor], input[name="dependencies_json"], [data-dcf-editor-submit]'))
            .to be_empty

          save(field, '{')
          expect(response).to have_http_status(422)
          expect(flash_error).to eq(I18n.t(:error_invalid_dependency))
          expect(rows(field).pluck(:status)).to eq(%w[validation_failed])
        end
        expect(payload).not_to have_received(:parse)
      end

      it 'keeps the 422 error_format_unsupported page for a blank parent pointer (require_dependency_capable)' do
        field = dcf_store_parent(child, nil)
        get page_path(field)
        expect(response).to have_http_status(422)
        expect(response.body).not_to include(I18n.t(:text_dcf_parent_missing))
      end

      it 'renders text_dcf_parent_not_available with the parent name escaped once; a PATCH gives 404 (T-DEPJ-12)' do
        other = dcf_create_project(name: 'Other')
        away = dcf_list_field(name: "Away <b>#{SecureRandom.hex(3)}</b>", values: %w[A], is_for_all: false,
                              projects: [other])
        field = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[c1],
                               parent: away)
        allow(payload).to receive(:parse).and_call_original

        get page_path(field)

        expect(response).to have_http_status(200)
        notice = doc.at_css('p.warning')
        expect(notice.text.strip).to eq(I18n.t(:text_dcf_parent_not_available, name: away.name))
        expect(notice.css('b')).to be_empty
        expect(notice.inner_html).to include(ERB::Util.html_escape(away.name))
        expect(response.body).not_to include('&amp;lt;')
        expect(doc.css('fieldset[data-dcf-editor], [data-dcf-editor-submit]')).to be_empty

        save(field, '{')
        expect(response).to have_http_status(404)
        expect(payload).not_to have_received(:parse)
        expect(rows(field).pluck(:status, :error_message)).to eq([%w[validation_failed error_field_not_found]])
      end

      %w[de fr nl].each do |lang|
        it "renders the editor, the scope banner and the parent notices in #{lang} without missing translations" do
          manager.update_column(:language, lang)
          missing = dcf_store_parent(dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}",
                                                    values: %w[c1], parent: parent), 99_999_999)
          other = dcf_create_project(name: 'Other')
          away = dcf_list_field(name: "Away-#{SecureRandom.hex(3)}", values: %w[A], is_for_all: false,
                                projects: [other])
          unavailable = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[c1],
                                       parent: away)

          # The request switches the locale; with_locale puts it back.
          I18n.with_locale(I18n.locale) do
            get page_path(child)
            expect(response.body).not_to match(/translation[ _]missing/i)
            expect(doc.at_css('noscript').text).to include(I18n.t(:text_dcf_editor_noscript, locale: lang))
            expect(doc.at_css('div.flash.warning').text.strip).to eq(I18n.t(:text_global_field_warning, locale: lang))
            get page_path(missing)
            expect(doc.at_css('p.nodata').text.strip).to eq(I18n.t(:text_dcf_parent_missing, locale: lang))
            get page_path(unavailable)
            expect(doc.at_css('p.warning').text.strip)
              .to eq(I18n.t(:text_dcf_parent_not_available, locale: lang, name: away.name))
            expect(response.body).not_to match(/translation[ _]missing/i)
          end
        end
      end

      it 'ignores a dependencies_json query parameter and parses nothing' do
        allow(payload).to receive(:parse).and_call_original
        get page_path(child), params: { dependencies_json: 'MARKER{' }
        expect(response).to have_http_status(200)
        expect(payload).not_to have_received(:parse)
        expect(response.body).not_to include('MARKER')
      end
    end

    describe 'PATCH with dependencies_json' do
      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'saves, redirects with the notice and writes one success row with the v2 delta (T-DEPJ-1)' do
        child
        allow(payload).to receive(:parse).and_call_original

        expect { save(child, json({ 'Germany' => %w[Lyon] }, { 'Germany' => 'Lyon' }), extra: { confirm: '1' }) }
          .to change { rows(child).count }.by(1)

        expect(response).to redirect_to(page_path(child))
        expect(flash[:notice]).to eq(I18n.t(:notice_dependencies_saved))
        expect(payload).to have_received(:parse).once
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, { 'Germany' => 'Lyon' }])
        row = rows(child).last
        before = JSON.parse(row.before_value)
        after = JSON.parse(row.after_value)
        expect([row.action, row.status, after['v'], after['source']]).to eq(['update_dependencies', 'success', 2, 'editor'])
        expect(after['mapping_sha256']).to match(/\A[0-9a-f]{64}\z/)
        expect(after['mapping_sha256']).to eq(payload.stored_digest(CustomField.find(child.id)))
        expect(before).to eq('v' => 2, 'links' => 3, 'defaults' => 1, 'mapping_sha256' => payload.digest(*original))
        expect(after.slice('links', 'added', 'removed', 'orphans_removed', 'defaults_changed', 'parents_changed'))
          .to eq('links' => 1, 'added' => 1, 'removed' => 3, 'orphans_removed' => 0, 'defaults_changed' => 2,
                 'parents_changed' => 3)
        expect(row.changes_summary).to start_with('Updated dependency mapping (editor): +1/-3 links')
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'saves for an administrator on an active project with one success row (G5 admin row)' do
        child
        admin = dcf_admin
        as(admin)

        expect { save(child, json({ 'Germany' => %w[Lyon] }), extra: { confirm: '1' }) }.to change { rows(child).count }.by(1)

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        row = rows(child).last
        expect([row.action, row.status, row.acting_user_id]).to eq(['update_dependencies', 'success', admin.id])
        expect(JSON.parse(row.after_value)['source']).to eq('editor')
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'chains mapping_sha256 over consecutive saves and audits a no-op save' do
        child
        save(child, json({ 'Germany' => %w[Lyon] }), extra: { confirm: '1' })
        save(child, json({ 'Germany' => %w[Lyon] }), extra: { confirm: '1' })

        first, second = rows(child).last(2).map { |row| [JSON.parse(row.before_value), JSON.parse(row.after_value)] }
        expect(second[0]['mapping_sha256']).to eq(first[1]['mapping_sha256'])
        expect(second[1].values_at('added', 'removed')).to eq([0, 0])
        expect(rows(child).last.status).to eq('success')
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'round-trips parent and child values with brackets (T-DEPJ-2)' do
        brackets = dcf_list_field(name: "Br-#{SecureRandom.hex(3)}", values: ['Foo [x]', '[b', 'a]'])
        field = dcf_list_field(format: 'depending_list', name: "Brc-#{SecureRandom.hex(3)}", values: ['[x]', 'y]'],
                               parent: brackets)
        mapping = { 'Foo [x]' => ['[x]'], '[b' => ['y]'], 'a]' => ['[x]', 'y]'] }

        save(field, json(mapping, { 'a]' => 'y]' }), extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(field))
        expect(stored(field)).to eq([mapping, { 'a]' => 'y]' }])
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'clears both stores with {} (T-DEPJ-3)' do
        save(child, '{}', extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{}, {}])
        after = JSON.parse(rows(child).last.after_value)
        expect(after.values_at('links', 'defaults', 'removed', 'defaults_changed')).to eq([0, 0, 3, 1])
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'saves 4,200 links in one parameter (T-DEPJ-4, UN-28)' do
        big_parent = dcf_list_field(name: "BigP-#{SecureRandom.hex(3)}", values: (1..42).map { |i| "P#{i}" })
        big = dcf_list_field(format: 'depending_list', name: "BigC-#{SecureRandom.hex(3)}",
                             values: (1..100).map { |i| "C#{i}" }, parent: big_parent)
        mapping = big_parent.possible_values.to_h { |key| [key, big.possible_values] }

        save(big, json(mapping), extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(big))
        expect(request.request_parameters.keys.size).to be <= 5
        expect(stored(big)[0]).to eq(mapping)
        after = JSON.parse(rows(big).last.after_value)
        expect(after.values_at('links', 'added', 'truncated')).to eq([4_200, 4_200, true])
        expect(after['sample']['added'].size).to eq(20)
        expect(rows(big).last.after_value.bytesize).to be <= 12_100
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'records an import payload with source import, mode and rows (T-DEPJ-13)' do
        meta = { 'mode' => 'replace', 'rows' => 2 }
        save(child, json({ 'Germany' => %w[Lyon], 'France' => %w[Lyon] }, {}, 'source' => 'import', 'import' => meta), extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(child))
        row = rows(child).last
        expect(JSON.parse(row.after_value).values_at('source', 'import')).to eq(['import', meta])
        expect(row.changes_summary).to start_with('Updated dependency mapping (import, replace, 2 rows): ')
        expect(CustomField.find(child.id).format_store.keys & %w[source import base version]).to eq([])
      end

      it 'refuses source editor together with import as invalid_import (T-DEPJ-23)' do
        save(child, json({ 'Germany' => %w[Lyon] }, {}, 'import' => { 'mode' => 'merge', 'rows' => 1 }))

        expect(response).to have_http_status(422)
        expect(flash_error).to eq(I18n.t(:error_invalid_dependency_payload))
        expect(rows(child).last.changes_summary).to match(/\Adependencies_json rejected: invalid_import \(\d+ bytes\)\z/)
        expect(stored(child)).to eq(original)
      end

      {
        'malformed' => ['{', 'invalid_json'],
        'blank' => ['', 'blank'],
        'unknown top-level key' => ['{"meta":{}}', 'unknown_key'],
        'long number' => ['{"value_dependencies":{"Belgium":[12345678901234567890]}}', 'number_too_long'],
        # G5 on the project path: floats, null and nesting deeper than 3
        'float' => ['{"value_dependencies":{"Belgium":[1.5]}}', 'invalid_links'],
        'null' => ['{"value_dependencies":{"Belgium":[null]}}', 'invalid_links'],
        'nesting deeper than 3' => ['{"value_dependencies":{"Belgium":[["x"]]}}', 'invalid_json']
      }.each do |label, (raw, code)|
        it "refuses a #{label} payload with an audited 422 and re-renders the stored mapping clean (T-DEPJ-5)" do
          raw_before = raw_store(child)
          allow(payload).to receive(:parse).and_call_original

          save(child, raw)

          expect(response).to have_http_status(422)
          expect(payload).to have_received(:parse).once
          expect(flash_error).to eq(I18n.t(:error_invalid_dependency_payload))
          expect(raw_store(child)).to eq(raw_before)
          row = rows(child).last
          expect([row.status, row.error_message]).to eq(%w[validation_failed error_invalid_dependency_payload])
          expect(row.changes_summary).to eq("dependencies_json rejected: #{code} (#{raw.bytesize} bytes)")
          expect(attr_json('mapping')).to eq(stored_mapping(child))
          expect(root['data-dcf-editor-dirty']).to be_nil
          expect(hidden_values).to eq([['dcf_dependencies_json', '']])
          expect(rendered_state_hash).to eq(state_hash(child))
        end
      end

      it 'refuses a nested dependencies_json param as not_a_string with 0 bytes' do
        save(child, { 'a' => '1' })

        expect(response).to have_http_status(422)
        expect(rows(child).last.changes_summary).to eq('dependencies_json rejected: not_a_string (0 bytes)')
        expect(stored(child)).to eq(original)
      end

      it 'refuses a payload above 4 MiB with the size message in the request locale, without JSON.parse (T-DEPJ-21)' do
        child
        body = json('Belgium' => %w[Antwerp])
        above = body + (' ' * (max_bytes + 1 - body.bytesize))
        allow(JSON).to receive(:parse).and_call_original

        save(child, above)

        expect(response).to have_http_status(422)
        expect(flash_error).to eq(I18n.t(:error_dcf_dependencies_too_large_to_send, size: limits.delimited(max_bytes + 1),
                                                                                    limit: limits.delimited(max_bytes)))
        expect(flash_error).not_to eq(I18n.t(:error_invalid_dependency_payload))
        expect(rows(child).last.changes_summary).to eq("dependencies_json rejected: too_large (#{max_bytes + 1} bytes)")
        expect(root['data-dcf-editor-dirty']).to be_nil

        manager.update_column(:language, 'de')
        I18n.with_locale(I18n.locale) { save(child, above) }
        size, limit = I18n.with_locale(:de) { [limits.delimited(max_bytes + 1), limits.delimited(max_bytes)] }
        expect(size).to eq('4.194.305')
        expect(flash_error)
          .to eq(I18n.t(:error_dcf_dependencies_too_large_to_send, locale: :de, size: size, limit: limit))
        # Rails 6.1 parses its own JSON (the session cookie) on a later request.
        expect(JSON).not_to have_received(:parse).with(a_string_including('Belgium'), any_args)
        expect(stored(child)).to eq(original)
      end

      # T-DEPJ-20: the refusals and their request times. The 1 s bound times a
      # request, a DB-backed path, so it is an opt-in :perf example (G6).
      def refuse_long_integers
        child
        # untimed warm-up: the first render of the process loads the locales,
        # the layout and the editor partial
        save(child, '{"value_dependencies":{"Belgium":[12345678901234567890]}}')
        expect(response).to have_http_status(422)
        allow(JSON).to receive(:parse).and_call_original
        times = ['9' * 1_000_000, '-12345678901234567890', '12345678901234567890'].map do |number|
          raw = %({"value_dependencies":{"Belgium":[#{number}]}})
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          save(child, raw)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

          expect(response).to have_http_status(422)
          expect(rows(child).last.changes_summary)
            .to eq("dependencies_json rejected: number_too_long (#{raw.bytesize} bytes)")
          puts format('DCF PERF project PATCH with a %d-digit integer: %.0f ms', number.delete('-').size, elapsed * 1000)
          elapsed
        end
        expect(JSON).not_to have_received(:parse).with(a_string_including('Belgium'), any_args)
        expect(stored(child)).to eq(original)
        times
      end

      it 'refuses 1,000,000-digit and 20-digit integers before JSON.parse (T-DEPJ-20, SP-01)' do
        expect(refuse_long_integers.size).to eq(3)
      end

      it 'refuses 1,000,000-digit and 20-digit integers each in under 1 s (T-DEPJ-20, SP-01)', :perf do
        expect(refuse_long_integers).to all(be < 1.0)
      end

      it 'refuses a short negative integer after JSON.parse as invalid_links (WP-22 open input)' do
        raw = '{"value_dependencies":{"Belgium":[-1]}}'
        allow(JSON).to receive(:parse).and_call_original
        save(child, raw)

        expect(response).to have_http_status(422)
        # the spy form of T-DEPJ-20 and T-DEPJ-21 sees this parse
        expect(JSON).to have_received(:parse).with(a_string_including('Belgium'), any_args).once
        expect(rows(child).last.changes_summary).to eq("dependencies_json rejected: invalid_links (#{raw.bytesize} bytes)")
      end

      it 'refuses an unknown parent key with offenders only in the audit summary and re-renders the posted mapping ' \
         'dirty (T-DEPJ-6, gap 1)' do
        key = '<img src=x onerror=alert(1)>MARK'
        posted = { 'Belgium' => %w[Antwerp], key => %w[Paris] }
        allow(payload).to receive(:parse).and_call_original

        save(child, json(posted, { 'Belgium' => 'Antwerp' }))

        expect(response).to have_http_status(422)
        expect(payload).to have_received(:parse).once
        expect(flash_error).to eq(I18n.t(:error_invalid_dependency))
        expect(doc.at_css('#flash_error').inner_html).not_to include('MARK')
        expect(rows(child).last.changes_summary).to eq("unknown parent keys: 1 [#{key}]")
        expect(attr_json('mapping'))
          .to eq('value_dependencies' => posted, 'default_value_dependencies' => { 'Belgium' => 'Antwerp' })
        expect(root['data-dcf-editor-dirty']).to eq('1')
        expect(hidden_values).to eq([['dcf_dependencies_json', '']])
        # Anchored: MySQL adds data-dcf-editor-storage-base, which is not the
        # admin-only data-dcf-editor-base.
        expect(data_names(root).grep(/\Adata-dcf-editor-(?:echo|pending|conflict|base)/)).to eq([])
        expect(response.body).not_to include('<img src=x')
        expect(stored(child)).to eq(original)
        expect(rendered_state_hash).to eq(state_hash(child))

        get custom_field_configuration_audit_path(project)
        expect(response.body).to include('&lt;img src=x onerror=alert(1)&gt;MARK')
        expect(response.body).not_to include('<img src=x')
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'prefers dependencies_json over nested params of the same request, without a deprecation line (T-DEPJ-7)' do
        child
        allow(Rails.logger).to receive(:warn).and_call_original

        save(child, json({ 'Germany' => %w[Lyon] }), extra: { confirm: '1', value_dependencies: { 'Belgium' => %w[Paris] } })

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        expect(Rails.logger).not_to have_received(:warn).with(/deprecated/)
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'reloads the field after a storage 422; the corrected resubmit with the rendered state hash saves ' \
         '(T-DEPJ-14, R9, PC-58)' do
        child
        stub_limit_at_stored(child)
        allow(payload).to receive(:parse).and_call_original
        grown = { 'Belgium' => %w[Antwerp Brussels Paris Lyon], 'France' => %w[Paris Lyon], 'Germany' => %w[Lyon] }

        save(child, json(grown), extra: { confirm: '1' })

        expect(response).to have_http_status(422)
        expect(payload).to have_received(:parse).once
        expect(flash_error).to include(child.name)
        expect(rows(child).last.error_message).to eq('error_dcf_mapping_too_large')
        expect(attr_json('mapping')['value_dependencies']).to eq(grown)
        expect(root['data-dcf-editor-dirty']).to eq('1')
        expect(hidden_values).to eq([['dcf_dependencies_json', '']])
        expect(stored(child)).to eq(original)
        fresh = rendered_state_hash
        expect(fresh).to eq(state_hash(child))

        save(child, json({ 'Germany' => %w[Lyon] }), state: fresh, extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        expect(rows(child).last.status).to eq('success')
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'escapes the field name once in the storage 422 flash on the JSON path (T-DEPJ-22, SP-06)' do
        markup = '<img src=x onerror=alert(1)>'
        field = dcf_list_field(format: 'depending_list', name: markup, values: %w[c1 c2], parent: parent)
        stub_limit_at_stored(field)

        save(field, json({ 'Belgium' => %w[c1 c2], 'France' => %w[c1 c2] }), extra: { confirm: '1' })

        expect(response).to have_http_status(422)
        box = doc.at_css('#flash_error')
        expect(box.css('img')).to be_empty
        expect(box.inner_html).to include(ERB::Util.html_escape(markup))
        expect(box.text).to include(markup)
        expect(response.body).not_to include(markup)
        expect(response.body).not_to include('&amp;lt;')
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'answers a stale save with 409, the stored mapping and the posted version as conflict mapping; the fresh ' \
         'state hash saves it (T-DEPJ-8, T-DEPJ-16, UD-17)' do
        raw_before = raw_store(child)
        allow(payload).to receive(:parse).and_call_original
        meta = { 'mode' => 'merge', 'rows' => 1 }
        mine = json({ 'Germany' => %w[Lyon] }, { 'Germany' => 'Lyon' }, 'source' => 'import', 'import' => meta)

        save(child, mine, state: 'stale', extra: { confirm: '1' })

        expect(response).to have_http_status(409)
        expect(payload).to have_received(:parse).once
        expect(flash_error).to eq(I18n.t(:error_stale_edit))
        expect(raw_store(child)).to eq(raw_before)
        expect(attr_json('mapping')).to eq(stored_mapping(child))
        expect(root['data-dcf-editor-dirty']).to be_nil
        expect(attr_json('conflict-mapping'))
          .to eq('value_dependencies' => { 'Germany' => %w[Lyon] }, 'default_value_dependencies' => { 'Germany' => 'Lyon' },
                 'source' => 'import', 'import' => meta)
        expect(hidden_values).to eq([['dcf_dependencies_json', '']])
        expect(data_names(root).grep(/pending|echo/)).to eq([])
        expect(rows(child).pluck(:status, :error_message).last).to eq(%w[validation_failed error_stale_edit])
        fresh = rendered_state_hash
        expect(fresh).to eq(state_hash(child))

        save(child, mine, state: fresh, extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, { 'Germany' => 'Lyon' }])
      end

      it 'offers no conflict mapping when the stale payload does not parse; a non-String one is not parsed' do
        allow(payload).to receive(:parse).and_call_original
        save(child, '{', state: 'stale')
        expect(response).to have_http_status(409)
        expect(payload).to have_received(:parse).once
        expect(root['data-dcf-editor-conflict-mapping']).to be_nil
        expect(attr_json('mapping')).to eq(stored_mapping(child))

        save(child, { 'a' => '1' }, state: 'stale')
        expect(response).to have_http_status(409)
        expect(payload).to have_received(:parse).once
        expect(root['data-dcf-editor-conflict-mapping']).to be_nil

        save(child, json({ 'Germany' => %w[Lyon] }), state: 'stale')
        expect(attr_json('conflict-mapping')).to include('source' => 'editor', 'import' => nil)
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'removes stored orphans on save and counts them; an identical save is still audited (edge case 9)' do
        field = store_raw(child, { 'Gone' => %w[Antwerp], 'Belgium' => %w[zz Antwerp] })

        save(field, json({ 'Belgium' => %w[Antwerp] }), extra: { confirm: '1' })
        save(field, json({ 'Belgium' => %w[Antwerp] }), extra: { confirm: '1' })

        first, second = rows(field).last(2)
        expect(JSON.parse(first.after_value)['orphans_removed']).to eq(2)
        expect(first.changes_summary).to include('2 orphaned removed')
        expect(JSON.parse(second.after_value).values_at('added', 'removed')).to eq([0, 0])
        expect([first.status, second.status]).to eq(%w[success success])
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'never names a hidden child of the edited field on the page, a 422 or a 409' do
        grandchild = dcf_list_field(format: 'depending_list', name: 'Secret grandchild', values: %w[SECRET-G1],
                                    parent: child)
        dcf_set_dependencies(grandchild, value_dependencies: { 'Antwerp' => %w[SECRET-G1] })
        grandchild.update!(visible: false, role_ids: [dcf_create_role.id])
        before = raw_store(grandchild)

        get page_path(child)
        bodies = [response.body]
        save(child, json({ 'ZZ' => %w[Antwerp] }), extra: { confirm: '1' })
        bodies << response.body
        save(child, json({ 'Germany' => %w[Lyon] }), state: 'stale', extra: { confirm: '1' })
        bodies << response.body
        save(child, json({ 'Germany' => %w[Lyon] }), extra: { confirm: '1' })

        bodies.each do |body|
          expect(body).not_to include('Secret grandchild')
          expect(body).not_to include('SECRET-G1')
        end
        expect(raw_store(grandchild)).to eq(before)
        expect(rows(child).last.changes_summary).not_to include('Secret')
        expect(rows(child).last.affected_child_field_ids.to_s).not_to include(grandchild.id.to_s)
      end

      # Changed by WP-34 (UD-23): confirm '1' on every save of this global field; was no confirm.
      it 'shows a foreign enumeration id raw in offenders and samples, never its hidden label (gap 3)' do
        hidden = dcf_enum_field(name: "SecretEnum-#{SecureRandom.hex(3)}", names: ['SECRET-LABEL'])
        hidden.update!(visible: false, role_ids: [dcf_create_role.id])
        secret = hidden.enumerations.first.id.to_s
        enum_parent = dcf_enum_field(name: "EP-#{SecureRandom.hex(3)}", names: %w[North])
        enum_child = dcf_enum_field(format: 'depending_enumeration', name: "EC-#{SecureRandom.hex(3)}",
                                    names: %w[Alpha], parent: enum_parent)
        north = enum_parent.enumerations.first.id.to_s
        alpha = enum_child.enumerations.first.id.to_s

        save(enum_child, json(north => [secret]), extra: { confirm: '1' })

        expect(response).to have_http_status(422)
        expect(rows(enum_child).last.changes_summary).to eq("unknown child values: 1 [#{secret}]")
        expect(response.body).not_to include('SECRET-LABEL')
        expect(response.body).not_to include(hidden.name)

        store_raw(enum_child, { north => [alpha, secret] })
        save(enum_child, json(north => [alpha]), extra: { confirm: '1' })

        expect(response).to redirect_to(page_path(enum_child))
        row = rows(enum_child).last
        after = JSON.parse(row.after_value)
        expect(after['sample']['removed']).to eq([['North', secret]])
        expect(after['orphans_removed']).to eq(1)
        expect(row.after_value).not_to include('SECRET-LABEL')
      end

      # Flipped by WP-34 (UD-23 changed by the owner on 2026-11-02): a replace
      # import on a global field needs the confirmation checkbox; without
      # confirm it is refused (422, nothing written, no row), with confirm
      # '1' it saves as before. Was 'saves a replace import on a global field
      # without any confirmation step (UD-23)', with no confirm input on the
      # page.
      it 'saves a replace import on a global field only with the confirmation (UD-23, WP-34)' do
        expect(child.is_for_all).to be(true)
        raw = json({ 'Germany' => %w[Lyon] }, {}, 'source' => 'import', 'import' => { 'mode' => 'replace', 'rows' => 1 })
        expect { save(child, raw) }.not_to change(events, :count)
        expect(response).to have_http_status(422)
        expect(stored(child)).to eq(original)

        save(child, raw, extra: { confirm: '1' })
        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        row = rows(child).last
        expect(JSON.parse(row.after_value).values_at('source', 'import'))
          .to eq(['import', { 'mode' => 'replace', 'rows' => 1 }])
        expect(row.affected_projects_count).to eq(Project.active.count)
        follow_redirect!
        expect(doc.css('input[type=checkbox][name=confirm][required]').size).to eq(1)
        expect(doc.at_css('input[name=confirm]')['checked']).to be_nil
        expect(response.body).to include(I18n.t(:text_dcf_confirm_understand))
      end
    end

    describe 'PATCH with the deprecated nested params' do
      # Changed by WP-34 (UD-23): confirm '1' (global child), still no mapping
      # params; was no params at all.
      it 'clears without mapping params, audits source form and logs one constant deprecation line (T-DEPJ-9)' do
        child
        allow(Rails.logger).to receive(:warn).and_call_original
        allow(payload).to receive(:parse).and_call_original

        patch custom_field_configuration_update_dependencies_path(project, child), params: { confirm: '1' }

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{}, {}])
        expect(JSON.parse(rows(child).last.after_value)['source']).to eq('form')
        expect(Rails.logger).to have_received(:warn).with(/\A\[DCF\] .*deprecated in 0\.1\.0/).once
        expect(payload).not_to have_received(:parse)
      end

      it 'answers a validation 422 with the reloaded stored mapping, not dirty' do
        patch custom_field_configuration_update_dependencies_path(project, child),
              params: { value_dependencies: { 'ZZ' => %w[Lyon] } }

        expect(response).to have_http_status(422)
        expect(attr_json('mapping')).to eq(stored_mapping(child))
        expect(root['data-dcf-editor-dirty']).to be_nil
      end
    end

    describe 'refusals before any parse (SP-20b, gap 12)' do
      before do
        allow(payload).to receive(:parse).and_call_original
        allow(payload).to receive(:parse!).and_call_original
      end

      let(:oversize) { 'x' * (max_bytes + 1) }
      let(:payloads) { ['{', %({"value_dependencies":{"Belgium":[#{'9' * 1_000_000}]}}), oversize, { 'a' => '1' }] }

      def expect_no_parse
        expect(payload).not_to have_received(:parse)
        expect(payload).not_to have_received(:parse!)
      end

      it 'refuses a PATCH that reaches the service without the permission: 403 and one authorization_failed row ' \
         'each (T-DEPJ-24)' do
        child
        as(dcf_plain_member(project))
        allow_any_instance_of(User).to receive(:allowed_to?).and_wrap_original do |original, action, *args, **opts, &block|
          if action.is_a?(Hash)
            true
          elsif action == :manage_project_custom_field_configuration
            false
          else
            original.call(action, *args, **opts, &block)
          end
        end
        raw_before = raw_store(child)

        payloads.each do |raw|
          [nil, 'stale'].each do |state|
            expect { save(child, raw, state: state) }
              .to change { rows(child).where(status: 'authorization_failed').count }.by(1)
            expect(response).to have_http_status(403)
          end
        end

        expect_no_parse
        expect(raw_store(child)).to eq(raw_before)
        row = rows(child).last
        expect([row.action, row.status, row.error_message, row.changes_summary, row.before_value, row.after_value])
          .to eq(['authorization_failed', 'authorization_failed', 'error_forbidden', nil, nil, nil])
        expect([row.project_id, row.custom_field_id]).to eq([project.id, child.id])
      end

      it 'refuses non-members, members without the permission and anonymous users with no row' do
        child
        count = events.count
        [dcf_create_user("stranger-#{SecureRandom.hex(3)}"), dcf_plain_member(project)].each do |user|
          as(user)
          save(child, '{', state: 'x')
          expect(response).to have_http_status(403)
        end
        as(User.anonymous)
        save(child, '{', state: 'x')
        expect(response.status).to be_in([302, 401, 403])
        expect(events.count).to eq(count)
        expect_no_parse
      end

      it 'answers 403 on a closed project for the manager and an administrator, with no parse and no row ' \
         '(T-DEPJ-17)' do
        closed = dcf_create_project(name: 'Closed', status: :closed)
        child
        raw_before = raw_store(child)
        count = events.count
        [dcf_manager(closed), dcf_admin].each do |user|
          as(user)
          get page_path(child, closed)
          expect(response).to have_http_status(200)
          payloads.first(2).each do |raw|
            save(child, raw, in_project: closed)
            expect(response).to have_http_status(403)
          end
        end
        expect_no_parse
        expect(events.count).to eq(count)
        expect(raw_store(child)).to eq(raw_before)
      end

      it 'answers 403 on an archived project for the manager and an administrator, with no parse' do
        archived = dcf_create_project(name: 'Archived', status: :archived)
        child
        [dcf_manager(archived), dcf_admin].each do |user|
          as(user)
          get page_path(child, archived)
          expect(response).to have_http_status(403)
          save(child, '{', in_project: archived)
          expect(response).to have_http_status(403)
        end
        expect_no_parse
      end

      it 'answers 404 for a field outside the project and 403 to a non-member for any field id' do
        other = dcf_create_project(name: 'Other')
        foreign = dcf_list_field(format: 'depending_list', name: "Foreign-#{SecureRandom.hex(3)}", values: %w[SECRET-V],
                                 parent: parent, is_for_all: false, projects: [other])
        save(foreign, '{', state: 'x')
        expect(response).to have_http_status(404)
        expect(response.body).not_to include(foreign.name)
        expect(response.body).not_to include('SECRET-V')

        as(dcf_create_user("stranger-#{SecureRandom.hex(3)}"))
        save(foreign, '{', state: 'x')
        expect(response).to have_http_status(403)
        patch custom_field_configuration_update_dependencies_path(project, 99_999_999),
              params: { dependencies_json: '{' }, headers: multipart
        expect(response).to have_http_status(403)
        expect(rows(foreign).count).to eq(0)
        expect_no_parse
      end

      it 'answers 422 without an authenticity token when forgery protection is on, with no parse' do
        child
        protection = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        begin
          save(child, '{')
        ensure
          ActionController::Base.allow_forgery_protection = protection
        end
        expect(response).to have_http_status(422)
        expect_no_parse
        expect(stored(child)).to eq(original)
      end
    end

    # G6 (quality R16): the invariance form, after a warm-up request.
    describe 'query counts' do
      def full(field, parent_field)
        json(parent_field.possible_values.to_h { |key| [key, field.possible_values] })
      end

      # Changed by WP-34 (UD-23): confirm '1' on the saves of both global fields (the same for both counts); was no confirm.
      it 'are the same for a save of 10 and of 4,200 links' do
        small_parent = dcf_list_field(name: "SP-#{SecureRandom.hex(3)}", values: %w[P1 P2])
        small = dcf_list_field(format: 'depending_list', name: "SC-#{SecureRandom.hex(3)}",
                               values: (1..5).map { |i| "C#{i}" }, parent: small_parent)
        big_parent = dcf_list_field(name: "BP-#{SecureRandom.hex(3)}", values: (1..42).map { |i| "P#{i}" })
        big = dcf_list_field(format: 'depending_list', name: "BC-#{SecureRandom.hex(3)}",
                             values: (1..100).map { |i| "C#{i}" }, parent: big_parent)
        save(small, '{}', extra: { confirm: '1' })
        small_raw = full(small, small_parent)
        big_raw = full(big, big_parent)
        small_state = state_hash(small)
        big_state = state_hash(big)

        small_queries = dcf_count_queries { save(small, small_raw, state: small_state, extra: { confirm: '1' }) }
        big_queries = dcf_count_queries { save(big, big_raw, state: big_state, extra: { confirm: '1' }) }

        expect(response).to redirect_to(page_path(big))
        expect(big_queries).to eq(small_queries)
      end

      it 'are the same for the page of 10 and of 1,000 parent values' do
        small_parent = dcf_enum_field(name: "SE-#{SecureRandom.hex(3)}", names: (1..10).map { |i| "N#{i}" })
        big_parent = dcf_enum_field(name: "BE-#{SecureRandom.hex(3)}", names: [])
        CustomFieldEnumeration.insert_all(
          (1..1_000).map { |i| { custom_field_id: big_parent.id, name: "N#{i}", position: i, active: true } }
        )
        small = dcf_enum_field(format: 'depending_enumeration', name: "SL-#{SecureRandom.hex(3)}", names: %w[c1],
                               parent: small_parent)
        big = dcf_enum_field(format: 'depending_enumeration', name: "BL-#{SecureRandom.hex(3)}", names: %w[c1],
                             parent: CustomField.find(big_parent.id))
        get page_path(small)
        expect(root['data-dcf-editor-mode']).to eq('project')

        small_queries = dcf_count_queries { get page_path(small) }
        big_queries = dcf_count_queries { get page_path(big) }

        expect(response).to have_http_status(200)
        expect(attr_json('parent-values').size).to eq(1_000)
        expect(big_queries).to eq(small_queries)
      end
    end
  end

  # --- WP-28: values page search and pagination ---------------------------
  # Project design 5, 10 and 15 (T-PAG-1..13, T-ASSET-1..2), UD-21, SD-16,
  # P-D12. Drag-and-drop markup is checked here (no JS driver).
  describe 'values page search and pagination (WP-28)' do
    let(:manager) { dcf_manager(project) }
    let(:asset) { ->(name, ext) { /#{name}(-[0-9a-f]{7,}\.#{ext}|\.#{ext}\?\d+)\z/ } }
    let(:service) { RedmineDependingCustomFields::BaseService }

    before { as(manager) }

    def doc
      Nokogiri::HTML(response.body)
    end

    def show_path(field, params = {})
      custom_field_configuration_field_path(project, field, params)
    end

    def labels(count, prefix = 'Value')
      (1..count).map { |i| format('%<prefix>s %<i>04d', prefix: prefix, i: i) }
    end

    def own_list(count, prefix = 'Value', extra: [])
      dcf_list_field(values: extra + labels(count, prefix), is_for_all: false, projects: [project])
    end

    def enum_with(count, is_for_all: true)
      field = dcf_enum_field(names: [], is_for_all: is_for_all)
      field.projects = [project] unless is_for_all
      CustomFieldEnumeration.insert_all(
        (1..count).map { |i| { custom_field_id: field.id, name: format('N%04d', i), position: i, active: true } }
      )
      CustomField.find(field.id)
    end

    def row_values
      doc.css('table.dcf-values tbody tr').map { |tr| tr['data-dcf-value'] }
    end

    def scripts
      doc.css('script[src]').map { |node| node['src'] }
    end

    def stylesheets
      doc.css('link[rel=stylesheet]').map { |node| node['href'] }
    end

    def hidden(name, scope = doc)
      scope.css(%(input[type="hidden"][name="#{name}"]))
    end

    def query_of(href)
      Rack::Utils.parse_nested_query(URI.parse(href).query.to_s)
    end

    describe 'drag threshold and pagination' do
      it 'keeps the drag markup at 500 values, without hidden q or page (T-PAG-1, UD-21)' do
        field = own_list(500)
        get show_path(field)
        expect(response).to have_http_status(200)
        expect(row_values.size).to eq(500)
        expect(doc.css('table.dcf-values .dcf-sort-handle').size).to eq(500)
        expect(doc.css('form.dcf-reorder-form').size).to eq(1)
        expect(scripts.grep(asset.call('dcf_value_reorder', 'js')).size).to eq(1)
        expect(doc.css('input#dcf_values_q[type="text"][name="q"]').size).to eq(1)
        expect(hidden('q')).to be_empty
        expect(hidden('page')).to be_empty
        expect(doc.css('.pagination')).to be_empty
        expect(doc.text).not_to include(I18n.t(:text_dcf_drag_reorder_large, max: 500))
      end

      it 'paginates 520 values: 25 rows, core pagination, no drag, the drag notice (T-PAG-2)' do
        field = own_list(520)
        get show_path(field)
        expect(row_values).to eq(labels(25))
        expect(doc.css('span.pagination ul.pages li.current span').text).to eq('1')
        expect(doc.css('span.pagination span.per-page')).not_to be_empty
        expect(response.body).not_to include('dcf-sort-handle')
        expect(response.body).not_to include('dcf-reorder-form')
        expect(scripts.grep(/dcf_value_reorder/)).to be_empty
        expect(doc.text).to include(I18n.t(:text_dcf_drag_reorder_large, max: 500))
        expect(doc.css('form.dcf-values-filter').size).to eq(1)
      end

      it 'shows the rows of page 2 and clamps the page (T-PAG-3)' do
        field = own_list(520)
        get show_path(field, page: 2)
        expect(row_values).to eq(labels(520)[25, 25])
        expect(hidden('page', doc.at_css('form.dcf-inline-form')).map { |n| n['value'] }).to eq(['2'])
        get show_path(field, page: 999)
        expect(row_values).to eq(labels(520)[500, 20])
        expect(doc.css('span.pagination li.current span').text).to eq('21')
        expect(hidden('page', doc.at_css('form.dcf-inline-form')).map { |n| n['value'] }).to eq(['21'])
        %w[0 -3 abc].each do |raw|
          get show_path(field, page: raw)
          expect(row_values.first).to eq('Value 0001')
          expect(hidden('page')).to be_empty
        end
        ['page[]=2&q[]=x', 'page[x]=2&q[y]=z'].each do |query|
          get "#{show_path(field)}?#{query}"
          expect(response).to have_http_status(200)
          expect(row_values).to eq(labels(25))
          expect(doc.at_css('input#dcf_values_q')['value'].to_s).to eq('')
          expect(hidden('q')).to be_empty
        end
      end

      it 'honours per_page and caps it at 500 (T-PAG-4)' do
        allow(Setting).to receive(:per_page_options_array).and_return([25, 100, 1000])
        field = own_list(1_200)
        get show_path(field, per_page: 100)
        expect(row_values.size).to eq(100)
        get show_path(field, per_page: 1000)
        expect(row_values.size).to eq(500)
        expect(doc.css('span.pagination span.items').text).to eq('(1-500/1200)')
      end

      it 'shows the search box above 25 values or with q, pagination above 500 (T-PAG-12, T-PAG-13)' do
        get show_path(own_list(25))
        expect(doc.css('form.dcf-values-filter')).to be_empty
        field = own_list(26)
        get show_path(field)
        form = doc.at_css('form.dcf-values-filter[method="get"]')
        expect(form['action']).to eq(show_path(field))
        expect(form.css('fieldset legend').text).to eq(I18n.t(:label_filter_plural))
        expect(form.at_css('label[for="dcf_values_q"]').text).to eq("#{I18n.t(:label_search)}:")
        input = form.at_css('input#dcf_values_q')
        expect([input['type'], input['name'], input['size'], input['maxlength']]).to eq(%w[text q 30 255])
        submit = form.at_css('input[type="submit"]')
        expect([submit['value'], submit['class'], submit['name']]).to eq([I18n.t(:button_apply), 'small', nil])
        expect(form.css('input[name="page"]')).to be_empty
        get show_path(own_list(3), q: 'x')
        expect(doc.css('form.dcf-values-filter').size).to eq(1)
        get show_path(own_list(500))
        expect(doc.css('span.pagination')).to be_empty
        get show_path(own_list(501))
        expect(doc.css('span.pagination').size).to eq(1)
      end

      it 'renders the Clear link like core: an svg on 6.0 and later, plain text on 5.1' do
        field = own_list(30)
        get show_path(field, q: 'value', show_usage: 1)
        link = doc.at_css('form.dcf-values-filter a.icon.icon-reload')
        expect(link['href']).to eq(show_path(field, show_usage: 1))
        expect(link.text.strip).to eq(I18n.t(:button_clear))
        expect(link.css('svg').size).to eq(Redmine::VERSION::MAJOR >= 6 ? 1 : 0)
        expect(link.css('span.icon')).to be_empty
        expect(hidden('show_usage', doc.at_css('form.dcf-values-filter')).map { |n| n['value'] }).to eq(['1'])
        get show_path(field, q: 'value')
        expect(doc.at_css('form.dcf-values-filter a.icon-reload')['href']).to eq(show_path(field))
        expect(hidden('show_usage', doc.at_css('form.dcf-values-filter'))).to be_empty
      end

      it 'keeps q and show_usage in the pagination links (core links)' do
        field = own_list(1_200)
        get show_path(field, q: 'value', show_usage: 1, page: 2)
        hrefs = doc.css('span.pagination a[href]').map { |a| a['href'] }
        expect(hrefs).not_to be_empty
        hrefs.each do |href|
          expect(URI.parse(href).path).to eq(show_path(field))
          expect(query_of(href)).to include('q' => 'value', 'show_usage' => '1')
        end
      end
    end

    describe 'search' do
      it 'searches tokens case- and accent-insensitively and disables drag (T-PAG-5)' do
        field = own_list(30, extra: ["\u0141\u00F3d\u017A", "Krak\u00F3w"])
        get show_path(field, q: 'LODZ')
        expect(row_values).to eq(["\u0141\u00F3d\u017A"])
        expect(response.body).not_to include('dcf-sort-handle')
        expect(response.body).not_to include('dcf-reorder-form')
        expect(scripts.grep(/dcf_value_reorder/)).to be_empty
        expect(doc.text).to include(I18n.t(:text_dcf_values_filtered, count: 1, total: 32))
        expect(doc.text).to include(I18n.t(:text_dcf_drag_reorder_filtered))
        expect(doc.at_css('input#dcf_values_q')['value']).to eq('LODZ')
        # Changed by WP-29 (was: 2 forms): the two sort buttons are button_to
        # forms too and carry q without page.
        forms = doc.css('form.dcf-inline-form') + doc.css('form.button_to')
        expect(forms.size).to eq(4)
        forms.each do |form|
          expect(hidden('q', form).map { |n| n['value'] }).to eq(['LODZ'])
          expect(hidden('page', form)).to be_empty
        end
      end

      it 'treats a q made only of a combining mark as unfiltered (T-PAG-10)' do
        field = own_list(30)
        get show_path(field, q: "\u0301")
        expect(row_values.size).to eq(30)
        expect(doc.css('table.dcf-values .dcf-sort-handle').size).to eq(30)
        expect(scripts.grep(asset.call('dcf_value_reorder', 'js')).size).to eq(1)
        expect(hidden('q')).to be_empty
        expect(doc.text).not_to include(I18n.t(:text_dcf_drag_reorder_filtered))
      end

      it 'shows text_dcf_no_matches with a Clear link when nothing matches (T-PAG-11)' do
        field = own_list(30)
        get show_path(field, q: 'zzz', show_usage: 1)
        nodata = doc.at_css('p.nodata')
        expect(nodata.text).to include(I18n.t(:text_dcf_no_matches))
        link = nodata.at_css('a')
        expect(link.text).to eq(I18n.t(:button_clear))
        expect(link['href']).to eq(show_path(field, show_usage: 1))
        expect(doc.css('table.dcf-values')).to be_empty
        expect(doc.css('.pagination')).to be_empty
        expect(doc.text).not_to include(I18n.t(:text_dcf_values_filtered, count: 0, total: 30))
      end

      it 'keeps text_no_values for a field without values, also with q' do
        field = dcf_enum_field(names: [], is_for_all: true)
        get show_path(field, q: 'x')
        expect(doc.at_css('p.nodata').text.strip).to eq(I18n.t(:text_no_values))
      end

      it 'folds each row at most once and q once per request, nothing unfiltered (G6)' do
        field = own_list(30)
        calls = 0
        allow(RedmineDependingCustomFields::ValueCollation).to receive(:key).and_wrap_original do |original, *args|
          calls += 1
          original.call(*args)
        end
        get show_path(field)
        expect(calls).to eq(0)
        get show_path(field, q: 'value 001')
        expect(calls).to be <= 30 + 1
        expect(row_values.size).to eq(11)
      end

      it 'echoes q escaped once in the search box, hidden inputs and links (G5)' do
        payloads = ['"><script>alert(1)</script>', "' onmouseover='x", '&amp;']
        field = own_list(30, extra: payloads.map { |p| "v #{p}" })
        payloads.each do |q|
          get show_path(field, q: q)
          expect(response.body).not_to include('<script>alert(1)</script>')
          expect(response.body).not_to include("' onmouseover='x\"")
          expect(doc.at_css('input#dcf_values_q')['value']).to eq(q)
          expect(hidden('q').map { |n| n['value'] }.uniq).to eq([q])
          usage = doc.css('a.icon-stats').map { |a| query_of(a['href'])['q'] }
          expect(usage).to eq([q])
        end
      end

      it 'searches on a closed project, where writes stay forbidden' do
        closed = dcf_create_project(name: 'Closed', status: :closed)
        field = dcf_list_field(values: labels(30), is_for_all: false, projects: [closed])
        as(dcf_manager(closed))
        get custom_field_configuration_field_path(closed, field, q: 'value 0001')
        expect(response).to have_http_status(200)
        expect(row_values).to eq(['Value 0001'])
      end
    end

    describe 'state preservation' do
      it 'redirects a rename on page 3 with q back to that page and search (T-PAG-6)' do
        field = own_list(1_600, 'Lodz')
        patch custom_field_configuration_rename_value_path(project, field),
              params: { old_value: 'Lodz 0060', new_value: 'Lodz 0060x', q: 'lodz', page: '3',
                        state_hash: service.state_hash(field) }
        expect(response).to redirect_to(show_path(field, q: 'lodz', page: 3))
        follow_redirect!
        expected = labels(1_600, 'Lodz')[50, 25].map { |v| v == 'Lodz 0060' ? 'Lodz 0060x' : v }
        expect(row_values).to eq(expected)
      end

      it 'keeps the redirect bare without q or page and drops an unfiltered q and page 1' do
        field = own_list(3)
        patch custom_field_configuration_rename_value_path(project, field),
              params: { old_value: 'Value 0001', new_value: 'Value 0001x', q: " \u0301", page: '1' }
        expect(response).to redirect_to(show_path(field))
        expect(response.location).not_to include('?')
      end

      it 'encodes q in the redirect and keeps nothing else of the request' do
        field = own_list(30)
        q = "Va lue&x\r\nSet-Cookie: dcf=1"
        patch custom_field_configuration_rename_value_path(project, field),
              params: { old_value: 'Value 0001', new_value: 'Value 0001x', q: q, page: '2',
                        state_hash: service.state_hash(field) }
        expect(response).to have_http_status(302)
        expect(response.location).to include('%0D%0A')
        expect(response.headers['Set-Cookie'].to_s).not_to include('dcf=1')
        expect(query_of(response.location)).to eq('q' => q, 'page' => '2')
      end

      it 'carries q and page through the confirmation panel and its pagination (T-PAG-7)' do
        field = dcf_list_field(values: labels(1_200), is_for_all: true)
        patch custom_field_configuration_rename_value_path(project, field),
              params: { old_value: 'Value 0030', new_value: 'Value 0030x', q: 'value', page: '2',
                        state_hash: service.state_hash(field) }
        expect(response).to have_http_status(422)
        form = doc.at_css('.dcf-confirm-panel form')
        expect(form.css('input[name="q"]').map { |n| n['value'] }).to eq(['value'])
        expect(form.css('input[name="page"]').map { |n| n['value'] }).to eq(['2'])
        expect(row_values).to eq(labels(1_200)[25, 25])
        hrefs = doc.css('span.pagination a[href]').map { |a| a['href'] }
        expect(hrefs).not_to be_empty
        hrefs.each do |href|
          expect(URI.parse(href).path).to eq(show_path(field))
          expect(query_of(href)['q']).to eq('value')
          expect(query_of(href).keys & %w[old_value new_value state_hash enumeration_id confirm]).to be_empty
        end

        fields = form.css('input[type="hidden"]').to_h { |n| [n['name'], n['value']] }
        fields.delete('_method')
        fields.delete('authenticity_token')
        patch form['action'], params: fields.merge('confirm' => '1')
        expect(response).to redirect_to(show_path(field, q: 'value', page: 2))
        expect(field.reload.possible_values).to include('Value 0030x')
      end

      it 're-renders a refused rename on the posted page and search' do
        field = own_list(1_200)
        patch custom_field_configuration_rename_value_path(project, field),
              params: { old_value: 'Value 0060', new_value: 'Value 0061', q: 'value', page: '3',
                        state_hash: service.state_hash(field) }
        expect(response).to have_http_status(422)
        expect(row_values).to eq(labels(1_200)[50, 25])
        expect(hidden('q', doc.at_css('form.dcf-inline-form')).map { |n| n['value'] }).to eq(['value'])
      end

      it 'jumps to the page of an added value and drops q (add_value)' do
        field = own_list(520)
        post custom_field_configuration_add_value_path(project, field), params: { value: ' ZZZ ', q: 'value', page: '3' }
        expect(response).to redirect_to(show_path(field, page: 21))
        post custom_field_configuration_add_value_path(project, field), params: { value: 'AAA', position: '0' }
        expect(response).to redirect_to(show_path(field))
        small = own_list(499)
        post custom_field_configuration_add_value_path(project, small), params: { value: 'Z', q: 'value' }
        expect(response).to redirect_to(show_path(small))
        enum = enum_with(520)
        post custom_field_configuration_add_value_path(project, enum), params: { value: 'New' }
        expect(response).to redirect_to(show_path(enum, page: 21))
      end

      it 'keeps the redirect of a removal on the last page; the page is clamped on display' do
        field = own_list(501)
        delete custom_field_configuration_remove_value_path(project, field),
               params: { value: 'Value 0501', page: '21', state_hash: service.state_hash(field) }
        expect(response).to redirect_to(show_path(field, page: 21))
        follow_redirect!
        expect(response).to have_http_status(200)
        expect(row_values.size).to eq(500)
        expect(doc.css('table.dcf-values .dcf-sort-handle').size).to eq(500)
      end

      it 'still refuses a partial reorder on a large list; a full permutation passes' do
        field = own_list(520)
        patch custom_field_configuration_reorder_values_path(project, field),
              params: { ordered_values: labels(520).first(25), state_hash: service.state_hash(field) }
        expect(response).to have_http_status(422)
        expect(field.reload.possible_values).to eq(labels(520))
        row = RedmineDependingCustomFields::ConfigAuditEvent.order(:id).last
        expect([row.status, row.error_message]).to eq(%w[validation_failed error_reorder_mismatch])
        patch custom_field_configuration_reorder_values_path(project, field),
              params: { ordered_values: labels(520).reverse, state_hash: service.state_hash(field) }
        expect(response).to have_http_status(302)
      end
    end

    describe 'enumeration pages in page mode (WP-30)' do
      # Changed by WP-30 (was: read-only rows): a filtered page renders the
      # page-mode form; the delete links keep q and state_hash.
      it 'renders a filtered page as the page-mode form with list-state delete links' do
        enum = enum_with(30)
        get show_path(enum, q: 'n002')
        expect(row_values.size).to eq(10)
        form = doc.at_css('form.dcf-enumerations-form')
        expect(form['data-dcf-page-scope']).to eq('1')
        expect(hidden('batch_scope', form).map { |n| n['value'] }).to eq(['page'])
        expect(hidden('q', form).map { |n| n['value'] }).to eq(['n002'])
        expect(form.css('input[type="text"][name$="[name]"]').map { |n| n['value'] })
          .to eq((20..29).map { |i| format('N%04d', i) })
        expect(doc.css('input.dcf-position, .dcf-sort-handle')).to be_empty
        links = doc.css('table.dcf-values a.icon-del')
        expect(links.size).to eq(10)
        links.each { |a| expect(query_of(a['href'])).to include('q' => 'n002', 'state_hash' => service.state_hash(enum)) }
      end

      # Changed by WP-30 (was: read-only rows): a paginated page renders the
      # page-mode form with the page in the form and in the delete links.
      it 'renders a paginated page as the page-mode form with the page in the delete links' do
        enum = enum_with(520)
        get show_path(enum, page: 2)
        expect(row_values.size).to eq(25)
        form = doc.at_css('form.dcf-enumerations-form')
        expect(hidden('page', form).map { |n| n['value'] }).to eq(['2'])
        expect(form.css('input[name^="enumerations["][name$="[name]"]').size).to eq(25)
        doc.css('table.dcf-values a.icon-del').each { |a| expect(query_of(a['href'])['page']).to eq('2') }
        expect(doc.text).to include(I18n.t(:text_dcf_drag_reorder_large, max: 500))
      end
    end

    describe 'show usage' do
      it 'shows exact usage of the page rows through page_usage, never per value' do
        field = own_list(520)
        2.times { dcf_issue_with_value(project, field, 'Value 0030') }
        dcf_issue_with_value(dcf_create_project(name: 'Elsewhere'), field, 'Value 0030')
        expect(RedmineDependingCustomFields::UsageCalculator).not_to receive(:usage_here)
        expect(RedmineDependingCustomFields::UsageCalculator).not_to receive(:parent_key_refs)
        get show_path(field, show_usage: 1, page: 2)
        row = doc.at_css('table.dcf-values tr[data-dcf-value="Value 0030"]')
        expect(row.css('td').map { |td| td.text.strip }[1, 3]).to eq(%w[2 1 0])
        doc.css('span.pagination a[href]').each { |a| expect(query_of(a['href'])['show_usage']).to eq('1') }
      end

      it 'runs no usage query on an enumeration field' do
        enum = enum_with(3)
        expect(RedmineDependingCustomFields::UsageCalculator).not_to receive(:page_usage)
        get show_path(enum, show_usage: 1)
        expect(response).to have_http_status(200)
      end
    end

    describe 'query counts (G6, T-PAG-9)' do
      before { allow(Setting).to receive(:per_page_options_array).and_return([25, 100]) }

      def usage_world(count)
        field = dcf_list_field(values: labels(count), is_for_all: false, projects: [project])
        child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[c1 c2],
                               parent: field, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'Value 0001' => %w[c1], 'Value 0003' => %w[c2] },
                                    default_value_dependencies: { 'Value 0001' => 'c1' })
        %w[Value\ 0001 Value\ 0002 Value\ 0003].each { |v| dcf_issue_with_value(project, field, v) }
        CustomField.find(field.id)
      end

      def queries(field, params)
        dcf_count_queries { get show_path(field, params) }
      end

      it 'are the same for per_page 25 and 100 and for the first and the last page with show_usage' do
        field = usage_world(600)
        get show_path(field, show_usage: 1)
        c25 = queries(field, show_usage: 1, per_page: 25)
        c100 = queries(field, show_usage: 1, per_page: 100)
        expect(row_values.size).to eq(100)
        expect(c100).to eq(c25)
        first = queries(field, show_usage: 1, per_page: 25, page: 1)
        last = queries(field, show_usage: 1, per_page: 25, page: 24)
        expect(row_values.first).to eq('Value 0576')
        expect(last).to eq(first)
      end

      it 'are the same for 25 and 500 values with and without show_usage' do
        small = usage_world(25)
        large = usage_world(500)
        get show_path(small)
        [{}, { show_usage: 1 }].each do |params|
          small_count = queries(small, params)
          large_count = queries(large, params)
          expect(row_values.size).to eq(500)
          expect(large_count).to eq(small_count)
        end
      end

      it 'are the same for 25 and 500 enumerations, show_usage changing nothing' do
        small = enum_with(25)
        large = enum_with(500)
        get show_path(small)
        base = queries(small, {})
        expect(queries(large, {})).to eq(base)
        expect(queries(large, show_usage: 1)).to eq(base)
      end
    end

    describe 'assets (T-ASSET-1, T-ASSET-2)' do
      def config_css
        stylesheets.grep(asset.call('dcf_config', 'css'))
      end

      it 'links dcf_config.css exactly once on every project configuration page and the admin audit page' do
        parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
        child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1], parent: parent, is_for_all: true)
        [show_path(own_list(3)), custom_field_configuration_field_dependencies_path(project, child),
         settings_project_path(project, tab: 'custom_field_configuration'),
         custom_field_configuration_audit_path(project)].each do |path|
          get path
          expect(response).to have_http_status(200)
          expect(config_css.size).to eq(1), path
        end
        as(dcf_admin)
        get dcf_config_audit_path
        expect(config_css.size).to eq(1)
        get project_path(project)
        expect(config_css).to be_empty
      end

      it 'includes dcf_value_reorder.js only when the list is sortable' do
        { own_list(3) => 1, own_list(1, 'One') => 0, own_list(520) => 0 }.each do |field, count|
          get show_path(field)
          expect(scripts.grep(asset.call('dcf_value_reorder', 'js')).size).to eq(count)
        end
        get show_path(own_list(30), q: 'value 001')
        expect(scripts.grep(/dcf_value_reorder/)).to be_empty
      end

      it 'moves the project rules into dcf_config.css with unchanged selectors' do
        dir = File.expand_path('../../assets/stylesheets', __dir__)
        config = File.read(File.join(dir, 'dcf_config.css'))
        global = File.read(File.join(dir, 'depending_custom_fields.css'))
        moved = ['.dcf-scope-badge', '.dcf-scope-global', '.dcf-scope-shared', '.dcf-scope-project',
                 '.dcf-confirm-panel ul', '.dcf-status-success', '.dcf-status-failed', '.dcf-status-neutral',
                 '.dcf-inline-form', '.dcf-values .dcf-sort-handle', '.dcf-values-sortable .dcf-sort-handle']
        moved.each do |selector|
          expect(config).to include(selector)
          expect(global).not_to include(selector)
        end
        %w[.dcf-values-filter .dcf-values-toolbar .dcf-page-scope-note].each { |s| expect(config).to include(s) }
      end
    end

    describe 'banners through dcf_flash_box (P-D12)' do
      it 'shows the global or shared warning with the core icon and none for a project-only field' do
        other = dcf_create_project(name: "Other-#{SecureRandom.hex(3)}")
        global = dcf_list_field(values: %w[A B], is_for_all: true)
        shared = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project, other])
        own = own_list(2)
        { global => :text_global_field_warning, shared => :text_shared_field_warning, own => nil }.each do |field, key|
          get show_path(field)
          banners = doc.css('div.flash.warning:not([id])')
          if key
            expect(banners.size).to eq(1)
            expect(banners.first.text.strip).to eq(I18n.t(key))
            expect(banners.first.css('svg').size).to eq(Redmine::VERSION::MAJOR >= 6 ? 1 : 0)
          else
            expect(banners).to be_empty
          end
        end
      end

      it 'renders the confirmation panel in a flash box inside .dcf-confirm-panel' do
        field = dcf_list_field(values: %w[A B], is_for_all: true)
        patch custom_field_configuration_rename_value_path(project, field), params: { old_value: 'A', new_value: 'A2' }
        expect(response).to have_http_status(422)
        box = doc.at_css('div.dcf-confirm-panel > div.flash.warning:not([id])')
        expect(box).not_to be_nil
        expect(box.css('svg').size).to eq(Redmine::VERSION::MAJOR >= 6 ? 1 : 0)
        expect(box.css('ul li').size).to be >= 3
        expect(box.at_css('form input[name="confirm"][type="checkbox"]')).not_to be_nil
        expect(doc.css('.dcf-confirm-panel ul')).not_to be_empty
      end
    end

    describe 'confirmation panel naming (SD-16)' do
      let(:other) { dcf_create_project(name: "Other-#{SecureRandom.hex(3)}") }
      let(:other_role) { dcf_create_role }

      def child_of(parent, name, key, enum: false, **options)
        child = if enum
                  dcf_enum_field(format: 'depending_enumeration', name: name, names: %w[c1], parent: parent)
                else
                  dcf_list_field(format: 'depending_list', name: name, values: %w[c1], parent: parent, **options)
                end
        child_key = enum ? child.enumerations.first.id.to_s : 'c1'
        dcf_set_dependencies(child, value_dependencies: { key => [child_key] })
      end

      # Visible and restricted (the manager's role) are named; secret (another
      # role) and outside (not used in the project) are only counted.
      def world(parent, key, enum: false)
        visible = child_of(parent, "Visible-#{SecureRandom.hex(3)}", key, enum: enum)
        secret = child_of(parent, "SecretChild-#{SecureRandom.hex(3)}", key, enum: enum)
        secret.update!(visible: false, role_ids: [other_role.id])
        outside = child_of(parent, "OutChild-#{SecureRandom.hex(3)}", key, enum: enum)
        outside.update!(is_for_all: false)
        outside.projects = [other]
        restricted = child_of(parent, "Restricted-#{SecureRandom.hex(3)}", key, enum: enum)
        restricted.update!(visible: false, role_ids: [manager.members.first.roles.first.id])
        { named: [visible, restricted], hidden: [secret, outside] }
      end

      def affected_line
        label = I18n.t(:label_affected_child_fields)
        doc.css('.dcf-confirm-panel li').map { |li| li.text.squish }.find { |text| text.start_with?(label) }
      end

      def expect_panel(named, hidden, total)
        expect(response).to have_http_status(422)
        expect(response.body).to include(I18n.t(:text_dcf_confirm_understand))
        names = named.map(&:name).sort_by { |n| named.find { |f| f.name == n }.id }
        expect(affected_line).to eq("#{I18n.t(:label_affected_child_fields)}: #{total} (#{names.join(', ')})")
        hidden.each { |field| expect(response.body).not_to include(field.name) }
      end

      it 'names only nameable children on a list rename and a list removal; an admin sees all' do
        parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B], is_for_all: true)
        fields = world(parent, 'A')

        patch custom_field_configuration_rename_value_path(project, parent), params: { old_value: 'A', new_value: 'A2' }
        expect_panel(fields[:named], fields[:hidden], 4)

        delete custom_field_configuration_remove_value_path(project, parent), params: { value: 'A' }
        expect_panel(fields[:named], fields[:hidden], 4)

        as(dcf_admin)
        patch custom_field_configuration_rename_value_path(project, parent), params: { old_value: 'A', new_value: 'A2' }
        all = (fields[:named] + fields[:hidden]).sort_by(&:id)
        expect(affected_line).to eq("#{I18n.t(:label_affected_child_fields)}: 4 (#{all.map(&:name).join(', ')})")
      end

      it 'names only nameable children on an enumeration removal through the delete link' do
        parent = dcf_enum_field(name: "EnumParent-#{SecureRandom.hex(3)}", names: %w[P1 P2], is_for_all: true)
        key = parent.enumerations.order(:position).first.id.to_s
        fields = world(parent, key, enum: true)
        get show_path(parent)
        href = doc.css('table.dcf-values a.icon-del').map { |a| a['href'] }.find { |h| query_of(h)['enumeration_id'] == key }

        delete href
        expect_panel(fields[:named], fields[:hidden], 4)
      end

      it 'shows only the count when every affected child is hidden, and escapes names once' do
        parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B], is_for_all: true)
        secret = child_of(parent, "SecretChild-#{SecureRandom.hex(3)}", 'A')
        secret.update!(visible: false, role_ids: [other_role.id])
        patch custom_field_configuration_rename_value_path(project, parent), params: { old_value: 'A', new_value: 'A2' }
        expect(affected_line).to eq("#{I18n.t(:label_affected_child_fields)}: 1")
        expect(response.body).not_to include(secret.name)
        expect(doc.css('.dcf-confirm-panel li').map(&:text).join).to include(
          "#{I18n.t(:label_dependency_references)}: 1"
        )

        markup = '<img src=x onerror=alert(1)>'
        child_of(parent, markup, 'B')
        patch custom_field_configuration_rename_value_path(project, parent), params: { old_value: 'B', new_value: 'B2' }
        expect(doc.css('.dcf-confirm-panel img')).to be_empty
        expect(response.body.scan(ERB::Util.html_escape(markup)).size).to eq(1)
        expect(response.body).not_to include('&amp;lt;')
        expect(affected_line).to eq("#{I18n.t(:label_affected_child_fields)}: 1 (#{markup})")
      end
    end

    describe 'markup' do
      it 'drops duplicate ids from the page and labels the rename text fields' do
        field = own_list(3)
        get show_path(field)
        ids = doc.css('#content [id]').map { |node| node['id'] }
        expect(ids.size).to eq(ids.uniq.size)
        expect(doc.css('input[name="new_value"]').map { |n| n['aria-label'] }).to eq([I18n.t(:label_dcf_value)] * 3)
      end

      it 'renders the filtered and the paginated page in German and French without missing translations (G4, G8)' do
        [['de', :de], ['fr', :fr]].each do |language, locale|
          manager.update_column(:language, language)
          I18n.with_locale(I18n.locale) { get show_path(own_list(30), q: 'value 001') }
          expect(response.body).not_to include('translation missing')
          expect(response.body).not_to include('translation_missing')
          expect(doc.text).to include(I18n.t(:text_dcf_values_filtered, count: 11, total: 30, locale: locale))
          expect(doc.text).to include(I18n.t(:text_dcf_drag_reorder_filtered, locale: locale))
          I18n.with_locale(I18n.locale) { get show_path(own_list(520)) }
          expect(response.body).not_to include('translation missing')
          expect(response.body).not_to include('translation_missing')
          expect(doc.text).to include(I18n.t(:text_dcf_drag_reorder_large, max: 500, locale: locale))
        end
      end

      it 'has the registry texts for the WP-28 keys in the four locales' do
        registry = File.read(File.expand_path('../../docs/specs/large_lists_i18n_registry.md', __dir__),
                             encoding: 'UTF-8')
        locales = [:en, :de, :fr, :nl]
        %w[text_dcf_values_filtered text_dcf_drag_reorder_large text_dcf_drag_reorder_filtered].each do |key|
          row = registry.lines.find { |line| line.start_with?("| `#{key}` | WP-28 |") }
          cells = row.split(' | ').map(&:strip)
          texts = cells[4, 4].map { |cell| cell.delete_suffix(' |').delete_suffix('|').strip }
          locales.each_with_index do |locale, i|
            raw = I18n.backend.send(:translations).dig(locale, key.to_sym)
            expect(raw).to eq(texts[i]), "#{key} #{locale}"
          end
        end
      end
    end

    describe 'audit page (project design 4)' do
      it 'selects only the listed columns, counts every row and renders the rows unchanged' do
        events = RedmineDependingCustomFields::ConfigAuditEvent
        30.times do |i|
          events.create!(project_id: project.id, action: 'rename_value', status: 'success',
                         custom_field_name: "F#{i}", acting_user_name: 'M', changes_summary: "<b>S#{i}</b>",
                         before_value: 'x' * 16_384, after_value: 'y' * 16_384, created_at: Time.now - i)
        end
        sqls = []
        callback = lambda do |*, payload|
          sqls << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
        end
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          get custom_field_configuration_audit_path(project)
        end
        expect(response).to have_http_status(200)
        # G6: no absolute query counts; the row query is found by its shape.
        audit = sqls.grep(/dcf_config_audit_events/)
        row_sql = audit.find { |sql| sql =~ /LIMIT/i && sql !~ /COUNT\(/i }
        expect(row_sql).to be_present
        expect(row_sql).not_to match(/before_value|after_value|\.\*|SELECT \*/)
        expect(audit.grep(/COUNT\(\*\)/i)).not_to be_empty
        rows = doc.css('table.dcf-audit-list tbody tr')
        expect(rows.size).to eq(25)
        expect(rows.first.css('td').map { |td| td.text.strip }[1..]).to eq(['M', 'F0', 'rename_value', 'success', '<b>S0</b>'])
        expect(doc.css('span.pagination span.items').text).to eq('(1-25/30)')
        get "#{custom_field_configuration_audit_path(project)}?page[]=1"
        expect(response).to have_http_status(200)
      end
    end
  end

  # --- WP-29: sort A-Z / Z-A ----------------------------------------------
  # Project design 5 and 6 (T-SORT-1..6), UD-23, UD-24, quality G4 and G5.
  describe 'sort A-Z / Z-A (WP-29)' do
    let(:manager) { dcf_manager(project) }
    let(:service) { RedmineDependingCustomFields::BaseService }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }

    before { as(manager) }

    def doc
      Nokogiri::HTML(response.body)
    end

    def show_path(field, params = {}, in_project = project)
      custom_field_configuration_field_path(in_project, field, params)
    end

    def sort_path(field, in_project = project)
      custom_field_configuration_sort_values_path(in_project, field)
    end

    def labels(count, prefix = 'Value')
      (1..count).map { |i| format('%<prefix>s %<i>04d', prefix: prefix, i: i) }
    end

    def own_list(values)
      dcf_list_field(values: values, is_for_all: false, projects: [project])
    end

    def enum_with(count, inactive: [])
      field = dcf_enum_field(names: [], is_for_all: true)
      CustomFieldEnumeration.insert_all(
        (1..count).map do |i|
          { custom_field_id: field.id, name: format('N%04d', i), position: i, active: !inactive.include?(i) }
        end
      )
      CustomField.find(field.id)
    end

    def enum_state(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:position, :id).pluck(:name, :position, :active)
    end

    def rows(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def row_values
      doc.css('table.dcf-values tbody tr').map { |tr| tr['data-dcf-value'] }
    end

    # The sort buttons are found by their action (project design 5): Rails
    # 6.1 to 8.1 render button_to as a form holding an input[type=submit].
    def sort_forms
      doc.css('form[action$="/values/sort"]')
    end

    def hidden_fields(form)
      form.css('input[type="hidden"]').reject { |n| n['name'] == 'authenticity_token' }
          .to_h { |n| [n['name'], n['value']] }
    end

    def label_of(form)
      button = form.at_css('[type="submit"]')
      button.name == 'button' ? button.text.strip : button['value']
    end

    def confirm_of(form)
      form.at_css('[data-confirm]')['data-confirm']
    end

    def query_of(href)
      Rack::Utils.parse_nested_query(URI.parse(href).query.to_s)
    end

    # UPDATE statements on the two tables a sort writes.
    def write_sqls(&block)
      sqls = []
      callback = lambda do |*, payload|
        sql = payload[:sql].to_s
        sqls << sql if sql.match?(/\AUPDATE\s+[`"]?(custom_fields|custom_field_enumerations)[`"]?\s/i)
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
      sqls
    end

    describe 'route and permission' do
      it 'routes PATCH .../values/sort to sort_values and no other verb' do
        field = own_list(%w[b a])
        path = sort_path(field)
        expect(path).to eq("/projects/#{project.to_param}/custom_field_configuration/fields/#{field.id}/values/sort")
        expect(Rails.application.routes.recognize_path(path, method: :patch))
          .to include(controller: 'project_custom_field_configuration', action: 'sort_values',
                      project_id: project.to_param, field_id: field.id.to_s)
        [:get, :post, :put, :delete].each do |verb|
          expect { Rails.application.routes.recognize_path(path, method: verb) }
            .to raise_error(ActionController::RoutingError)
        end
      end

      it 'adds sort_values to manage_project_custom_field_configuration (granted to its holders)' do
        permission = Redmine::AccessControl.permission(:manage_project_custom_field_configuration)
        expect(permission.actions).to include('project_custom_field_configuration/sort_values',
                                              'project_custom_field_configuration/reorder_values')
        expect(permission.require_member?).to be(true)
        expect(permission.read?).to be(true)
        expect(Redmine::AccessControl.permissions.count { |p| p.actions.include?('project_custom_field_configuration/sort_values') })
          .to eq(1)
      end
    end

    describe 'sorting (T-SORT-1, T-SORT-2)' do
      it 'sorts a list A-Z, redirects to the field page and flashes notice_values_sorted (T-SORT-1)' do
        field = own_list(['b', 'A', "\u00E9", 'a'])
        patch sort_path(field), params: { direction: 'asc', state_hash: service.state_hash(field) }
        expect(response).to redirect_to(show_path(field))
        expect(flash[:notice]).to eq(I18n.t(:notice_values_sorted))
        expect(field.reload.possible_values).to eq(['A', 'a', 'b', "\u00E9"])
        row = rows(field).last
        expect([row.action, row.status, row.changes_summary]).to eq(['sort_values', 'success', 'Sorted 4 value(s) A-Z (4 moved)'])
        follow_redirect!
        expect(doc.at_css('#flash_notice').text).to include(I18n.t(:notice_values_sorted))
        expect(row_values).to eq(['A', 'a', 'b', "\u00E9"])
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global enumeration; was
      # no confirm.
      it 'sorts enumerations Z-A with the inactive ones among them; a stale page then gets 409 (T-SORT-2, UD-24)' do
        field = dcf_enum_field(names: %w[b D a c])
        field.enumerations.find_by(name: 'a').update!(active: false)
        old_hash = service.state_hash(field)
        patch sort_path(field), params: { direction: 'desc', state_hash: old_hash, confirm: '1' }
        expect(response).to redirect_to(show_path(field))
        expect(enum_state(field)).to eq([['D', 1, true], ['c', 2, true], ['b', 3, true], ['a', 4, false]])
        follow_redirect!
        expect(row_values).to eq(CustomFieldEnumeration.where(custom_field_id: field.id).order(:position).pluck(:id).map(&:to_s))
        patch custom_field_configuration_update_enumerations_path(project, field),
              params: { state_hash: old_hash, enumerations: {} }
        expect(response).to have_http_status(409)
      end

      # Flipped by WP-34 (UD-23 changed by the owner on 2026-11-02): a global
      # and a shared field get the confirmation panel without confirm (or
      # with confirm '0') and sort with confirm '1'; was 'sorts a global and
      # a shared field without a confirmation panel, confirm ignored (UD-23)'.
      it 'sorts a global and a shared field only after the confirmation panel (UD-23, WP-34)' do
        global = dcf_list_field(values: %w[c b a], is_for_all: true)
        shared = dcf_list_field(values: %w[c b a], is_for_all: false,
                                projects: [project, dcf_create_project(name: "Other-#{SecureRandom.hex(3)}")])
        [[global, {}], [shared, { confirm: '0' }]].each do |field, extra|
          patch sort_path(field), params: { direction: 'asc' }.merge(extra)
          expect(response).to have_http_status(422)
          expect(doc.css('.dcf-confirm-panel').size).to eq(1)
          expect(field.reload.possible_values).to eq(%w[c b a])
          expect(rows(field)).to be_empty
          patch sort_path(field), params: { direction: 'asc', confirm: '1' }
          expect(response).to redirect_to(show_path(field))
          expect(field.reload.possible_values).to eq(%w[a b c])
          follow_redirect!
          expect(doc.css('.dcf-confirm-panel')).to be_empty
          expect(rows(field).last.status).to eq('success')
        end
      end

      it 'lists sort_values rows on the project audit page' do
        field = own_list(%w[b a])
        patch sort_path(field), params: { direction: 'asc' }
        get custom_field_configuration_audit_path(project)
        cells = doc.css('table.dcf-audit-list tbody tr').first.css('td').map { |td| td.text.strip }
        expect(cells).to include('sort_values', 'success', 'Sorted 2 value(s) A-Z (2 moved)')
      end
    end

    describe 'refusals (T-SORT-3..6, G5)' do
      def attempt(field, in_project = project, params = { direction: 'asc' })
        patch sort_path(field, in_project), params: params
      end

      it 're-renders 409 on a stale state_hash with the posted q, changing nothing (T-SORT-3)' do
        field = own_list(labels(30).reverse)
        attempt(field, project, direction: 'asc', state_hash: 'stale', q: 'value')
        expect(response).to have_http_status(409)
        expect(doc.at_css('#flash_error').text).to include(I18n.t(:error_stale_edit))
        expect(doc.at_css('input#dcf_values_q')['value']).to eq('value')
        expect(field.reload.possible_values).to eq(labels(30).reverse)
        expect([rows(field).last.status, rows(field).last.error_message]).to eq(%w[validation_failed error_stale_edit])
        expect(sort_forms.map { |form| hidden_fields(form)['state_hash'] }.uniq).to eq([service.state_hash(field)])
      end

      it 'refuses any direction but asc or desc with 422 and one row each, never echoing it (T-SORT-5)' do
        field = own_list(%w[b a])
        [{}, { direction: '' }, { direction: 'ASC' }, { direction: ' asc' }, { direction: 'up<b>' },
         { direction: ['asc'] }, { direction: { 'x' => 'asc' } }].each do |extra|
          expect { attempt(field, project, extra.merge(state_hash: service.state_hash(field))) }
            .to change { rows(field).count }.by(1)
          expect(response).to have_http_status(422)
          expect(doc.at_css('#flash_error').text).to include(I18n.t(:error_reorder_mismatch))
          row = rows(field).last
          expect([row.status, row.error_message, row.changes_summary]).to eq(['validation_failed', 'error_reorder_mismatch', nil])
          expect(response.body).not_to include('up<b>')
          expect(response.body).not_to include('up&lt;b&gt;')
        end
        expect(field.reload.possible_values).to eq(%w[b a])
      end

      it 'refuses anonymous users, non-members, members without the permission and managers of another project ' \
         'before any write (T-SORT-4)' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        count = events.count
        other = dcf_create_project(name: "Other-#{SecureRandom.hex(3)}")
        sqls = write_sqls do
          [dcf_create_user("stranger-#{SecureRandom.hex(3)}"), dcf_plain_member(project), dcf_manager(other)].each do |user|
            as(user)
            attempt(field)
            expect(response).to have_http_status(403)
          end
          # G5: an anonymous HTML request is sent to the login (require_login).
          as(User.anonymous)
          attempt(field)
          expect(response).to have_http_status(302)
          expect(response.location).to match(%r{/login(\?|\z)})
        end
        expect(sqls).to be_empty
        expect(enum_state(field)).to eq(before)
        expect(events.count).to eq(count)
      end

      it 'sorts for the manager and for an administrator who is not a member' do
        [manager, dcf_admin].each do |user|
          as(user)
          field = own_list(%w[c b a])
          attempt(field)
          expect(response).to redirect_to(show_path(field))
          expect(field.reload.possible_values).to eq(%w[a b c])
        end
      end

      it 'answers 403 on a closed project for the manager and an administrator, with no write and no row (T-SORT-4)' do
        closed = dcf_create_project(name: 'Closed', status: :closed)
        field = dcf_list_field(values: %w[c b a], is_for_all: true)
        count = events.count
        [dcf_manager(closed), dcf_admin].each do |user|
          as(user)
          get show_path(field, {}, closed)
          expect(response).to have_http_status(200)
          expect(sort_forms.size).to eq(2)
          sqls = write_sqls { attempt(field, closed) }
          expect(response).to have_http_status(403)
          expect(response.body).to include(I18n.t(:error_project_archived))
          expect(sqls).to be_empty
        end
        expect(field.reload.possible_values).to eq(%w[c b a])
        expect(events.count).to eq(count)
      end

      it 'answers 403 on an archived project for the manager and an administrator (T-SORT-6)' do
        archived = dcf_create_project(name: 'Archived', status: :archived)
        field = dcf_list_field(values: %w[c b a], is_for_all: true)
        count = events.count
        [dcf_manager(archived), dcf_admin].each do |user|
          as(user)
          get show_path(field, {}, archived)
          expect(response).to have_http_status(403)
          attempt(field, archived)
          expect(response).to have_http_status(403)
        end
        expect(field.reload.possible_values).to eq(%w[c b a])
        expect(events.count).to eq(count)
      end

      it 'answers 403 with one authorization_failed row when the request reaches the service without the permission' do
        field = own_list(%w[b a])
        as(dcf_plain_member(project))
        allow_any_instance_of(User).to receive(:allowed_to?).and_wrap_original do |original, action, *args, **opts, &block|
          if action.is_a?(Hash)
            true
          elsif action == :manage_project_custom_field_configuration
            false
          else
            original.call(action, *args, **opts, &block)
          end
        end
        expect { attempt(field) }.to change { rows(field).where(status: 'authorization_failed').count }.by(1)
        expect(response).to have_http_status(403)
        row = rows(field).last
        expect([row.action, row.error_message, row.changes_summary, row.before_value, row.after_value])
          .to eq(['authorization_failed', 'error_forbidden', nil, nil, nil])
        expect(field.reload.possible_values).to eq(%w[b a])
      end

      it 'answers 404 for a field outside the project, 422 for an unsupported format, 403 to a non-member for any id' do
        other = dcf_create_project(name: "Other-#{SecureRandom.hex(3)}")
        foreign = dcf_list_field(name: "Foreign-#{SecureRandom.hex(3)}", values: %w[SECRET-V B],
                                 is_for_all: false, projects: [other])
        attempt(foreign)
        expect(response).to have_http_status(404)
        expect(response.body).not_to include(foreign.name)
        expect(response.body).not_to include('SECRET-V')
        bool = IssueCustomField.create!(name: "Bool-#{SecureRandom.hex(3)}", field_format: 'bool', is_for_all: true)
        attempt(bool)
        expect(response).to have_http_status(422)
        as(dcf_create_user("stranger-#{SecureRandom.hex(3)}"))
        patch custom_field_configuration_sort_values_path(project, 99_999_999), params: { direction: 'asc' }
        expect(response).to have_http_status(403)
        expect(foreign.reload.possible_values).to eq(%w[SECRET-V B])
        expect(rows(foreign).count + rows(bool).count).to eq(0)
      end

      it 'carries an authenticity token and answers 422 without one when forgery protection is on' do
        field = own_list(%w[b a])
        protection = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        begin
          get show_path(field)
          expect(sort_forms.size).to eq(2)
          sort_forms.each do |form|
            expect(form.css('input[type="hidden"][name="authenticity_token"]').size).to eq(1)
            expect(form.css('input[type="hidden"][name="_method"][value="patch"]').size).to eq(1)
          end
          attempt(field)
        ensure
          ActionController::Base.allow_forgery_protection = protection
        end
        expect(response).to have_http_status(422)
        expect(field.reload.possible_values).to eq(%w[b a])
        expect(rows(field).count).to eq(0)
      end

      it 'refuses in order: closed project, then a stale state, then the direction' do
        closed = dcf_create_project(name: 'Closed', status: :closed)
        field = dcf_list_field(values: %w[b a], is_for_all: true)
        as(dcf_manager(closed))
        attempt(field, closed, direction: 'up', state_hash: 'stale')
        expect(response).to have_http_status(403)
        expect(rows(field).count).to eq(0)
        as(manager)
        attempt(field, project, direction: 'up', state_hash: 'stale')
        expect(response).to have_http_status(409)
        expect(rows(field).last.error_message).to eq('error_stale_edit')
        attempt(field, project, direction: 'up', state_hash: service.state_hash(field))
        expect(response).to have_http_status(422)
        expect(rows(field).last.error_message).to eq('error_reorder_mismatch')
        expect(field.reload.possible_values).to eq(%w[b a])
      end
    end

    describe 'buttons (project design 5)' do
      it 'shows the sort buttons whenever the field has more than one value' do
        get show_path(own_list(%w[Only]))
        expect(sort_forms).to be_empty
        expect(doc.css('div.dcf-values-toolbar')).to be_empty
        get show_path(own_list(%w[Only]), q: 'x')
        expect(doc.css('div.dcf-values-toolbar form.dcf-values-filter').size).to eq(1)
        expect(sort_forms).to be_empty
        get show_path(own_list(%w[b a]))
        expect(doc.css('div.dcf-values-toolbar form[action$="/values/sort"]').size).to eq(2)
        expect(doc.css('form.dcf-values-filter')).to be_empty
        get show_path(own_list(labels(30)))
        expect(doc.css('div.dcf-values-toolbar form.dcf-values-filter').size).to eq(1)
        expect(doc.css('div.dcf-values-toolbar form[action$="/values/sort"]').size).to eq(2)
        expect(doc.css('form.dcf-values-filter form, form.dcf-values-filter input[name="direction"]')).to be_empty
        get show_path(own_list(labels(30)), q: 'zzz')
        expect(doc.at_css('p.nodata')).not_to be_nil
        expect(sort_forms.size).to eq(2)
        get show_path(enum_with(2, inactive: [1]))
        expect(sort_forms.size).to eq(2)
      end

      it 'posts direction, state_hash and a filtering q only, never page, A-Z first' do
        field = own_list(labels(520))
        get show_path(field, q: 'value', page: 2, show_usage: 1)
        expect(row_values).to eq(labels(520)[25, 25])
        forms = sort_forms
        expect(forms.size).to eq(2)
        expect(forms.map { |form| form['action'] }.uniq).to eq([sort_path(field)])
        expect(forms.map { |form| form['method'] }.uniq).to eq(['post'])
        state = service.state_hash(field)
        expect(forms.map { |form| hidden_fields(form) }).to eq(
          [{ '_method' => 'patch', 'direction' => 'asc', 'state_hash' => state, 'q' => 'value' },
           { '_method' => 'patch', 'direction' => 'desc', 'state_hash' => state, 'q' => 'value' }]
        )
        expect(forms.map { |form| label_of(form) }).to eq([I18n.t(:label_dcf_sort_az), I18n.t(:label_dcf_sort_za)])
        expect(forms.map { |form| confirm_of(form) }.uniq).to eq([I18n.t(:text_dcf_sort_confirm, count: 520)])
        get show_path(field, page: 3)
        expect(sort_forms.map { |form| hidden_fields(form).keys.sort }.uniq).to eq([%w[_method direction state_hash]])
      end

      it 'gives the sort forms the class dcf-values-sort, no ids and nothing of the drag markup (WP-30 hook)' do
        get show_path(own_list(%w[c b a]))
        sort_forms.each do |form|
          expect(form['class'].split).to include('button_to', 'dcf-values-sort')
          expect(form.css('[id]')).to be_empty
          expect(form.ancestors('table, form')).to be_empty
        end
        toolbar = doc.at_css('div.dcf-values-toolbar').to_html
        expect(toolbar).not_to include('dcf-sort-handle')
        expect(toolbar).not_to include('dcf-reorder-form')
        expect(doc.css('form.dcf-values-sort').size).to eq(2)
      end

      # Changed by WP-34 (UD-23): the global enum_with fields carry no
      # data-confirm (the server panel asks), so the count is pinned on a
      # project-only copy and in the panel; was data-confirm on the global
      # field.
      it 'counts every value in the confirm text, inactive enumerations included, also when filtered' do
        enum = enum_with(30, inactive: [3, 7])
        enum.update!(is_for_all: false)
        enum.projects = [project]
        get show_path(enum)
        expect(sort_forms.map { |form| confirm_of(form) }.uniq).to eq([I18n.t(:text_dcf_sort_confirm, count: 30)])
        get show_path(enum, q: 'n001')
        expect(sort_forms.map { |form| confirm_of(form) }.uniq).to eq([I18n.t(:text_dcf_sort_confirm, count: 30)])
        expect(sort_forms.map { |form| hidden_fields(form)['q'] }.uniq).to eq(['n001'])
        global = enum_with(30, inactive: [3, 7])
        get show_path(global, q: 'n001')
        expect(sort_forms.map { |form| form.at_css('[data-confirm]') }.uniq).to eq([nil])
        patch sort_path(global), params: { direction: 'asc', q: 'n001' }
        expect(doc.at_css('.dcf-confirm-panel').text).to include(I18n.t(:text_dcf_sort_confirm, count: 30))
        get show_path(enum_with(520), page: 2)
        expect(sort_forms.size).to eq(2)
        sort_forms.each { |form| expect(form.ancestors('form, table')).to be_empty }
      end

      it 'echoes q escaped once in the sort forms (G5)' do
        q = '"><img src=x onerror=alert(1)>'
        get show_path(own_list(labels(30)), q: q)
        expect(doc.css('div.dcf-values-toolbar img')).to be_empty
        expect(response.body).not_to include('<img src=x onerror=alert(1)>')
        expect(sort_forms.size).to eq(2)
        sort_forms.each { |form| expect(hidden_fields(form)['q']).to eq(q) }
        expect(response.body).not_to include('&amp;quot;')
      end

      it 'renders the buttons, the confirm text and the notice in German and French (G4, G8)' do
        [['de', :de], ['fr', :fr]].each do |language, locale|
          manager.update_column(:language, language)
          field = own_list(%w[b a c])
          I18n.with_locale(I18n.locale) { get show_path(field) }
          expect(response.body).not_to include('translation missing')
          expect(response.body).not_to include('translation_missing')
          expect(sort_forms.map { |form| label_of(form) })
            .to eq([I18n.t(:label_dcf_sort_az, locale: locale), I18n.t(:label_dcf_sort_za, locale: locale)])
          expect(sort_forms.map { |form| confirm_of(form) }.uniq)
            .to eq([I18n.t(:text_dcf_sort_confirm, count: 3, locale: locale)])
          I18n.with_locale(I18n.locale) { patch sort_path(field), params: { direction: 'asc' } }
          expect(flash[:notice]).to eq(I18n.t(:notice_values_sorted, locale: locale))
        end
      end

      it 'has the registry texts for the WP-29 keys in the four locales' do
        registry = File.read(File.expand_path('../../docs/specs/large_lists_i18n_registry.md', __dir__),
                             encoding: 'UTF-8')
        locales = [:en, :de, :fr, :nl]
        %w[notice_values_sorted label_dcf_sort_az label_dcf_sort_za text_dcf_sort_confirm].each do |key|
          row = registry.lines.find { |line| line.start_with?("| `#{key}` | WP-29 |") }
          cells = row.split(' | ').map(&:strip)
          texts = cells[4, 4].map { |cell| cell.delete_suffix(' |').delete_suffix('|').strip }
          locales.each_with_index do |locale, i|
            raw = I18n.backend.send(:translations).dig(locale, key.to_sym)
            expect(raw).to eq(texts[i]), "#{key} #{locale}"
          end
        end
      end

      it 'adds no query to the page: the same count for 2 and 500 values (G6)' do
        small = own_list(%w[b a])
        large = own_list(labels(500))
        get show_path(small)
        small_count = dcf_count_queries { get show_path(small) }
        large_count = dcf_count_queries { get show_path(large) }
        expect(sort_forms.size).to eq(2)
        expect(large_count).to eq(small_count)
      end
    end

    describe 'redirect' do
      it 'keeps a filtering q and drops the page' do
        field = own_list(labels(1_200).reverse)
        patch sort_path(field), params: { direction: 'asc', q: 'value', page: '3', state_hash: service.state_hash(field) }
        expect(response).to redirect_to(show_path(field, q: 'value'))
        expect(query_of(response.location)).to eq('q' => 'value')
        follow_redirect!
        expect(row_values).to eq(labels(25))
      end

      it 'redirects to the bare field path without a filtering q' do
        field = own_list(%w[b a])
        [{}, { q: '' }, { q: " \u0301", page: '2' }, { 'q' => ['x'], 'page' => '4' }].each do |extra|
          patch sort_path(field), params: { direction: 'desc' }.merge(extra)
          expect(response).to redirect_to(show_path(field))
          expect(response.location).not_to include('?')
        end
      end

      it 'encodes q in the redirect and keeps nothing else of the request' do
        field = own_list(labels(30))
        q = "Va lue&x\r\nSet-Cookie: dcf=1"
        patch sort_path(field), params: { direction: 'desc', q: q, page: '2', state_hash: service.state_hash(field) }
        expect(response).to have_http_status(302)
        expect(response.location).to include('%0D%0A')
        expect(response.headers['Set-Cookie'].to_s).not_to include('dcf=1')
        expect(query_of(response.location)).to eq('q' => q)
      end
    end

    describe 'hidden children (security)' do
      let(:other_role) { dcf_create_role }

      def hidden_child(parent)
        child = dcf_list_field(format: 'depending_list', name: "HIDDEN-CHILD-#{SecureRandom.hex(3)}",
                               values: %w[SECRET-V], parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[SECRET-V], 'B' => %w[SECRET-V] })
        child.update!(visible: false, role_ids: [other_role.id])
        child
      end

      def expect_unnamed(child)
        expect(response.body).not_to include(child.name)
        expect(response.body).not_to include('SECRET-V')
        expect(flash.to_hash.values.join(' ')).not_to include('HIDDEN-CHILD')
      end

      it 'never names a role-invisible child or shows its values when sorting the parent' do
        parent = own_list(%w[B A])
        child = hidden_child(parent)
        store = CustomField.where(id: child.id).pluck(Arel.sql('format_store')).first
        patch sort_path(parent), params: { direction: 'asc', state_hash: service.state_hash(parent) }
        expect(response).to redirect_to(show_path(parent))
        expect_unnamed(child)
        follow_redirect!
        expect_unnamed(child)
        patch sort_path(parent), params: { direction: 'up' }
        expect(response).to have_http_status(422)
        expect_unnamed(child)
        expect(CustomField.where(id: child.id).pluck(Arel.sql('format_store')).first).to eq(store)
        expect(parent.reload.possible_values).to eq(%w[A B])
        rows(parent).each do |row|
          expect(row.affected_child_field_ids).to be_nil
          expect([row.changes_summary, row.error_message, row.before_value, row.after_value].join(' '))
            .not_to include('HIDDEN-CHILD')
        end
      end

      def storage_limits
        RedmineDependingCustomFields::StorageLimits
      end

      # The save raises for the child with a storage error on it, so
      # BaseService finds a violation and asks nameable_field? (SD-16).
      def raise_storage_error_for(child)
        child.errors.add(:possible_values, storage_limits::ERROR,
                         size: storage_limits.delimited(70_000), limit: storage_limits.delimited(65_535),
                         bytes: 70_000, max_bytes: 65_535, column: 'possible_values')
        expect(storage_limits.violation_in(child).custom_field_name).to eq(child.name)
        allow_any_instance_of(CustomField).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(child))
      end

      # Redmine 5.1 en has no thousands delimiter, 6.0 and later a comma.
      def storage_flash(child)
        I18n.t(:error_dcf_values_too_large, field: child.name,
                                            size: storage_limits.delimited(70_000),
                                            limit: storage_limits.delimited(65_535))
      end

      it 'answers a storage error raised for a hidden child with the generic message' do
        parent = own_list(%w[B A])
        child = hidden_child(parent)
        raise_storage_error_for(child)
        patch sort_path(parent), params: { direction: 'asc' }
        expect(response).to have_http_status(422)
        expect(doc.at_css('#flash_error').text.strip).to eq(I18n.t(:error_save_failed))
        expect(response.body).not_to include(ERB::Util.html_escape(storage_flash(child)))
        expect_unnamed(child)
        row = rows(parent).last
        expect([row.status, row.error_message]).to eq(%w[validation_failed error_dcf_values_too_large])
        expect(row.changes_summary).not_to include('HIDDEN-CHILD')
        expect(parent.reload.possible_values).to eq(%w[B A])
      end

      it 'names a visible child in the storage error flash (counterpart of the hidden case)' do
        parent = own_list(%w[B A])
        child = dcf_list_field(format: 'depending_list', name: "SEEN-CHILD-#{SecureRandom.hex(3)}",
                               values: %w[V], parent: parent, is_for_all: false, projects: [project])
        raise_storage_error_for(child)
        patch sort_path(parent), params: { direction: 'asc' }
        expect(response).to have_http_status(422)
        expect(doc.at_css('#flash_error').text.strip).to eq(storage_flash(child))
        expect(parent.reload.possible_values).to eq(%w[B A])
      end
    end
  end

  describe 'page-scoped enumeration save (WP-30)' do
    let(:manager) { dcf_manager(project) }
    let(:service) { RedmineDependingCustomFields::BaseService }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
    let(:asset) { ->(name, ext) { /#{name}(-[0-9a-f]{7,}\.#{ext}|\.#{ext}\?\d+)\z/ } }

    before { as(manager) }

    def doc
      Nokogiri::HTML(response.body)
    end

    def show_path(field, params = {}, in_project = project)
      custom_field_configuration_field_path(in_project, field, params)
    end

    def save_path(field, in_project = project)
      custom_field_configuration_update_enumerations_path(in_project, field)
    end

    def enum_with(count, inactive: [])
      field = dcf_enum_field(names: [], is_for_all: true)
      CustomFieldEnumeration.insert_all(
        (1..count).map do |i|
          { custom_field_id: field.id, name: format('N%04d', i), position: i, active: !inactive.include?(i) }
        end
      )
      CustomField.find(field.id)
    end

    def ordered(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:position, :id).to_a
    end

    def enum_state(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id, :name, :position, :active)
    end

    def rows(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def page_form
      doc.css('form[data-dcf-page-scope]')
    end

    def scripts
      doc.css('script[src]').map { |node| node['src'] }
    end

    def values_page_scripts
      scripts.grep(asset.call('dcf_values_page', 'js'))
    end

    def hidden(name, scope = doc)
      scope.css(%(input[type="hidden"][name="#{name}"]))
    end

    def query_of(href)
      Rack::Utils.parse_nested_query(URI.parse(href).query.to_s)
    end

    def flash_error
      doc.at_css('#flash_error')&.text.to_s.strip
    end

    # The named, enabled controls of a form, as a browser posts them: text
    # and hidden inputs, checked boxes, the submit. Pairs in document order.
    def form_pairs(form, submit: true)
      form.css('input[name], select[name], textarea[name], button[name]').each_with_object([]) do |node, pairs|
        next if node['disabled']
        next if %w[checkbox radio].include?(node['type']) && !node['checked']
        next if node['type'] == 'submit' && !submit

        pairs << [node['name'], node['value'].to_s]
      end
    end

    # Posts the pairs of the rendered page form, urlencoded, with +changes+
    # ({ name => value }) applied and the checkboxes of +untick+ (enumerations)
    # unticked, so only their hidden '0' is posted.
    def post_form(form, changes = {}, untick = [])
      dropped = untick.map { |enum| ["enumerations[#{enum.id}][active]", '1'] }
      pairs = form_pairs(form).reject { |pair| %w[_method authenticity_token].include?(pair.first) || dropped.include?(pair) }
      pairs = pairs.map { |name, value| [name, changes.key?(name) ? changes[name] : value] }
      patch form['action'], params: URI.encode_www_form(pairs),
                            headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
    end

    def name_key(enum)
      "enumerations[#{enum.id}][name]"
    end

    describe 'markup (T-PAG-8, T-ASSET-3, T-ASSET-4)' do
      it 'renders the page-mode form on a paginated enumeration page' do
        field = enum_with(520)
        get show_path(field, page: 2)
        expect(response).to have_http_status(200)
        expect(page_form.size).to eq(1)
        form = page_form.first
        expect(form['action']).to eq(save_path(field))
        expect(form['method']).to eq('post')
        expect(form['class'].split).to eq(['dcf-enumerations-form'])
        expect(form['data-dcf-page-scope']).to eq('1')
        expect(form['data-dcf-warn-unsaved']).to eq(I18n.t(:text_warn_on_leaving_unsaved))
        expect(hidden('_method', form).map { |n| n['value'] }).to eq(['patch'])
        expect(hidden('batch_scope', form).map { |n| [n['value'], n['id']] }).to eq([['page', nil]])
        expect(hidden('state_hash', form).map { |n| [n['value'], n['id']] }).to eq([[service.state_hash(field), nil]])
        expect(hidden('page', form).map { |n| n['value'] }).to eq(['2'])
        expect(hidden('q', form)).to be_empty
        enums = ordered(field)[25, 25]
        names = form.css('input[type="text"][name^="enumerations["]')
        expect(names.map { |n| [n['name'], n['value'], n['id'], n['aria-label']] })
          .to eq(enums.map { |e| [name_key(e), e.name, nil, I18n.t(:label_dcf_value)] })
        enums.each do |enum|
          controls = form.css(%(input[name="enumerations[#{enum.id}][active]"]))
          expect(controls.map { |n| [n['type'], n['value'], n['id']] }).to eq([['hidden', '0', nil], ['checkbox', '1', nil]])
          expect(controls.last['checked']).to eq('checked')
          expect([controls.last['title'], controls.last['aria-label']]).to eq([I18n.t(:field_active)] * 2)
        end
        expect(form.css('[name$="[position]"], input.dcf-position, .dcf-sort-handle')).to be_empty
        expect(form.css('form')).to be_empty
        expect(form.ancestors('form')).to be_empty
        expect(form.css('[type="submit"]').size).to eq(1)
        expect(form.at_css('p.dcf-page-scope-note').text).to eq(I18n.t(:text_dcf_page_scope_save))
        expect(doc.css('.dcf-page-scope-note').size).to eq(1)
        expect(doc.css('[data-dcf-page-scope], [data-dcf-warn-unsaved]').size).to eq(1)
        expect(doc.css('form.dcf-reorder-form, form[action$="/values/reorder"]')).to be_empty
        expect(values_page_scripts.size).to eq(1)
        expect(scripts.grep(/dcf_value_reorder/)).to be_empty
        expect(scripts.size).to eq(scripts.uniq.size)
        ids = doc.css('#content [id]').map { |node| node['id'] }
        expect(ids.size).to eq(ids.uniq.size)
      end

      it 'renders the page-mode form on a filtered enumeration page with q and no page' do
        field = enum_with(30, inactive: [21])
        get show_path(field, q: 'n002')
        form = page_form.first
        expect(form.css('input[type="text"][name^="enumerations["]').size).to eq(10)
        expect(hidden('q', form).map { |n| n['value'] }).to eq(['n002'])
        expect(hidden('page', form)).to be_empty
        expect(form.css('input[type="checkbox"]').map { |n| n['checked'] }.count(nil)).to eq(1)
        expect(values_page_scripts.size).to eq(1)
      end

      it 'keeps full mode, list pages and pages without rows free of page mode' do
        full = dcf_enum_field(names: %w[X Y Z])
        list = dcf_list_field(values: (1..520).map { |i| format('Value %04d', i) }, is_for_all: true)
        cases = [show_path(full), show_path(list), show_path(list, q: 'value 001'), show_path(enum_with(30), q: 'zzz'),
                 show_path(dcf_enum_field(names: [])), show_path(dcf_enum_field(names: []), q: 'x')]
        cases.each do |path|
          get path
          expect(response).to have_http_status(200)
          expect(page_form).to be_empty, path
          expect(doc.css('[data-dcf-warn-unsaved], .dcf-page-scope-note, input[name="batch_scope"]')).to be_empty, path
          expect(values_page_scripts).to be_empty, path
        end
        get show_path(full)
        form = doc.at_css('form.dcf-enumerations-form')
        expect(form.css('input.dcf-position').size).to eq(3)
        expect(form.attributes.keys.grep(/\Adata-/)).to be_empty
        get project_path(project)
        expect(values_page_scripts).to be_empty
      end

      it 'omits data-dcf-warn-unsaved when the user preference is off, keeps it without a preference row' do
        field = enum_with(520)
        manager.pref.update!(warn_on_leaving_unsaved: '0')
        get show_path(field)
        expect(page_form.first['data-dcf-warn-unsaved']).to be_nil
        expect(page_form.first['data-dcf-page-scope']).to eq('1')
        expect(values_page_scripts.size).to eq(1)
        manager.pref.update!(warn_on_leaving_unsaved: '1')
        get show_path(field)
        expect(page_form.first['data-dcf-warn-unsaved']).to eq(I18n.t(:text_warn_on_leaving_unsaved))
        fresh = dcf_manager(project)
        UserPreference.where(user_id: fresh.id).delete_all
        as(User.find(fresh.id))
        get show_path(field)
        expect(page_form.first['data-dcf-warn-unsaved']).to eq(I18n.t(:text_warn_on_leaving_unsaved))
      end

      it 'escapes the warn text and the value names exactly once (G5)' do
        xss = '"><img src=x onerror=alert(1)>'
        field = enum_with(520)
        ordered(field)[0].update_column(:name, '"><script>alert(1)</script>')
        original = I18n.t(:text_warn_on_leaving_unsaved, locale: :en)
        I18n.backend.store_translations(:en, text_warn_on_leaving_unsaved: xss)
        begin
          get show_path(field)
        ensure
          I18n.backend.store_translations(:en, text_warn_on_leaving_unsaved: original)
        end
        # Core's own layout puts the same text into its warnLeavingUnsaved
        # script, so the raw markup of the form tag is checked.
        tag = response.body[/<form[^>]*data-dcf-page-scope[^>]*>/]
        expect(tag).to include('data-dcf-warn-unsaved="&quot;&gt;&lt;img src=x onerror=alert(1)&gt;"')
        expect(tag).not_to include('<img')
        expect(response.body).not_to include('<script>alert(1)</script>')
        expect(response.body).not_to include('&amp;quot;')
        expect(page_form.first['data-dcf-warn-unsaved']).to eq(xss)
        expect(page_form.first.css('input[type="text"]').first['value']).to eq('"><script>alert(1)</script>')
        expect(doc.css('#content img, #content script')).to be_empty
      end

      # Changed by WP-34 (UD-23): enum_with is global, so its sort buttons
      # carry no data-confirm (the server panel asks); a project-only copy
      # keeps data-confirm. Was data-confirm on the global field.
      it 'exposes the four hooks dcf_values_page.js selects on a filtered paginated page (contract pin)' do
        field = enum_with(1_200)
        get show_path(field, q: 'n0', page: 2)
        expect(doc.css('form[data-dcf-page-scope][data-dcf-warn-unsaved]').size).to eq(1)
        expect(doc.css('form.dcf-values-filter').size).to eq(1)
        expect(doc.css('span.pagination a').size).to be > 1
        expect(doc.css('form.dcf-values-sort').size).to eq(2)
        doc.css('form.dcf-values-sort').each do |form|
          expect(form.at_css('[type="submit"]')['data-confirm']).to be_nil
        end
        field.update!(is_for_all: false)
        field.projects = [project]
        get show_path(field, q: 'n0', page: 2)
        doc.css('form.dcf-values-sort').each do |form|
          expect(form.at_css('[type="submit"]')['data-confirm']).to eq(I18n.t(:text_dcf_sort_confirm, count: 1_200))
        end
        expect(doc.css('form.dcf-values-filter input#dcf_values_q').size).to eq(1)
        expect(doc.css('form[data-dcf-page-scope] form, form.dcf-values-sort[data-dcf-page-scope]')).to be_empty
      end

      it 'renders the page-mode page in German and French without missing translations (G4, G8)' do
        field = enum_with(520)
        [['de', :de], ['fr', :fr]].each do |language, locale|
          manager.update_column(:language, language)
          I18n.with_locale(I18n.locale) { get show_path(field, page: 2) }
          expect(response.body).not_to include('translation missing')
          expect(response.body).not_to include('translation_missing')
          expect(doc.at_css('p.dcf-page-scope-note').text).to eq(I18n.t(:text_dcf_page_scope_save, locale: locale))
          expect(page_form.first['data-dcf-warn-unsaved']).to eq(I18n.t(:text_warn_on_leaving_unsaved, locale: locale))
        end
      end

      it 'has the registry texts for the WP-30 key in the four locales' do
        registry = File.read(File.expand_path('../../docs/specs/large_lists_i18n_registry.md', __dir__),
                             encoding: 'UTF-8')
        row = registry.lines.find { |line| line.start_with?('| `text_dcf_page_scope_save` | WP-30 |') }
        cells = row.split(' | ').map(&:strip)
        texts = cells[4, 4].map { |cell| cell.delete_suffix(' |').delete_suffix('|').strip }
        [:en, :de, :fr, :nl].each_with_index do |locale, i|
          raw = I18n.backend.send(:translations).dig(locale, :text_dcf_page_scope_save)
          expect(raw).to eq(texts[i]), locale.to_s
        end
      end
    end

    describe 'saving (T-ENP-R1)' do
      it 'saves the rendered page form and redirects back to the page (T-ENP-R1)' do
        field = enum_with(520)
        get show_path(field, page: 2)
        first, second = ordered(field)[25, 2]
        untouched = enum_state(field).reject { |id, *| [first.id, second.id].include?(id) }
        post_form(page_form.first, { name_key(first) => 'Renamed' }, [second])
        expect(response).to redirect_to(show_path(field, page: 2))
        expect(flash[:notice]).to eq(I18n.t(:notice_values_saved))
        expect(first.reload.name).to eq('Renamed')
        expect(second.reload.active).to be false
        expect(enum_state(field).reject { |id, *| [first.id, second.id].include?(id) }).to eq(untouched)
        row = rows(field).last
        expect(row.changes_summary).to eq('Saved 25 of 520 enumeration value(s) (page): renamed 1, deactivated 1')
        follow_redirect!
        expect(page_form.first.css('input[type="text"]').first['value']).to eq('Renamed')
      end

      it 'keeps a filtering q and the page; an unfiltered first page redirects bare' do
        field = enum_with(1_600)
        get show_path(field, q: 'n1', page: 3)
        form = page_form.first
        expect(hidden('page', form).map { |n| n['value'] }).to eq(['3'])
        target = form.css('input[type="text"]').first
        post_form(form, target['name'] => 'Changed')
        expect(response).to redirect_to(show_path(field, q: 'n1', page: 3))
        expect(query_of(response.location)).to eq('q' => 'n1', 'page' => '3')
        get show_path(field)
        post_form(page_form.first)
        expect(response).to redirect_to(show_path(field))
        expect(response.location).not_to include('?')
      end

      it 'keeps the session per_page across the redirect' do
        allow(Setting).to receive(:per_page_options_array).and_return([25, 100])
        field = enum_with(520)
        get show_path(field, per_page: 100, page: 2)
        expect(page_form.first.css('input[type="text"]').size).to eq(100)
        post_form(page_form.first)
        expect(response).to redirect_to(show_path(field, page: 2))
        follow_redirect!
        expect(page_form.first.css('input[type="text"]').size).to eq(100)
      end

      it 'refuses a duplicate with 422 and re-renders the same page with a fresh state hash' do
        field = enum_with(520)
        get show_path(field, page: 2)
        posted_hash = hidden('state_hash', page_form.first).first['value']
        target = ordered(field)[25]
        post_form(page_form.first, name_key(target) => 'N0001')
        expect(response).to have_http_status(422)
        expect(flash_error).to eq(I18n.t(:error_value_duplicate))
        expect(target.reload.name).to eq('N0026')
        form = page_form.first
        expect(hidden('page', form).map { |n| n['value'] }).to eq(['2'])
        expect(hidden('state_hash', form).first['value']).to eq(service.state_hash(field))
        expect(hidden('state_hash', form).first['value']).to eq(posted_hash)
        expect(form.css('input[type="text"]').first['value']).to eq('N0026')
        expect(values_page_scripts.size).to eq(1)
      end

      it 're-renders a 409 with the posted q and page, links from the show path, and the resubmit passes' do
        field = enum_with(1_200)
        get show_path(field, q: 'n0', page: 2)
        form = page_form.first
        posted_hash = hidden('state_hash', form).first['value']
        ordered(field).last.update_column(:name, 'Elsewhere')
        post_form(form, form.css('input[type="text"]').first['name'] => 'Mine')
        expect(response).to have_http_status(409)
        expect(flash_error).to eq(I18n.t(:error_stale_edit))
        expect(response.body).not_to include('Mine')
        form = page_form.first
        expect(hidden('batch_scope', form).map { |n| n['value'] }).to eq(['page'])
        expect(hidden('q', form).map { |n| n['value'] }).to eq(['n0'])
        expect(hidden('page', form).map { |n| n['value'] }).to eq(['2'])
        expect(hidden('state_hash', form).first['value']).not_to eq(posted_hash)
        hrefs = doc.css('span.pagination a[href]').map { |a| a['href'] }
        expect(hrefs).not_to be_empty
        hrefs.each { |href| expect(URI.parse(href).path).to eq(show_path(field)) }
        expect(values_page_scripts.size).to eq(1)
        post_form(form, form.css('input[type="text"]').first['name'] => 'Mine')
        expect(response).to redirect_to(show_path(field, q: 'n0', page: 2))
      end

      # Changed by WP-34 (UD-23): the sort of the global enum_with posts
      # confirm '1'; was no confirm.
      it 'answers 409 to a page form opened before a sort (T-SORT-2 with page mode)' do
        field = enum_with(520)
        get show_path(field, page: 2)
        form = page_form.first
        patch custom_field_configuration_sort_values_path(project, field), params: { direction: 'desc', confirm: '1' }
        before = enum_state(field)
        post_form(form)
        expect(response).to have_http_status(409)
        expect(enum_state(field)).to eq(before)
      end
    end

    describe 'refusals (T-ENP-R2, G5)' do
      it 'answers 403 on a closed project with no write and no row (T-ENP-R2)' do
        closed = dcf_create_project(name: 'Closed', status: :closed)
        field = enum_with(520)
        as(dcf_manager(closed))
        get show_path(field, { page: 2 }, closed)
        expect(response).to have_http_status(200)
        expect(page_form.size).to eq(1)
        target = ordered(field)[25]
        count = events.count
        patch save_path(field, closed),
              params: { batch_scope: 'page', page: '2', state_hash: service.state_hash(field),
                        enumerations: { target.id.to_s => { name: 'N0026', active: '0' } } }
        expect(response).to have_http_status(403)
        expect(response.body).to include(I18n.t(:error_project_archived))
        expect(target.reload.active).to be true
        expect(events.count).to eq(count)
      end

      it 'refuses non-members, members without the permission and anonymous users before any write' do
        field = enum_with(520)
        target = ordered(field)[25]
        params = { batch_scope: 'page', enumerations: { target.id.to_s => { name: 'X', active: '0' } } }
        count = events.count
        [dcf_create_user("stranger-#{SecureRandom.hex(3)}"), dcf_plain_member(project)].each do |user|
          as(user)
          patch save_path(field), params: params
          expect(response).to have_http_status(403)
        end
        as(User.anonymous)
        patch save_path(field), params: params
        expect(response).to have_http_status(302)
        expect(response.location).to match(%r{/login(\?|\z)})
        expect(target.reload).to have_attributes(name: 'N0026', active: true)
        expect(events.count).to eq(count)
      end

      it 'carries an authenticity token and answers 422 without one when forgery protection is on' do
        field = enum_with(520)
        target = ordered(field)[0]
        protection = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        begin
          get show_path(field)
          expect(hidden('authenticity_token', page_form.first).size).to eq(1)
          patch save_path(field), params: { batch_scope: 'page', enumerations: { target.id.to_s => { name: 'X' } } }
        ensure
          ActionController::Base.allow_forgery_protection = protection
        end
        expect(response).to have_http_status(422)
        expect(target.reload).to have_attributes(name: 'N0001', active: true)
      end

      it 'answers 404 for a field outside the project and 422 for a list field in page mode' do
        other = dcf_create_project(name: "Other-#{SecureRandom.hex(3)}")
        foreign = dcf_enum_field(name: "Foreign-#{SecureRandom.hex(3)}", names: %w[SECRET-V], is_for_all: false)
        foreign.projects = [other]
        patch save_path(foreign), params: { batch_scope: 'page', enumerations: { foreign.enumerations.first.id.to_s => { name: 'x' } } }
        expect(response).to have_http_status(404)
        expect(response.body).not_to include('SECRET-V')
        list = dcf_list_field(values: %w[A B], is_for_all: true)
        patch save_path(list), params: { batch_scope: 'page', enumerations: { '1' => { name: 'x' } } }
        expect(response).to have_http_status(422)
        expect(response.body).to include(I18n.t(:error_format_unsupported))
        expect(foreign.enumerations.first.reload.name).to eq('SECRET-V')
      end

      it 'refuses a foreign, a missing and a hidden field id alike, without an oracle (T-ENP-3, SP-20c)' do
        field = enum_with(520)
        visible = dcf_enum_field(name: "Visible-#{SecureRandom.hex(3)}", names: %w[VISIBLE-V])
        hidden_field = dcf_enum_field(name: "HIDDEN-FIELD-#{SecureRandom.hex(3)}", names: %w[SECRET-V])
        hidden_field.update!(visible: false, role_ids: [dcf_create_role.id])
        own = ordered(field)[25]
        ids = [CustomFieldEnumeration.maximum(:id) + 1_000, visible.enumerations.first.id, hidden_field.enumerations.first.id]
        outcomes = ids.map do |id|
          patch save_path(field),
                params: { batch_scope: 'page', page: '2', state_hash: service.state_hash(field),
                          enumerations: { own.id.to_s => { name: 'Renamed', active: '1' },
                                          id.to_s => { name: 'POSTED-JUNK', active: '0' } } }
          expect(response).to have_http_status(422)
          expect(response.body).not_to include('POSTED-JUNK')
          expect(response.body).not_to include('SECRET-V')
          expect(response.body).not_to include(hidden_field.name)
          row = rows(field).last
          [flash_error, row.status, row.error_message, row.changes_summary, row.before_value, row.after_value]
        end
        expect(outcomes.uniq).to eq([[I18n.t(:error_reorder_mismatch), 'validation_failed', 'error_reorder_mismatch',
                                      nil, nil, nil]])
        expect(own.reload.name).to eq('N0026')
        expect(visible.enumerations.first.reload).to have_attributes(name: 'VISIBLE-V', active: true)
        expect(hidden_field.enumerations.first.reload).to have_attributes(name: 'SECRET-V', active: true)
      end

      it 'refuses an empty page and malformed enumerations params with 422 and one row each, never a 500' do
        field = enum_with(520)
        own = ordered(field)[0]
        bodies = ['batch_scope=page',
                  'batch_scope=page&enumerations=x',
                  'batch_scope=page&enumerations[][name]=x',
                  'batch_scope=page&enumerations[name]=X&enumerations[active]=1',
                  "batch_scope=page&enumerations[00#{own.id}][name]=R"]
        bodies.each do |body|
          expect do
            patch save_path(field), params: body, headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
          end.to change { rows(field).where(status: 'validation_failed').count }.by(1)
          expect(response).to have_http_status(422), body
          expect(flash_error).to eq(I18n.t(:error_reorder_mismatch))
        end
        expect(own.reload.name).to eq('N0001')
      end

      # Strong parameters drop a non-numeric key and a non-Hash row next to
      # numeric keys; page mode refuses the body instead of saving the rest.
      it 'refuses a body that mixes valid rows with keys or rows permit drops, applying none (focus-S5)' do
        field = enum_with(520)
        own, other = ordered(field)
        valid = "batch_scope=page&enumerations[#{own.id}][name]=R&enumerations[#{own.id}][active]=1"
        bodies = ["#{valid}&enumerations[x][name]=y",
                  "#{valid}&enumerations[#{other.id}]=junk",
                  "#{valid}&enumerations[#{other.id}abc][name]=N0002",
                  "#{valid}&enumerations[#{other.id}][]=N0002"]
        bodies.each do |body|
          expect do
            patch save_path(field), params: body, headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
          end.to change { rows(field).where(status: 'validation_failed', error_message: 'error_reorder_mismatch').count }.by(1)
          expect(response).to have_http_status(422), body
          expect(flash_error).to eq(I18n.t(:error_reorder_mismatch))
          expect(response.body).not_to include('junk')
          expect(rows(field).last.changes_summary).to be_nil
        end
        expect(ordered(field).first(2).map(&:name)).to eq(%w[N0001 N0002])
        expect(rows(field).where(status: 'success')).to be_empty
        patch save_path(field), params: "#{valid}&enumerations[#{own.id}][foo]=bar",
                                headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
        expect(response).to redirect_to(show_path(field))
        expect(own.reload.name).to eq('R')
      end

      it 'leaves full mode as it was: permit still drops such keys there (T-ACT-21)' do
        field = dcf_enum_field(names: %w[X Y])
        x, y = ordered(field)
        body = "enumerations[#{x.id}][name]=X2&enumerations[#{x.id}][position]=1&enumerations[#{x.id}][active]=1" \
               "&enumerations[#{y.id}][name]=Y&enumerations[#{y.id}][position]=2&enumerations[#{y.id}][active]=1" \
               '&enumerations[x][name]=junk'
        patch save_path(field), params: body, headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
        expect(response).to redirect_to(show_path(field))
        expect(x.reload.name).to eq('X2')
      end

      # WP-32 (WP-30 input 4): full mode refuses an Array enumerations as page
      # mode does; it used to raise TypeError (500, no row).
      it 'refuses an Array enumerations in full mode with 422 and one row, never a 500 (WP-32)' do
        field = dcf_enum_field(names: %w[X Y])
        before = enum_state(field)
        form = { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
        bodies = ['enumerations[][name]=POSTED-JUNK',
                  "state_hash=#{service.state_hash(field)}&enumerations[][name]=POSTED-JUNK&enumerations[][active]=1",
                  'batch_scope=&enumerations[][name]=POSTED-JUNK&enumerations[][position]=1']
        bodies.each do |body|
          expect { patch save_path(field), params: body, headers: form }
            .to change { rows(field).where(status: 'validation_failed', error_message: 'error_reorder_mismatch').count }.by(1)
          expect(response).to have_http_status(422), body
          expect(flash_error).to eq(I18n.t(:error_reorder_mismatch))
          expect(response.body).not_to include('POSTED-JUNK')
          expect(rows(field).last.changes_summary).to be_nil
        end
        patch save_path(field), params: 'state_hash=stale&enumerations[][name]=POSTED-JUNK', headers: form
        expect(response).to have_http_status(409)
        expect(enum_state(field)).to eq(before)
        expect(rows(field).where(status: 'success')).to be_empty
      end

      it 'refuses an unknown or non-scalar batch_scope with 422 instead of running full mode (T-ENP-5)' do
        field = dcf_enum_field(names: %w[X Y Z])
        x, y, z = ordered(field)
        full = { x.id.to_s => { name: 'X', position: '3', active: '1' },
                 y.id.to_s => { name: 'Y', position: '1', active: '1' },
                 z.id.to_s => { name: 'Z', position: '2', active: '1' } }
        before = enum_state(field)
        ['full', 'PAGE', ['page'], { 'x' => 'page' }].each do |scope|
          expect { patch save_path(field), params: { batch_scope: scope, enumerations: full } }
            .to change { rows(field).where(status: 'validation_failed', error_message: 'error_reorder_mismatch').count }.by(1)
          expect(response).to have_http_status(422)
          expect(flash_error).to eq(I18n.t(:error_reorder_mismatch))
          expect(rows(field).last.changes_summary).to be_nil
        end
        expect(enum_state(field)).to eq(before)
        patch save_path(field), params: { batch_scope: '', enumerations: full }
        expect(response).to redirect_to(show_path(field))
        expect(ordered(field).map(&:name)).to eq(%w[Y Z X])
      end

      it 'keeps full mode strict over HTTP: a partial submit without batch_scope is refused (T-ACT-21)' do
        field = dcf_enum_field(names: %w[X Y Z])
        x = ordered(field).first
        patch save_path(field), params: { enumerations: { x.id.to_s => { name: 'R', position: '1', active: '1' } } }
        expect(response).to have_http_status(422)
        expect(flash_error).to eq(I18n.t(:error_reorder_mismatch))
        patch save_path(field), params: { batch_scope: 'page', enumerations: { x.id.to_s => { name: 'R', active: '1' } } }
        expect(response).to redirect_to(show_path(field))
        expect(x.reload.name).to eq('R')
      end
    end

    describe 'parameter budget (T-PARAM-1)' do
      it 'keeps the page-mode form at per_page 500 well below 4,096 parameters and saves it' do
        allow(Setting).to receive(:per_page_options_array).and_return([25, 500])
        field = enum_with(1_200)
        get show_path(field, per_page: 500)
        form = page_form.first
        names = form.css('input[type="text"][name^="enumerations["]')
        expect(names.size).to eq(500)
        controls = form.css('input[name], select[name], textarea[name], button[name]').reject { |n| n['disabled'] }
        expect(controls.size).to be <= (3 * 500) + 8
        expect(controls.size).to be < 4_096
        expect(controls.map { |n| n['name'] }.grep(/\[position\]\z/)).to be_empty
        expect(form['enctype']).to be_nil
        body = URI.encode_www_form(form_pairs(form))
        expect(body.count('&') + 1).to be < 4_096
        target = ordered(field)[499]
        post_form(form, name_key(target) => 'Last on page')
        expect(response).to redirect_to(show_path(field))
        expect(target.reload.name).to eq('Last on page')
        expect(rows(field).last.changes_summary).to eq('Saved 500 of 1200 enumeration value(s) (page): renamed 1')
      end
    end

    # G6: the invariance form, never absolute counts.
    describe 'query counts (G6)' do
      before { allow(Setting).to receive(:per_page_options_array).and_return([25, 100]) }

      def queries(field, params)
        dcf_count_queries { get show_path(field, params) }
      end

      def text_inputs
        page_form.first.css('input[type="text"]').size
      end

      it 'renders the page-mode form with the same statements for 520 and 5,200 values, paginated or filtered' do
        small = enum_with(520)
        large = enum_with(5_200)
        get show_path(small, page: 2)
        base = queries(small, page: 2)
        expect(text_inputs).to eq(25)
        expect(queries(large, page: 2)).to eq(base)
        expect(text_inputs).to eq(25)
        filtered = queries(small, q: 'N01', page: 2)
        expect(text_inputs).to eq(25)
        expect(queries(large, q: 'N01', page: 2)).to eq(filtered)
        expect(text_inputs).to eq(25)
      end

      it 'renders the page-mode form with the same statements for 25 and 100 rows on one page' do
        field = enum_with(520)
        get show_path(field, page: 2)
        c25 = queries(field, per_page: 25, page: 2)
        expect(text_inputs).to eq(25)
        c100 = queries(field, per_page: 100, page: 2)
        expect(text_inputs).to eq(100)
        expect(c100).to eq(c25)
      end
    end

    describe 'hidden children (security)' do
      it 'never names a role-invisible child or shows its values in page mode' do
        parent = enum_with(520)
        p1, p2 = ordered(parent)
        child = dcf_enum_field(format: 'depending_enumeration', name: "HIDDEN-CHILD-#{SecureRandom.hex(3)}",
                               names: %w[SECRET-V], parent: parent)
        secret = child.enumerations.first
        dcf_set_dependencies(child, value_dependencies: { p1.id.to_s => [secret.id.to_s], p2.id.to_s => [secret.id.to_s] })
        child.update!(visible: false, role_ids: [dcf_create_role.id])
        store = CustomField.where(id: child.id).pluck(Arel.sql('format_store')).first
        check = lambda do
          expect(response.body).not_to include(child.name)
          expect(response.body).not_to include('SECRET-V')
          expect(flash.to_hash.values.join(' ')).not_to include('HIDDEN-CHILD')
        end
        get show_path(parent)
        check.call
        post_form(page_form.first, {}, [p1])
        expect(response).to redirect_to(show_path(parent))
        check.call
        follow_redirect!
        check.call
        post_form(page_form.first, name_key(p2) => 'N0003')
        expect(response).to have_http_status(422)
        check.call
        post_form(page_form.first, 'state_hash' => 'stale')
        expect(response).to have_http_status(409)
        check.call
        expect(p1.reload.active).to be false
        expect(CustomField.where(id: child.id).pluck(Arel.sql('format_store')).first).to eq(store)
        rows(parent).each do |row|
          expect(row.affected_child_field_ids).to be_nil
          expect([row.changes_summary, row.error_message, row.before_value, row.after_value].join(' '))
            .not_to match(/HIDDEN-CHILD|SECRET-V/)
        end
      end
    end
  end

  # --- WP-31: project storage ceiling and value length cap (UD-22) ---------
  # Project design 2.4, 9 and 15, limits design 4.11, quality G12 (gap 12)
  # and gap 14. The ceiling is stubbed through
  # ProjectStoragePolicy.ceiling_bytes; stubbed ceilings are far below MySQL
  # TEXT, so the examples behave the same on PostgreSQL and MariaDB.
  describe 'project storage ceiling and value length cap (WP-31)' do
    let(:policy) { RedmineDependingCustomFields::ProjectStoragePolicy }
    let(:limits) { RedmineDependingCustomFields::StorageLimits }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
    let(:manager) { dcf_manager(project) }
    let(:multipart) { { 'CONTENT_TYPE' => 'multipart/form-data' } }

    def doc
      Nokogiri::HTML(response.body)
    end

    def flash_box
      doc.at_css('#flash_error')
    end

    def raw(field, column)
      CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
    end

    def stub_ceiling(bytes)
      allow(policy).to receive(:ceiling_bytes).and_return(bytes)
    end

    def yaml_bytes(values)
      limits.serialized_bytesize(CustomField, 'possible_values', values)
    end

    def own_list(values)
      dcf_list_field(values: values, is_for_all: false, projects: [project])
    end

    def rows(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def show_path(field, params = {})
      custom_field_configuration_field_path(project, field, params)
    end

    def editor_root
      doc.at_css('fieldset[data-dcf-editor]')
    end

    def state_hash(field)
      RedmineDependingCustomFields::BaseService.state_hash(CustomField.find(field.id))
    end

    # Changed by WP-34 (UD-23): an explicit confirm, passed by each caller;
    # was no confirm.
    def save_mapping(field, mapping, confirm: nil)
      params = { dependencies_json: JSON.generate(mapping), state_hash: state_hash(field) }
      params[:confirm] = confirm if confirm
      patch custom_field_configuration_update_dependencies_path(project, field), params: params, headers: multipart
    end

    describe 'storage ceiling on project pages (T-SIZE-R2)' do
      before { as(manager) }

      it 'refuses an add_value over the ceiling with an audited 422 and writes nothing' do
        field = own_list(%w[A B])
        ceiling = yaml_bytes(%w[A B])
        stub_ceiling(ceiling)

        expect do
          post custom_field_configuration_add_value_path(project, field), params: { value: 'SECRET_C1' }
        end.to change(events, :count).by(1)

        expect(response).to have_http_status(422)
        bytes = yaml_bytes(%w[A B SECRET_C1])
        expect(flash_box.text.strip).to eq(I18n.t(:error_dcf_values_too_large, field: field.name,
                                                                               size: limits.delimited(bytes),
                                                                               limit: limits.delimited(ceiling)))
        row = rows(field).last
        expect([row.action, row.status, row.error_message])
          .to eq(%w[validation_failed validation_failed error_dcf_values_too_large])
        expect(row.changes_summary).to eq("possible_values: #{bytes} bytes exceeds #{ceiling} (custom field ##{field.id})")
        expect(response.body).not_to include('SECRET_C1')
        expect(response.body).not_to include(I18n.t('activerecord.errors.messages.dcf_storage_too_large',
                                                    size: limits.delimited(bytes), limit: limits.delimited(ceiling)))
        expect(field.reload.possible_values).to eq(%w[A B])
      end

      it 'removes a value from a field stored above the ceiling (302, success row)' do
        field = own_list(%w[Alpha Bravo Charlie])
        stub_ceiling(10)

        delete custom_field_configuration_remove_value_path(project, field), params: { value: 'Bravo', confirm: '1' }

        expect(response).to have_http_status(302)
        expect(field.reload.possible_values).to eq(%w[Alpha Charlie])
        expect([rows(field).last.action, rows(field).last.status]).to eq(%w[remove_value success])
      end

      it 'escapes the field name once in the ceiling flash' do
        markup = '<img src=x onerror=alert(1)>'
        field = dcf_list_field(name: markup, values: %w[A B], is_for_all: false, projects: [project])
        stub_ceiling(1)

        post custom_field_configuration_add_value_path(project, field), params: { value: 'C' }

        expect(response).to have_http_status(422)
        expect(flash_box.css('img')).to be_empty
        expect(flash_box.inner_html).to include(ERB::Util.html_escape(markup))
        expect(response.body).not_to include(markup)
        expect(response.body).not_to include('&amp;lt;')
      end

      it 'ignores a ceiling posted with the request' do
        field = own_list(%w[A B])
        stub_ceiling(1)
        post custom_field_configuration_add_value_path(project, field),
             params: { value: 'C', dcf_storage_ceiling: (10**12).to_s, project_storage_ceiling_kib: '999999',
                       custom_field: { dcf_storage_ceiling: (10**12).to_s } }
        expect(response).to have_http_status(422)
        expect(rows(field).last.error_message).to eq('error_dcf_values_too_large')
        expect(field.reload.possible_values).to eq(%w[A B])
      end

      # Changed by WP-34 (UD-23): confirm '1' on both saves of the global
      # child (the ceiling is checked only on a confirmed save); was no confirm.
      it 'refuses the JSON dependency save over the ceiling, re-renders it dirty and saves the corrected resubmit ' \
         '(T-DEPJ-14 with the ceiling)' do
        parent = dcf_list_field(name: "Country-#{SecureRandom.hex(3)}", values: %w[Belgium France])
        child = dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}",
                               values: %w[Antwerp Paris], parent: parent)
        dcf_set_dependencies(child, value_dependencies: { 'Belgium' => %w[Antwerp] })
        stored = raw(child, 'format_store').bytesize
        stub_ceiling(stored)
        grown = { 'Belgium' => %w[Antwerp Paris], 'France' => %w[Antwerp Paris] }

        save_mapping(child, { 'value_dependencies' => grown, 'default_value_dependencies' => {} }, confirm: '1')

        expect(response).to have_http_status(422)
        expect(flash_box.text.strip).to include(child.name)
        expect(flash_box.text.strip).to include(limits.delimited(stored))
        expect(rows(child).last.error_message).to eq('error_dcf_mapping_too_large')
        expect(editor_root['data-dcf-editor-dirty']).to eq('1')
        expect(JSON.parse(editor_root['data-dcf-editor-mapping'])['value_dependencies']).to eq(grown)
        expect(doc.css('input[name="dependencies_json"]').map { |input| input['value'] }).to eq([''])
        expect(editor_root['data-dcf-editor-storage-limit']).to eq(stored.to_s)
        rendered = doc.at_css('input[name="state_hash"]')['value']
        expect(rendered).to eq(state_hash(child))

        patch custom_field_configuration_update_dependencies_path(project, child),
              params: { dependencies_json: JSON.generate('value_dependencies' => { 'France' => %w[Paris] },
                                                         'default_value_dependencies' => {}),
                        state_hash: rendered, confirm: '1' }, headers: multipart

        expect(response).to have_http_status(302)
        expect(CustomField.find(child.id).value_dependencies).to eq('France' => %w[Paris])
      end

      # Review round 2 (contracts-r2-1): the editor always posts the
      # per-parent defaults; an empty set over a mapping stored without them
      # changes nothing.
      # Changed by WP-34 (UD-23): confirm '1' (global child); was no confirm.
      it 'saves the unchanged mapping of a child stored above the ceiling without its per-parent defaults (302)' do
        parent = dcf_list_field(name: "Country-#{SecureRandom.hex(3)}", values: %w[Belgium France])
        child = dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}",
                               values: %w[Antwerp Paris], parent: parent)
        mapping = { 'Belgium' => %w[Antwerp], 'France' => %w[Paris] }
        dcf_set_dependencies(child, value_dependencies: mapping)
        stale = CustomField.find(child.id).format_store.to_hash.except('default_value_dependencies')
        child.update_column(:format_store, stale)
        expect(raw(child, 'format_store')).not_to include('default_value_dependencies')
        stub_ceiling(1)

        save_mapping(child, { 'value_dependencies' => mapping, 'default_value_dependencies' => {} }, confirm: '1')

        expect(response).to have_http_status(302)
        expect([rows(child).last.action, rows(child).last.status]).to eq(%w[update_dependencies success])
        expect(CustomField.find(child.id).value_dependencies).to eq(mapping)
      end
    end

    describe 'a role-invisible child refused by the ceiling (security)' do
      it 'is never named in the flash, the page, its attributes or the audit rows' do
        parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B])
        child = dcf_list_field(format: 'depending_list', name: 'CEILING-HIDDEN-CHILD', values: %w[SECRET-CV],
                               parent: parent)
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[SECRET-CV] })
        child.update!(visible: false, role_ids: [dcf_create_role.id])
        stub_ceiling(raw(child, 'format_store').bytesize)
        as(manager)

        patch custom_field_configuration_rename_value_path(project, parent),
              params: { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }

        expect(response).to have_http_status(422)
        expect(flash_box.text.strip).to eq(I18n.t(:error_save_failed))
        ['CEILING-HIDDEN-CHILD', 'SECRET-CV'].each do |secret|
          expect(response.body).not_to include(secret)
          expect(doc.xpath('//@*').map(&:value).join(' ')).not_to include(secret)
          expect(events.all.map { |row| row.attributes.values.join(' ') }.join(' ')).not_to include(secret)
        end
        row = rows(parent).last
        expect([row.status, row.error_message]).to eq(%w[validation_failed error_dcf_mapping_too_large])
        expect(row.changes_summary).to include("custom field ##{child.id}")
        expect(parent.reload.possible_values).to eq(%w[A B])
      end
    end

    describe 'value length cap (T-LEN-1)' do
      before { as(manager) }

      it 'refuses a 256-character add with an audited 422 that echoes neither the value nor a field name' do
        field = own_list(%w[A])
        value = "LONGVALUE#{'z' * 247}"
        expect(value.length).to eq(256)

        expect { post custom_field_configuration_add_value_path(project, field), params: { value: value } }
          .to change(events, :count).by(1)

        expect(response).to have_http_status(422)
        expect(flash_box.text.strip).to eq(I18n.t(:error_dcf_value_length, max: 255))
        expect(flash_box.text).not_to include(field.name)
        expect(response.body).not_to include('LONGVALUE')
        row = rows(field).last
        expect([row.status, row.error_message]).to eq(%w[validation_failed error_dcf_value_length])
        expect(row.attributes.values.join(' ')).not_to include('LONGVALUE')
        expect(response.body).not_to match(/translation[ _]missing/i)
        expect(field.reload.possible_values).to eq(%w[A])
      end

      it 'shows the German text' do
        field = own_list(%w[A])
        manager.update_column(:language, 'de')
        I18n.with_locale(I18n.locale) do
          post custom_field_configuration_add_value_path(project, field), params: { value: 'z' * 256 }
        end
        expect(response).to have_http_status(422)
        expect(flash_box.text.strip).to eq('Ein Wert darf höchstens 255 Zeichen lang sein.')
      end

      it 'refuses a 256-character rename of a shared value without the confirmation panel' do
        field = dcf_list_field(values: %w[A B], is_for_all: true)
        value = dcf_custom_value(field, 'A')

        patch custom_field_configuration_rename_value_path(project, field),
              params: { old_value: 'A', new_value: "RENAMED#{'r' * 249}" }

        expect(response).to have_http_status(422)
        expect(flash_box.text.strip).to eq(I18n.t(:error_dcf_value_length, max: 255))
        expect(doc.at_css('.dcf-confirm-panel')).to be_nil
        expect(response.body).not_to include('RENAMED')
        expect(rows(field).last.error_message).to eq('error_dcf_value_length')
        expect(value.reload.value).to eq('A')
      end

      it 'jumps to the page of a 255-character value added with surrounding spaces' do
        labels = (1..520).map { |i| format('Value %04d', i) }
        field = own_list(labels)
        added = "Z#{'z' * 254}"
        post custom_field_configuration_add_value_path(project, field), params: { value: "  #{added}  " }
        expect(response).to redirect_to(show_path(field, page: 21))
        expect(field.reload.possible_values.last).to eq(added)
      end
    end

    describe 'project editor storage attributes (gap 14)' do
      before { as(manager) }

      let(:parent) { dcf_list_field(name: "Country-#{SecureRandom.hex(3)}", values: %w[Belgium France]) }
      let(:child) do
        field = dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}",
                               values: %w[Antwerp Paris], parent: parent)
        dcf_set_dependencies(field, value_dependencies: { 'Belgium' => %w[Antwerp] })
      end

      it 'renders the effective limit, the base and the warn percent, never a values limit' do
        get custom_field_configuration_field_dependencies_path(project, child)

        expect(response).to have_http_status(200)
        record = CustomField.find(child.id)
        expect(editor_root['data-dcf-editor-storage-limit']).to eq(policy.format_store_limit(record).to_s)
        expect(editor_root['data-dcf-editor-storage-base']).to eq(limits.base_bytes(record).to_s)
        expect(editor_root['data-dcf-editor-storage-warn']).to eq('90')
        expect(editor_root['data-dcf-editor-values-limit']).to be_nil
      end

      it 'renders the default ceiling on PostgreSQL and SQLite and the stored size of a field above a ceiling' do
        allow(limits).to receive(:column_limit).and_return(nil)
        get custom_field_configuration_field_dependencies_path(project, child)
        expect(editor_root['data-dcf-editor-storage-limit']).to eq('2097152')

        stub_ceiling(10)
        get custom_field_configuration_field_dependencies_path(project, child)
        expect(editor_root['data-dcf-editor-storage-limit']).to eq(raw(child, 'format_store').bytesize.to_s)
      end
    end

    # Nothing outside save_field! and format_store_limit sets the ceiling.
    describe 'administration, APIs and issue import' do
      before do
        as(dcf_admin)
        stub_ceiling(1)
        allow(limits).to receive(:column_limit).and_return(nil)
      end

      it 'saves a growing list and a growing mapping from the admin form' do
        field = dcf_list_field(values: %w[A B])
        values = (1..100).map { |i| "Value #{i}" }
        patch custom_field_path(field), params: { custom_field: { possible_values: values.join("\n"),
                                                                  dcf_storage_ceiling: '1' } }
        expect(response).to have_http_status(302)
        expect(CustomField.find(field.id).possible_values).to eq(values)

        parent = dcf_list_field(values: %w[P Q])
        child = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
        json = JSON.generate('version' => 1, 'source' => 'import', 'import' => { 'mode' => 'merge', 'rows' => 4 },
                             'value_dependencies' => { 'P' => %w[a b], 'Q' => %w[a b] },
                             'default_value_dependencies' => {})
        patch custom_field_path(child), params: { custom_field: { dependencies_json: json } }
        expect(response).to have_http_status(302)
        expect(CustomField.find(child.id).value_dependencies).to eq('P' => %w[a b], 'Q' => %w[a b])
        expect(policy).not_to have_received(:ceiling_bytes)
      end

      it 'saves a growing list through the plugin JSON API' do
        field = dcf_list_field(values: %w[A B])
        values = (1..100).map { |i| "Value #{i}" }
        put "/depending_custom_fields/#{field.id}.json",
            params: { custom_field: { possible_values: values, dcf_storage_ceiling: '1' } }
        expect(response.status).to be_between(200, 204)
        expect(CustomField.find(field.id).possible_values).to eq(values)

        post '/depending_custom_fields.json',
             params: { custom_field: { name: "API-#{SecureRandom.hex(3)}", type: 'IssueCustomField', field_format: 'list',
                                       possible_values: values } }
        expect(response).to have_http_status(201)
        expect(policy).not_to have_received(:ceiling_bytes)
      end

      it 'imports an issue with depending values without touching the ceiling' do
        parent = dcf_list_field(values: %w[A B])
        child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
        dcf_set_dependencies(child, value_dependencies: { 'B' => %w[b1] })
        tracker, _status, priority = dcf_issue_infra(project)
        [parent, child].each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
        import = IssueImport.new(user: dcf_admin)
        import.settings = { 'mapping' => { 'project_id' => project.id.to_s, 'tracker' => "value:#{tracker.id}",
                                           'subject' => '0', "cf_#{parent.id}" => '1', "cf_#{child.id}" => '2' } }
        issue = import.send(:build_object, %w[Imported B b1], 1)
        issue.priority ||= priority
        expect(issue.save).to be(true), issue.errors.full_messages.inspect
        expect(issue.custom_field_value(child)).to eq('b1')
        expect(policy).not_to have_received(:ceiling_bytes)
      end
    end

    # Quality G12 (gap 12) and FM-26. Core stores the posted settings Hash as
    # is (permit!.to_h) and caches it beyond the transaction.
    describe 'plugin settings page' do
      # Redmine 7.0 enables sudo mode by default; the page is the subject.
      before { allow(Redmine::SudoMode).to receive(:enabled?).and_return(false) }
      after { Setting.clear_cache }

      let(:path) { plugin_settings_path('redmine_depending_custom_fields') }

      def ceiling_input
        doc.at_css('input[name="settings[project_storage_ceiling_kib]"]')
      end

      def post_settings(kib)
        post path, params: { settings: { manage_standard_custom_fields: '1', block_removal_when_used: '0',
                                         project_storage_ceiling_kib: kib } }
      end

      { 'en' => 'Maximum stored size for changes made in project settings (KiB)',
        'de' => 'Maximale Speichergröße für Änderungen in den Projekteinstellungen (KiB)' }.each do |language, label|
        it "renders the ceiling field with its label and info text in #{language}" do
          admin = dcf_admin
          admin.update_column(:language, language)
          as(admin)
          I18n.with_locale(I18n.locale) { get path }

          expect(response).to have_http_status(200)
          expect(response.body).not_to match(/translation[ _]missing/i)
          input = ceiling_input
          expect([input['type'], input['min'], input['max'], input['step'], input['value']])
            .to eq(%w[number 64 1048576 1 2048])
          expect(doc.at_css("label[for=\"#{input['id']}\"]").text.strip).to eq(label)
          kib = I18n.with_locale(language) { ActiveSupport::NumberHelper.number_to_delimited(2048) }
          info = I18n.t(:text_dcf_project_storage_ceiling_info, kib: kib, locale: language)
          expect(input.parent.at_css('em.info').text.strip).to eq(info)
          expect(info).to include(kib)
          expect(doc.css('input[name="settings[manage_standard_custom_fields]"]').size).to eq(2)
          expect(doc.css('input[name="settings[block_removal_when_used]"]').size).to eq(2)
        end
      end

      it 'stores a non-numeric value as posted and falls back to 2,048 KiB' do
        as(dcf_admin)
        post_settings('abc')
        expect(response).to have_http_status(302)
        Setting.clear_cache
        stored = Setting.plugin_redmine_depending_custom_fields
        expect(stored['project_storage_ceiling_kib']).to eq('abc')
        expect(stored['block_removal_when_used']).to eq('0')
        expect(policy.ceiling_bytes).to eq(2_097_152)
        get path
        expect(ceiling_input['value']).to eq('2048')
      end

      it 'raises a value below the minimum to 64 KiB and shows the value that applies' do
        as(dcf_admin)
        post_settings('32')
        Setting.clear_cache
        expect(policy.ceiling_bytes).to eq(65_536)
        get path
        expect(ceiling_input['value']).to eq('64')
        post_settings('4096')
        Setting.clear_cache
        expect(policy.ceiling_bytes).to eq(4_194_304)
        get path
        expect(ceiling_input['value']).to eq('4096')
      end

      # The editor parses data-dcf-editor-storage-limit as at most 16 digits.
      it 'clamps a value above the maximum to 1,048,576 KiB and keeps the project editor limit parseable' do
        as(dcf_admin)
        post_settings('9' * 30)
        Setting.clear_cache
        expect(policy.ceiling_bytes).to eq(1_073_741_824)
        get path
        expect(ceiling_input['value']).to eq('1048576')

        allow(limits).to receive(:column_limit).and_return(nil)
        parent = dcf_list_field(name: "Country-#{SecureRandom.hex(3)}", values: %w[Belgium France])
        child = dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}",
                               values: %w[Antwerp Paris], parent: parent)
        dcf_set_dependencies(child, value_dependencies: { 'Belgium' => %w[Antwerp] })
        as(manager)
        get custom_field_configuration_field_dependencies_path(project, child)
        expect(response).to have_http_status(200)
        expect(editor_root['data-dcf-editor-storage-limit']).to eq('1073741824')
        expect(editor_root['data-dcf-editor-storage-limit']).to match(/\A(0|[1-9][0-9]{0,15})\z/)
      end

      it 'never renders a stored markup value' do
        as(dcf_admin)
        post_settings('"><script>alert(1)</script>')
        Setting.clear_cache
        get path
        expect(response.body).not_to include('<script>alert(1)</script>')
        expect(ceiling_input['value']).to eq('2048')
      end

      it 'is for administrators only: a project manager gets 403 and changes nothing' do
        as(dcf_admin)
        post_settings('128')
        Setting.clear_cache
        as(manager)
        get path
        expect(response).to have_http_status(403)
        post_settings('64')
        expect(response).to have_http_status(403)
        Setting.clear_cache
        expect(Setting.plugin_redmine_depending_custom_fields['project_storage_ceiling_kib']).to eq('128')
      end
    end

    describe 'texts (large_lists_i18n_registry.md)' do
      registry = {
        en: ['A value can have at most 255 characters.',
             'Maximum stored size for changes made in project settings (KiB)',
             'Applies when the values or the dependency mapping of a custom field are changed from a project\'s ' \
             'settings. The custom field administration and the API are not limited by this setting. Default: 2,048 KiB.'],
        de: ['Ein Wert darf höchstens 255 Zeichen lang sein.',
             'Maximale Speichergröße für Änderungen in den Projekteinstellungen (KiB)',
             'Gilt, wenn die Werte oder die Abhängigkeitszuordnung eines benutzerdefinierten Feldes in den ' \
             'Einstellungen eines Projekts geändert werden. Die Verwaltung der benutzerdefinierten Felder und die API ' \
             'sind durch diese Einstellung nicht eingeschränkt. Standard: 2,048 KiB.'],
        fr: ['Une valeur peut comporter au maximum 255 caractères.',
             'Taille maximale enregistrée pour les modifications faites dans les paramètres du projet (Kio)',
             'S\'applique lorsque les valeurs ou le mappage des dépendances d\'un champ personnalisé sont modifiés ' \
             'depuis les paramètres d\'un projet. L\'administration des champs personnalisés et l\'API ne sont pas ' \
             'limitées par ce paramètre. Par défaut : 2,048 Kio.'],
        nl: ['Een waarde mag maximaal 255 tekens bevatten.',
             'Maximale opgeslagen grootte voor wijzigingen in de projectinstellingen (KiB)',
             'Geldt wanneer de waarden of de afhankelijkheidskoppeling van een aangepast veld vanuit de instellingen ' \
             'van een project worden gewijzigd. Het beheer van aangepaste velden en de API worden door deze instelling ' \
             'niet beperkt. Standaard: 2,048 KiB.']
      }

      registry.each do |locale, (length, label, info)|
        it "matches the registry in #{locale}" do
          expect(I18n.t(:error_dcf_value_length, max: 255, locale: locale)).to eq(length)
          expect(I18n.t(:label_dcf_project_storage_ceiling, locale: locale)).to eq(label)
          expect(I18n.t(:text_dcf_project_storage_ceiling_info, kib: '2,048', locale: locale)).to eq(info)
        end
      end
    end
  end

  # --- Exact value matching on MySQL and MariaDB (SD-17, WP-33) ----------
  # The service examples run untagged on every database; this one goes
  # through the project page where the collation used to merge values.
  describe 'list value rename on MySQL and MariaDB (SD-17, WP-33)', :mysql do
    let(:manager) { dcf_manager(project) }
    let(:other) { dcf_create_project(name: "Other-#{SecureRandom.hex(3)}") }
    let(:near) { ['a', "\u00c1", 'A '] }

    before { as(manager) }

    def doc
      Nokogiri::HTML(response.body)
    end

    def stored(field)
      CustomValue.where(custom_field_id: field.id).order(:id).pluck(:value)
    end

    def panel_counts
      [I18n.t(:label_usage_this_project), I18n.t(:label_usage_other_projects)].map do |label|
        doc.css('.dcf-confirm-panel li').map { |li| li.text.squish }.find { |text| text.start_with?("#{label}:") }
      end
    end

    it 'shows the exact counts in the panel and on the values page and rewrites only those rows' do
      field = dcf_list_field(values: ['A', 'a', "\u00c1", 'B'], is_for_all: true)
      2.times { dcf_issue_with_value(project, field, 'A') }
      dcf_issue_with_value(other, field, 'A')
      near.each { |value| [project, other].each { |where| dcf_issue_with_value(where, field, value) } }
      before = stored(field)

      get custom_field_configuration_field_path(project, field, show_usage: 1)
      row = doc.at_css('table.dcf-values tr[data-dcf-value="A"]')
      expect(row.css('td').map { |td| td.text.strip }[1, 2]).to eq(%w[2 1])

      patch custom_field_configuration_rename_value_path(project, field), params: { old_value: 'A', new_value: 'C' }
      expect(response).to have_http_status(422)
      expect(panel_counts).to eq(["#{I18n.t(:label_usage_this_project)}: 2", "#{I18n.t(:label_usage_other_projects)}: 1"])
      expect(response.body).not_to include('CAST(')
      expect(response.body).not_to include('SELECT')
      expect(stored(field)).to eq(before)

      patch custom_field_configuration_rename_value_path(project, field),
            params: { old_value: 'A', new_value: 'C', confirm: '1' }
      expect(response).to have_http_status(:redirect)
      expect(stored(field)).to eq(before.map { |value| value == 'A' ? 'C' : value })
      event = RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: field.id).order(:id).last
      expect([event.status, event.changes_summary, event.affected_values_count]).to eq(['success', "Renamed 'A' to 'C'", 3])
      expect(flash[:notice]).to eq(I18n.t(:notice_value_renamed))
      expect(field.reload.possible_values).to eq(['C', 'a', "\u00c1", 'B'])
    end

    it 'renames a project-only value without a panel when only a value differing in case is used elsewhere' do
      field = dcf_list_field(values: %w[A a], is_for_all: false, projects: [project])
      dcf_issue_with_value(project, field, 'A')
      dcf_issue_with_value(other, field, 'a')
      patch custom_field_configuration_rename_value_path(project, field), params: { old_value: 'A', new_value: 'C' }
      expect(response).to redirect_to(custom_field_configuration_field_path(project, field))
      expect(stored(field)).to eq(%w[C a])
    end
  end
end
