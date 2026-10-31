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
    # editor root, its assets once each from the head hook.
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
      expect(response.body).not_to include('dcf_config')
    end

    # Renamed by WP-27 (was: 'saves a dependency mapping and redirects').
    it 'saves a dependency mapping and redirects (legacy nested params, deprecated)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: true)
      as(dcf_manager(project))
      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => ['c1'] } }
      expect(response).to have_http_status(:redirect)
      expect(child.reload.value_dependencies).to eq('A' => ['c1'])
    end

    # Renamed by WP-27 (was: '... submitted as an array (T-UI-7)').
    it 'saves multiple per-parent defaults submitted as an array (T-UI-7, legacy nested params, deprecated)' do
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
      added = 'C' * 1_500

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

    it 'escapes the field name once in the dependency page flash (T-SIZE-2)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: markup, values: %w[c1], parent: parent, is_for_all: true)
      stub_limit_at_stored('format_store', child)
      as(dcf_manager(project))

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'A' => ['c1'] } }

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
            error = RedmineDependingCustomFields::OperationError.new(
              key.to_sym, interpolations: { field: 'F', size: '1', limit: '2' }
            )
            out = translate(error)
            expect(out).to be_a(String)
            expect(out).not_to include('translation missing')
            expect(out).not_to eq(key)
          end
        end
      end
    end

    it 'sends every flash and error page message through translate_error (S4)' do
      source = File.read(File.expand_path('../../app/controllers/project_custom_field_configuration_controller.rb',
                                          __dir__))
      flash_lines = source.lines.grep(/flash(\.now)?\[/)
      expect(flash_lines.size).to be >= 5
      flash_lines.each { |line| expect(line).to match(/=\s*translate_error\(/) }
      source.lines.grep(/render_error\(/).each { |line| expect(line).to match(/message: translate_error\(/) }
      expect(source).not_to match(/translate_error\(e\.key/)
      expect(source.scan(/\bl\(/).size).to eq(1)
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
        expect(names - %w[_method authenticity_token utf8 state_hash dependencies_json]).to eq([])
        expect(names.size).to be <= 5
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
      it 'saves, redirects with the notice and writes one success row with the v2 delta (T-DEPJ-1)' do
        child
        allow(payload).to receive(:parse).and_call_original

        expect { save(child, json({ 'Germany' => %w[Lyon] }, { 'Germany' => 'Lyon' })) }
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

      it 'saves for an administrator on an active project with one success row (G5 admin row)' do
        child
        admin = dcf_admin
        as(admin)

        expect { save(child, json({ 'Germany' => %w[Lyon] })) }.to change { rows(child).count }.by(1)

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        row = rows(child).last
        expect([row.action, row.status, row.acting_user_id]).to eq(['update_dependencies', 'success', admin.id])
        expect(JSON.parse(row.after_value)['source']).to eq('editor')
      end

      it 'chains mapping_sha256 over consecutive saves and audits a no-op save' do
        child
        save(child, json({ 'Germany' => %w[Lyon] }))
        save(child, json({ 'Germany' => %w[Lyon] }))

        first, second = rows(child).last(2).map { |row| [JSON.parse(row.before_value), JSON.parse(row.after_value)] }
        expect(second[0]['mapping_sha256']).to eq(first[1]['mapping_sha256'])
        expect(second[1].values_at('added', 'removed')).to eq([0, 0])
        expect(rows(child).last.status).to eq('success')
      end

      it 'round-trips parent and child values with brackets (T-DEPJ-2)' do
        brackets = dcf_list_field(name: "Br-#{SecureRandom.hex(3)}", values: ['Foo [x]', '[b', 'a]'])
        field = dcf_list_field(format: 'depending_list', name: "Brc-#{SecureRandom.hex(3)}", values: ['[x]', 'y]'],
                               parent: brackets)
        mapping = { 'Foo [x]' => ['[x]'], '[b' => ['y]'], 'a]' => ['[x]', 'y]'] }

        save(field, json(mapping, { 'a]' => 'y]' }))

        expect(response).to redirect_to(page_path(field))
        expect(stored(field)).to eq([mapping, { 'a]' => 'y]' }])
      end

      it 'clears both stores with {} (T-DEPJ-3)' do
        save(child, '{}')

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{}, {}])
        after = JSON.parse(rows(child).last.after_value)
        expect(after.values_at('links', 'defaults', 'removed', 'defaults_changed')).to eq([0, 0, 3, 1])
      end

      it 'saves 4,200 links in one parameter (T-DEPJ-4, UN-28)' do
        big_parent = dcf_list_field(name: "BigP-#{SecureRandom.hex(3)}", values: (1..42).map { |i| "P#{i}" })
        big = dcf_list_field(format: 'depending_list', name: "BigC-#{SecureRandom.hex(3)}",
                             values: (1..100).map { |i| "C#{i}" }, parent: big_parent)
        mapping = big_parent.possible_values.to_h { |key| [key, big.possible_values] }

        save(big, json(mapping))

        expect(response).to redirect_to(page_path(big))
        expect(request.request_parameters.keys.size).to be <= 5
        expect(stored(big)[0]).to eq(mapping)
        after = JSON.parse(rows(big).last.after_value)
        expect(after.values_at('links', 'added', 'truncated')).to eq([4_200, 4_200, true])
        expect(after['sample']['added'].size).to eq(20)
        expect(rows(big).last.after_value.bytesize).to be <= 12_100
      end

      it 'records an import payload with source import, mode and rows (T-DEPJ-13)' do
        meta = { 'mode' => 'replace', 'rows' => 2 }
        save(child, json({ 'Germany' => %w[Lyon], 'France' => %w[Lyon] }, {}, 'source' => 'import', 'import' => meta))

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

      it 'refuses 1,000,000-digit and 20-digit integers before JSON.parse, each in under 1 s (T-DEPJ-20, SP-01)' do
        child
        # untimed warm-up: the first render of the process loads the locales,
        # the layout and the editor partial
        save(child, '{"value_dependencies":{"Belgium":[12345678901234567890]}}')
        expect(response).to have_http_status(422)
        allow(JSON).to receive(:parse).and_call_original
        ['9' * 1_000_000, '-12345678901234567890', '12345678901234567890'].each do |number|
          raw = %({"value_dependencies":{"Belgium":[#{number}]}})
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          save(child, raw)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

          expect(response).to have_http_status(422)
          expect(rows(child).last.changes_summary)
            .to eq("dependencies_json rejected: number_too_long (#{raw.bytesize} bytes)")
          puts format('DCF PERF project PATCH with a %d-digit integer: %.0f ms', number.delete('-').size, elapsed * 1000)
          expect(elapsed).to be < 1.0
        end
        expect(JSON).not_to have_received(:parse).with(a_string_including('Belgium'), any_args)
        expect(stored(child)).to eq(original)
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
        expect(data_names(root).grep(/echo|pending|conflict|base/)).to eq([])
        expect(response.body).not_to include('<img src=x')
        expect(stored(child)).to eq(original)
        expect(rendered_state_hash).to eq(state_hash(child))

        get custom_field_configuration_audit_path(project)
        expect(response.body).to include('&lt;img src=x onerror=alert(1)&gt;MARK')
        expect(response.body).not_to include('<img src=x')
      end

      it 'prefers dependencies_json over nested params of the same request, without a deprecation line (T-DEPJ-7)' do
        child
        allow(Rails.logger).to receive(:warn).and_call_original

        save(child, json({ 'Germany' => %w[Lyon] }), extra: { value_dependencies: { 'Belgium' => %w[Paris] } })

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        expect(Rails.logger).not_to have_received(:warn).with(/deprecated/)
      end

      it 'reloads the field after a storage 422; the corrected resubmit with the rendered state hash saves ' \
         '(T-DEPJ-14, R9, PC-58)' do
        child
        stub_limit_at_stored(child)
        allow(payload).to receive(:parse).and_call_original
        grown = { 'Belgium' => %w[Antwerp Brussels Paris Lyon], 'France' => %w[Paris Lyon], 'Germany' => %w[Lyon] }

        save(child, json(grown))

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

        save(child, json({ 'Germany' => %w[Lyon] }), state: fresh)

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        expect(rows(child).last.status).to eq('success')
      end

      it 'escapes the field name once in the storage 422 flash on the JSON path (T-DEPJ-22, SP-06)' do
        markup = '<img src=x onerror=alert(1)>'
        field = dcf_list_field(format: 'depending_list', name: markup, values: %w[c1 c2], parent: parent)
        stub_limit_at_stored(field)

        save(field, json({ 'Belgium' => %w[c1 c2], 'France' => %w[c1 c2] }))

        expect(response).to have_http_status(422)
        box = doc.at_css('#flash_error')
        expect(box.css('img')).to be_empty
        expect(box.inner_html).to include(ERB::Util.html_escape(markup))
        expect(box.text).to include(markup)
        expect(response.body).not_to include(markup)
        expect(response.body).not_to include('&amp;lt;')
      end

      it 'answers a stale save with 409, the stored mapping and the posted version as conflict mapping; the fresh ' \
         'state hash saves it (T-DEPJ-8, T-DEPJ-16, UD-17)' do
        raw_before = raw_store(child)
        allow(payload).to receive(:parse).and_call_original
        meta = { 'mode' => 'merge', 'rows' => 1 }
        mine = json({ 'Germany' => %w[Lyon] }, { 'Germany' => 'Lyon' }, 'source' => 'import', 'import' => meta)

        save(child, mine, state: 'stale')

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

        save(child, mine, state: fresh)

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

      it 'removes stored orphans on save and counts them; an identical save is still audited (edge case 9)' do
        field = store_raw(child, { 'Gone' => %w[Antwerp], 'Belgium' => %w[zz Antwerp] })

        save(field, json({ 'Belgium' => %w[Antwerp] }))
        save(field, json({ 'Belgium' => %w[Antwerp] }))

        first, second = rows(field).last(2)
        expect(JSON.parse(first.after_value)['orphans_removed']).to eq(2)
        expect(first.changes_summary).to include('2 orphaned removed')
        expect(JSON.parse(second.after_value).values_at('added', 'removed')).to eq([0, 0])
        expect([first.status, second.status]).to eq(%w[success success])
      end

      it 'never names a hidden child of the edited field on the page, a 422 or a 409' do
        grandchild = dcf_list_field(format: 'depending_list', name: 'Secret grandchild', values: %w[SECRET-G1],
                                    parent: child)
        dcf_set_dependencies(grandchild, value_dependencies: { 'Antwerp' => %w[SECRET-G1] })
        grandchild.update!(visible: false, role_ids: [dcf_create_role.id])
        before = raw_store(grandchild)

        get page_path(child)
        bodies = [response.body]
        save(child, json({ 'ZZ' => %w[Antwerp] }))
        bodies << response.body
        save(child, json({ 'Germany' => %w[Lyon] }), state: 'stale')
        bodies << response.body
        save(child, json({ 'Germany' => %w[Lyon] }))

        bodies.each do |body|
          expect(body).not_to include('Secret grandchild')
          expect(body).not_to include('SECRET-G1')
        end
        expect(raw_store(grandchild)).to eq(before)
        expect(rows(child).last.changes_summary).not_to include('Secret')
        expect(rows(child).last.affected_child_field_ids.to_s).not_to include(grandchild.id.to_s)
      end

      it 'shows a foreign enumeration id raw in offenders and samples, never its hidden label (gap 3)' do
        hidden = dcf_enum_field(name: "SecretEnum-#{SecureRandom.hex(3)}", names: ['SECRET-LABEL'])
        hidden.update!(visible: false, role_ids: [dcf_create_role.id])
        secret = hidden.enumerations.first.id.to_s
        enum_parent = dcf_enum_field(name: "EP-#{SecureRandom.hex(3)}", names: %w[North])
        enum_child = dcf_enum_field(format: 'depending_enumeration', name: "EC-#{SecureRandom.hex(3)}",
                                    names: %w[Alpha], parent: enum_parent)
        north = enum_parent.enumerations.first.id.to_s
        alpha = enum_child.enumerations.first.id.to_s

        save(enum_child, json(north => [secret]))

        expect(response).to have_http_status(422)
        expect(rows(enum_child).last.changes_summary).to eq("unknown child values: 1 [#{secret}]")
        expect(response.body).not_to include('SECRET-LABEL')
        expect(response.body).not_to include(hidden.name)

        store_raw(enum_child, { north => [alpha, secret] })
        save(enum_child, json(north => [alpha]))

        expect(response).to redirect_to(page_path(enum_child))
        row = rows(enum_child).last
        after = JSON.parse(row.after_value)
        expect(after['sample']['removed']).to eq([['North', secret]])
        expect(after['orphans_removed']).to eq(1)
        expect(row.after_value).not_to include('SECRET-LABEL')
      end

      it 'saves a replace import on a global field without any confirmation step (UD-23)' do
        expect(child.is_for_all).to be(true)
        save(child, json({ 'Germany' => %w[Lyon] }, {}, 'source' => 'import',
                                                       'import' => { 'mode' => 'replace', 'rows' => 1 }))

        expect(response).to redirect_to(page_path(child))
        expect(stored(child)).to eq([{ 'Germany' => %w[Lyon] }, {}])
        row = rows(child).last
        expect(JSON.parse(row.after_value).values_at('source', 'import'))
          .to eq(['import', { 'mode' => 'replace', 'rows' => 1 }])
        expect(row.affected_projects_count).to eq(Project.active.count)
        follow_redirect!
        expect(doc.css('input[name=confirm]')).to be_empty
        expect(response.body).not_to include(I18n.t(:text_dcf_confirm_understand))
      end
    end

    describe 'PATCH with the deprecated nested params' do
      it 'clears without mapping params, audits source form and logs one constant deprecation line (T-DEPJ-9)' do
        child
        allow(Rails.logger).to receive(:warn).and_call_original
        allow(payload).to receive(:parse).and_call_original

        patch custom_field_configuration_update_dependencies_path(project, child)

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

      it 'are the same for a save of 10 and of 4,200 links' do
        small_parent = dcf_list_field(name: "SP-#{SecureRandom.hex(3)}", values: %w[P1 P2])
        small = dcf_list_field(format: 'depending_list', name: "SC-#{SecureRandom.hex(3)}",
                               values: (1..5).map { |i| "C#{i}" }, parent: small_parent)
        big_parent = dcf_list_field(name: "BP-#{SecureRandom.hex(3)}", values: (1..42).map { |i| "P#{i}" })
        big = dcf_list_field(format: 'depending_list', name: "BC-#{SecureRandom.hex(3)}",
                             values: (1..100).map { |i| "C#{i}" }, parent: big_parent)
        save(small, '{}')
        small_raw = full(small, small_parent)
        big_raw = full(big, big_parent)
        small_state = state_hash(small)
        big_state = state_hash(big)

        small_queries = dcf_count_queries { save(small, small_raw, state: small_state) }
        big_queries = dcf_count_queries { save(big, big_raw, state: big_state) }

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
end
