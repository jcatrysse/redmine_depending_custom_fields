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
end
