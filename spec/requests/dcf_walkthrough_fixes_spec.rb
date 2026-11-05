# frozen_string_literal: true

require_relative '../rails_helper'

# Chromium walkthrough of 2026-11-05 (docs/reviews/chromium-walkthrough-2026-11-05.md):
# the confirmed findings of the project configuration pages, the audit pages
# and the context-menu wizard that the server renders.
RSpec.describe 'Chromium walkthrough fixes', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:manager) { dcf_manager(project) }
  let(:other_role) { dcf_create_role(permissions: [:view_issues]) }
  let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def state_hash(field)
    RedmineDependingCustomFields::BaseService.state_hash(CustomField.find(field.id))
  end

  def audit_row(field, **attrs)
    events.create!({ project_id: project.id, custom_field_id: field.id, custom_field_name: field.name,
                     acting_user_id: 1, acting_user_name: 'Redmine Admin', action: 'add_value', status: 'success',
                     changes_summary: "Added value 'A'", created_at: Time.now }.merge(attrs))
  end

  # admin-1: a holder of the permission who may not see a field never gets
  # it listed, named or its values rendered; it answers 404 like an unknown
  # field, on every page and update action.
  describe 'a field hidden from the role of the manager (admin-1)' do
    let(:secret) { "ZULU-#{SecureRandom.hex(3)}" }
    let(:hidden) { dcf_list_field(name: "Secret-#{SecureRandom.hex(3)}", values: [secret, 'Other']) }
    let(:hidden_child) do
      field = dcf_list_field(format: 'depending_list', name: "SecretChild-#{SecureRandom.hex(3)}",
                             values: %w[sc1 sc2], parent: hidden)
      dcf_set_dependencies(field, value_dependencies: { secret => %w[sc1] })
    end
    let(:visible) { dcf_list_field(name: "Open-#{SecureRandom.hex(3)}", values: %w[O1 O2]) }

    before do
      visible
      hidden_child.update!(visible: false, role_ids: [other_role.id])
      hidden.update!(visible: false, role_ids: [other_role.id])
    end

    def requests(field)
      { show: -> { get custom_field_configuration_field_path(project, field) },
        dependencies: -> { get custom_field_configuration_field_dependencies_path(project, field) },
        add: -> { post custom_field_configuration_add_value_path(project, field), params: { value: 'Hack' } },
        rename: lambda {
          patch custom_field_configuration_rename_value_path(project, field),
                params: { old_value: field.possible_values.first, new_value: 'Hack', confirm: '1' }
        },
        remove: lambda {
          delete custom_field_configuration_remove_value_path(project, field),
                 params: { value: field.possible_values.first, confirm: '1' }
        },
        reorder: lambda {
          patch custom_field_configuration_reorder_values_path(project, field),
                params: { ordered_values: field.possible_values.reverse, confirm: '1' }
        },
        sort: lambda {
          patch custom_field_configuration_sort_values_path(project, field), params: { direction: 'desc', confirm: '1' }
        },
        enumerations: -> { patch custom_field_configuration_update_enumerations_path(project, field), params: {} },
        default: lambda {
          patch custom_field_configuration_set_default_value_path(project, field),
                params: { default_value: field.possible_values.last, confirm: '1' }
        },
        save_dependencies: lambda {
          patch custom_field_configuration_update_dependencies_path(project, field),
                params: { dependencies_json: '{"value_dependencies":{},"default_value_dependencies":{}}', confirm: '1' }
        } }
    end

    it 'is not listed on the settings tab, which lists the visible field' do
      as(manager)
      get settings_project_path(project, tab: 'custom_field_configuration')

      expect(response).to have_http_status(200)
      expect(doc.css('table.dcf-config-fields').text).to include(visible.name)
      expect(response.body).not_to include(hidden.name)
      expect(response.body).not_to include(hidden_child.name)
    end

    it 'answers 404 on its pages and on every update action, names nothing and changes nothing' do
      as(manager)
      [hidden, hidden_child].each do |field|
        before = CustomField.find(field.id).attributes
        requests(field).each do |name, call|
          call.call
          expect(response).to have_http_status(404), "#{name} #{field.name}"
          expect(response.body).not_to include(field.name)
          expect(response.body).not_to include(secret)
        end
        expect(CustomField.find(field.id).attributes).to eq(before)
      end
    end

    it 'is refused by the services as well (defense in depth)' do
      error = begin
        RedmineDependingCustomFields::AddValueService.new(project: project, field: CustomField.find(hidden.id),
                                                          user: manager, params: { value: 'Hack' }).call
        nil
      rescue RedmineDependingCustomFields::OperationError => e
        e
      end
      expect([error&.key, error&.http_status]).to eq([:error_field_not_found, :not_found])
      expect(CustomField.find(hidden.id).possible_values).to eq([secret, 'Other'])
    end

    it 'keeps its audit rows off the project audit page; an administrator sees them' do
      audit_row(hidden, changes_summary: "Added value '#{secret}'")
      audit_row(visible, changes_summary: "Added value 'O2'")
      as(manager)
      get custom_field_configuration_audit_path(project)
      expect(response).to have_http_status(200)
      expect(response.body).not_to include(hidden.name)
      expect(response.body).not_to include(secret)
      expect(doc.at_css('table.dcf-audit-list').text).to include(visible.name)

      as(dcf_admin)
      get custom_field_configuration_audit_path(project)
      expect(response.body).to include(hidden.name)
    end

    it 'stays fully available to an administrator' do
      as(dcf_admin)
      get settings_project_path(project, tab: 'custom_field_configuration')
      expect(response.body).to include(hidden.name)
      get custom_field_configuration_field_path(project, hidden)
      expect(response).to have_http_status(200)
      get custom_field_configuration_field_dependencies_path(project, hidden_child)
      expect(response).to have_http_status(200)
    end

    it 'shows a visible child of the hidden parent with the generic parent text and no parent value' do
      open_child = dcf_list_field(format: 'depending_list', name: "OpenChild-#{SecureRandom.hex(3)}",
                                  values: %w[oc1], parent: hidden)
      dcf_set_dependencies(open_child, value_dependencies: { secret => %w[oc1] })
      as(manager)
      get custom_field_configuration_field_dependencies_path(project, open_child)
      expect(response).to have_http_status(200)
      expect(doc.at_css('p.warning').text.strip).to eq(I18n.t(:text_dcf_parent_not_available_generic))
      expect(response.body).not_to include(hidden.name)
      expect(response.body).not_to include(secret)
    end
  end

  # ux-3: translated actions, statuses and refusal summaries, at render time.
  describe 'the audit pages (ux-3)' do
    let(:field) { dcf_list_field(name: "Audited-#{SecureRandom.hex(3)}", values: %w[A B]) }

    before do
      audit_row(field, action: 'validation_failed', status: 'validation_failed', error_message: 'error_stale_edit',
                       changes_summary: nil)
      audit_row(field, action: 'validation_failed', status: 'validation_failed',
                       error_message: 'error_dcf_values_too_large',
                       changes_summary: "possible_values: 275014 bytes exceeds 275004 (custom field ##{field.id})")
      audit_row(field, action: 'sort_values', status: 'success', changes_summary: 'Sorted 2 value(s) A-Z (1 moved)')
      audit_row(field, action: 'future_action', status: 'error', error_message: 'Some raw text',
                       changes_summary: nil)
    end

    def cells
      doc.css('table.dcf-audit-list tbody tr').map { |tr| tr.css('td').map { |td| td.text.strip } }
    end

    it 'shows labels and texts instead of keys and developer text on the project and the admin page' do
      [[manager, -> { get custom_field_configuration_audit_path(project) }, 3],
       [dcf_admin, -> { get dcf_config_audit_path }, 4]].each do |user, call, action_col|
        as(user)
        call.call
        expect(response).to have_http_status(200)
        rows = cells
        actions = rows.map { |r| r[action_col] }
        statuses = rows.map { |r| r[action_col + 1] }
        summaries = rows.map { |r| r[action_col + 2] }
        expect(actions).to eq(['future_action', I18n.t(:label_dcf_audit_action_sort_values),
                               I18n.t(:label_dcf_audit_action_validation_failed),
                               I18n.t(:label_dcf_audit_action_validation_failed)])
        expect(statuses).to eq([I18n.t(:label_dcf_audit_status_error), I18n.t(:label_dcf_audit_status_success),
                                I18n.t(:label_dcf_audit_status_validation_failed),
                                I18n.t(:label_dcf_audit_status_validation_failed)])
        expect(summaries).to eq(['Some raw text', 'Sorted 2 value(s) A-Z (1 moved)',
                                 I18n.t(:text_dcf_audit_values_too_large, size: limits.delimited(275_014),
                                                                         limit: limits.delimited(275_004)),
                                 I18n.t(:error_stale_edit)])
        expect(response.body).not_to include('error_stale_edit')
        expect(response.body).not_to include('bytes exceeds')
        expect(response.body).not_to include('custom field #')
        # The stored rows are unchanged.
        expect(events.where(error_message: 'error_stale_edit').count).to eq(1)
      end
    end
  end

  # ux-5: delimited counts on the Settings tab and in the values page filter
  # info (the pager is core's markup, undelimited as on core's lists).
  describe 'counts (ux-5)' do
    let(:field) do
      dcf_list_field(name: "Big-#{SecureRandom.hex(3)}", values: (1..1_200).map { |i| i <= 1_100 ? "X#{i}" : "Y#{i}" })
    end

    it 'formats the counts with delimiters' do
      as(manager)
      field
      get settings_project_path(project, tab: 'custom_field_configuration')
      row = doc.css('table.dcf-config-fields tr').find { |tr| tr.text.include?(field.name) }
      # Redmine 5.1 en has no thousands delimiter, 6.0 and later a comma.
      expect(row.css('td').map { |td| td.text.strip }).to include(limits.delimited(1_200))

      get custom_field_configuration_field_path(project, field, q: 'X')
      expect(doc.css('p.info').map { |p| p.text.strip })
        .to include(I18n.t(:text_dcf_values_filtered, count: limits.delimited(1_100), total: limits.delimited(1_200)))
    end
  end

  # ux-6, admin-4 and ux-15: subtitles without parentheses, the Value column
  # without the empty handle column, the drag note above the limit.
  describe 'the values and dependency pages (ux-6, admin-4, ux-15)' do
    let(:parent) { dcf_list_field(name: "Country-#{SecureRandom.hex(3)}", values: %w[A B]) }
    let(:child) do
      dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}", values: %w[c1], parent: parent)
    end

    it 'shows the format and the page name without parentheses' do
      as(manager)
      get custom_field_configuration_field_path(project, child)
      expect(doc.at_css('h2 em.info').text.strip).to eq(I18n.t(:label_depending_list))
      get custom_field_configuration_field_dependencies_path(project, child)
      expect(doc.at_css('h2 em.info').text.strip).to eq(I18n.t(:label_custom_field_dependencies))
    end

    it 'says that drag and drop is not available above the limit, not on an empty match, ' \
       'and has no empty handle column' do
      max = RedmineDependingCustomFields::ValuesPage::UNPAGINATED_MAX
      big = dcf_list_field(name: "Many-#{SecureRandom.hex(3)}", values: (1..(max + 1)).map { |i| "W#{i}" })
      as(manager)
      get custom_field_configuration_field_path(project, big)
      note = I18n.t(:text_dcf_drag_reorder_large, max: max)
      expect(note).to include('not available')
      expect(doc.css('p.info').map { |p| p.text.strip }).to include(note)
      expect(doc.css('table.dcf-values td.reorder, table.dcf-values th.reorder')).to be_empty
      expect(doc.at_css('table.dcf-values thead tr').css('th').size).to eq(2)

      get custom_field_configuration_field_path(project, big, q: 'nothing-matches')
      expect(doc.css('p.info').map { |p| p.text.strip }).not_to include(note)

      get custom_field_configuration_field_path(project, parent)
      expect(doc.css('table.dcf-values td.reorder').size).to eq(2)
    end

    it 'groups the two sort buttons under one label' do
      as(manager)
      get custom_field_configuration_field_path(project, parent)
      group = doc.at_css('.dcf-values-sort-group[role=group]')
      expect(group['aria-label']).to eq(I18n.t(:label_sort))
      expect(group.css('form.button_to input[type=submit], form.button_to button').size).to eq(2)
    end
  end

  # ux-14: the confirmation panel heading sits on the icon line.
  it 'puts the confirmation heading directly in the flash box, without an empty first row (ux-14)' do
    field = dcf_list_field(values: %w[A B], is_for_all: true)
    as(manager)
    patch custom_field_configuration_rename_value_path(project, field), params: { old_value: 'A', new_value: 'A2' }
    box = doc.at_css('div.dcf-confirm-panel > div.flash.warning')
    first = box.element_children.reject { |el| el.name == 'svg' }.first
    expect([first.name, first.text.strip]).to eq(['strong', I18n.t(:text_confirm_cross_project_change)])
    css = File.read(File.expand_path('../../assets/stylesheets/dcf_config.css', __dir__))
    expect(css).to match(/\.dcf-confirm-panel > \.flash\.warning \{[^}]*color: inherit/)
  end

  # admin-2: a refusal under the project ceiling names the ceiling.
  it 'names the configured ceiling when the project ceiling refuses a change (admin-2)' do
    field = dcf_list_field(name: "Ceiled-#{SecureRandom.hex(3)}", values: ['A' * 70_000], is_for_all: false,
                           projects: [project])
    allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
      .and_return('project_storage_ceiling_kib' => '64', 'manage_standard_custom_fields' => '1')
    as(manager)
    post custom_field_configuration_add_value_path(project, field), params: { value: 'B' }

    text = doc.at_css('#flash_error').text.strip
    stored = limits.serialized_bytesize(CustomField, 'possible_values', ['A' * 70_000])
    size = limits.serialized_bytesize(CustomField, 'possible_values', ['A' * 70_000, 'B'])
    expect(text).to eq(I18n.t(:error_dcf_values_over_ceiling, field: field.name, size: limits.delimited(size),
                                                              limit: limits.delimited(stored), ceiling: '64'))
    expect(text).to include('64 KiB')
  end

  # issue-1, ux-2: the wizard refusal groups the issues per message.
  describe 'the wizard refusal (issue-1, ux-2)' do
    let(:role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
    let(:user) do
      member = dcf_create_user("wz-#{SecureRandom.hex(3)}")
      dcf_add_member(member, project, role)
      member
    end
    let(:parent) { dcf_list_field(values: %w[low high], name: "Level-#{SecureRandom.hex(3)}") }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[c1 c2], parent: parent,
                             name: "Sub-#{SecureRandom.hex(3)}")
      dcf_set_dependencies(field, value_dependencies: { 'low' => %w[c1], 'high' => %w[c2] })
    end
    let(:other) do
      field = dcf_list_field(format: 'depending_list', values: %w[o1 o2], parent: parent,
                             name: "Other-#{SecureRandom.hex(3)}")
      dcf_set_dependencies(field, value_dependencies: { 'low' => %w[o1], 'high' => %w[o2] })
    end

    it 'gives one line per message with the issue numbers, as bulk edit does' do
      issues = Array.new(2) { dcf_real_issue(project, parent => 'low', child => 'c1', other => 'o1') }
      as(user)
      post '/depending_custom_fields/save',
           params: { issue_ids: issues.map(&:id).join(','),
                     issue: { custom_field_values: { parent.id.to_s => 'high' } } }

      expect(response).to have_http_status(:unprocessable_entity)
      ids = issues.map { |i| "##{i.id}" }.join(', ')
      invalid = I18n.t('activerecord.errors.messages.invalid')
      expect(JSON.parse(response.body)['errors'])
        .to eq(["#{child.name} #{invalid}: #{ids}", "#{other.name} #{invalid}: #{ids}"])
    end
  end

  # ux-13: the field name in the wizard has a title only with a description.
  it 'gives the wizard field name a title only when the field has a description (ux-13)' do
    role = dcf_create_role(permissions: [:view_issues, :edit_issues])
    user = dcf_create_user("wt-#{SecureRandom.hex(3)}")
    dcf_add_member(user, project, role)
    parent = dcf_list_field(values: %w[low high], name: "Lvl-#{SecureRandom.hex(3)}")
    child = dcf_list_field(format: 'depending_list', values: %w[c1], parent: parent, name: "Sb-#{SecureRandom.hex(3)}")
    dcf_set_dependencies(child, value_dependencies: { 'low' => %w[c1], 'high' => %w[c1] })
    child.update!(description: 'Explained')
    issue = dcf_real_issue(project, parent => 'low', child => 'c1')
    as(user)
    get '/depending_custom_fields/wizard', params: { ids: [issue.id], parent_id: parent.id }
    expect(response).to have_http_status(200)
    titles = doc.css('span.field-description').to_h { |span| [span.text.strip, span['title']] }
    expect(titles).to eq(parent.name => nil, child.name => 'Explained')
  end

  # ux-9 and ux-12: the texts give a next step.
  it 'gives the privacy-safe refusal and the wizard load error a next step in every locale (ux-9, ux-12)' do
    next_steps = {
      'en' => ['cannot see', 'ask someone who can see all fields', 'Click the entry again'],
      'de' => ['nicht sehen', 'der alle Felder sehen kann', 'Klicken Sie erneut'],
      'fr' => ['pas voir', 'qui peut voir tous les champs', 'Cliquez à nouveau'],
      'nl' => ['niet kunt zien', 'die alle velden kan zien', 'Klik nogmaals']
    }
    next_steps.each do |locale, (base, step, retry_text)|
      I18n.with_locale(locale) do
        refusals = [I18n.t('activerecord.errors.messages.dcf_hidden_child_conflict'),
                    I18n.t(:error_dcf_hidden_child_conflict)]
        refusals.each { |text| expect(text).to include(base).and include(step) }
        expect(I18n.t(:text_dcf_wizard_load_failed)).to include(retry_text)
      end
    end
  end
end
