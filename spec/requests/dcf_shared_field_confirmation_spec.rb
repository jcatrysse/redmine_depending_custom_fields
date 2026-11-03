# frozen_string_literal: true

require_relative '../rails_helper'

# WP-34 (UD-23 changed by the owner on 2026-11-02): on a field shared with
# other projects or global (the scope banner case) a dependency save of the
# project dependency page (editor save, replace import and the deprecated
# nested params) and a sort A-Z / Z-A need the server-side confirmation, as
# rename and remove do. One scope rule decides the banner, the badge, the
# dependency page checkbox, the sort buttons and the services. A missing
# confirmation writes nothing and no audit row. Drag-and-drop reorder and the
# other value operations stay without confirmation (owner scope: sort only).
RSpec.describe 'Confirmation on shared and global fields (UD-23, WP-34)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:other) { dcf_create_project(name: "Other-#{SecureRandom.hex(3)}") }
  let(:manager) { dcf_manager(project) }
  let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
  let(:service) { RedmineDependingCustomFields::BaseService }
  let(:multipart) { { 'CONTENT_TYPE' => 'multipart/form-data' } }
  let(:warning) { I18n.t(:text_confirm_cross_project_change) }

  before { allow(User).to receive(:current).and_return(manager) }

  def doc
    Nokogiri::HTML(response.body)
  end

  def rows(field)
    events.where(custom_field_id: field.id).order(:id)
  end

  def scope_options(scope)
    case scope
    when :global then { is_for_all: true }
    when :shared then { is_for_all: false, projects: [project, other] }
    when :archived_other then { is_for_all: false, projects: [project, dcf_create_project(status: :archived)] }
    when :project then { is_for_all: false, projects: [project] }
    end
  end

  # A depending child in +scope+ (:project_field for a ProjectCustomField
  # pair) with a project-only parent.
  def child_in(scope)
    if scope == :project_field
      parent = dcf_list_field(type: ProjectCustomField, name: "PP-#{SecureRandom.hex(3)}", values: %w[A B])
      child = dcf_list_field(type: ProjectCustomField, format: 'depending_list', name: "PC-#{SecureRandom.hex(3)}",
                             values: %w[c1 c2], parent: parent)
    else
      parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B], is_for_all: false, projects: [project])
      child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[c1 c2],
                             parent: parent, **scope_options(scope))
    end
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1] }, default_value_dependencies: { 'A' => 'c1' })
  end

  def list_in(scope, values = %w[c b a])
    return dcf_list_field(type: ProjectCustomField, values: values) if scope == :project_field

    dcf_list_field(values: values, **scope_options(scope))
  end

  def stored(field)
    record = CustomField.find(field.id)
    [record.value_dependencies.to_hash, record.default_value_dependencies.to_hash]
  end

  def json(vd, dd = {}, extra = {})
    JSON.generate({ 'value_dependencies' => vd, 'default_value_dependencies' => dd }.merge(extra))
  end

  def page_path(field)
    custom_field_configuration_field_dependencies_path(project, field)
  end

  def save(field, raw, extra = {})
    params = { dependencies_json: raw, state_hash: service.state_hash(CustomField.find(field.id)) }.merge(extra)
    patch custom_field_configuration_update_dependencies_path(project, field), params: params, headers: multipart
  end

  def confirm_boxes
    doc.css('#dcf-dependencies-form input[type=checkbox][name=confirm][required]')
  end

  def editor
    doc.at_css('fieldset[data-dcf-editor]')
  end

  def banner?
    texts = [I18n.t(:text_global_field_warning), I18n.t(:text_shared_field_warning)]
    doc.css('div.flash.warning').any? { |box| texts.include?(box.text.strip) }
  end

  def sort_path(field)
    custom_field_configuration_sort_values_path(project, field)
  end

  def show_path(field, params = {})
    custom_field_configuration_field_path(project, field, params)
  end

  def sort_forms
    doc.css('div.dcf-values-toolbar form[action$="/values/sort"]')
  end

  def panel_form
    doc.at_css('.dcf-confirm-panel form')
  end

  # Without the CSRF token and the utf8 marker form_tag adds on Rails 6.1 (5.1).
  def hidden_fields(form)
    form.css('input[type="hidden"]').reject { |n| %w[authenticity_token utf8].include?(n['name']) }
        .to_h { |n| [n['name'], n['value']] }
  end

  describe 'one scope rule' do
    # The banner is shown iff the dependency page has the checkbox iff the
    # sort buttons carry no data-confirm iff a save and a sort without
    # confirm give the confirmation.
    it 'decides the banner, the checkbox, the sort buttons and the services alike' do
      expected = { global: true, project_field: true, shared: true, archived_other: true, project: false }
      expected.each do |scope, asks|
        child = child_in(scope)
        get page_path(child)
        expect(response).to have_http_status(200), scope.to_s
        expect([banner?, confirm_boxes.size]).to eq([asks, asks ? 1 : 0]), scope.to_s

        save(child, json({ 'B' => %w[c2] }))
        expect(response).to have_http_status(asks ? 422 : 302), scope.to_s
        expect(stored(child).first).to eq(asks ? { 'A' => %w[c1] } : { 'B' => %w[c2] }), scope.to_s

        list = list_in(scope)
        get show_path(list)
        expect(banner?).to eq(asks), scope.to_s
        expect(sort_forms.size).to eq(2), scope.to_s
        expect(sort_forms.map { |form| form.at_css('[data-confirm]').nil? }.uniq).to eq([asks]), scope.to_s
        patch sort_path(list), params: { direction: 'asc', state_hash: service.state_hash(list) }
        expect(response).to have_http_status(asks ? 422 : 302), scope.to_s
        expect(doc.css('.dcf-confirm-panel').size).to eq(asks ? 1 : 0), scope.to_s if asks
        expect(list.reload.possible_values).to eq(asks ? %w[c b a] : %w[a b c]), scope.to_s
      end
    end

    it 'is defined once and read by the helper and the services' do
      root = File.expand_path('../..', __dir__)
      files = Dir[File.join(root, '{app,lib}/**/*.rb')]
      definitions = files.select { |path| File.read(path).include?('field.projects.reject { |p| p.id == project.id }') }
      expect(definitions.map { |path| path.delete_prefix("#{root}/") })
        .to eq(['app/services/redmine_depending_custom_fields/field_relevance.rb'])
      helper = File.read(File.join(root, 'app/helpers/project_custom_field_configuration_helper.rb'))
      base = File.read(File.join(root, 'app/services/redmine_depending_custom_fields/base_service.rb'))
      expect(helper).to include('FieldRelevance.scope(field, project)')
      expect(base).to include('FieldRelevance.scope(field, project)')
    end

    # Decided at POST time: a field that became shared after the GET asks.
    it 'honours a scope change between the GET and the save' do
      child = child_in(:project)
      get page_path(child)
      expect(confirm_boxes).to be_empty
      raw = json({ 'B' => %w[c2] })
      state = service.state_hash(child)
      child.projects << other

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { dependencies_json: raw, state_hash: state }, headers: multipart
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_warning').text.strip).to eq(warning)
      expect(confirm_boxes.size).to eq(1)
      expect(stored(child).first).to eq('A' => %w[c1])
    end
  end

  describe 'dependency page' do
    it 'renders one unchecked required checkbox next to Save for shared and global fields only' do
      [:global, :shared].each do |scope|
        child = child_in(scope)
        get page_path(child)
        box = confirm_boxes.first
        expect(confirm_boxes.size).to eq(1), scope.to_s
        expect([box['value'], box['checked'], box['autocomplete']]).to eq(['1', nil, 'off']), scope.to_s
        expect(box.ancestors('p.buttons').size).to eq(1), scope.to_s
        expect(box.ancestors('fieldset[data-dcf-editor]')).to be_empty, scope.to_s
        expect(box.ancestors('label').first.text.squish).to eq(I18n.t(:text_dcf_confirm_understand)), scope.to_s
        expect(doc.css('#dcf-dependencies-form [data-confirm]')).to be_empty, scope.to_s
        expect(doc.css('.dcf-confirm-panel')).to be_empty, scope.to_s
      end
    end

    it 'has no checkbox on the parent-missing and parent-not-available pages, nor on the admin form' do
      child = child_in(:global)
      CustomField.where(id: child.id).update_all(
        ['format_store = ?', CustomField.type_for_attribute('format_store').serialize(
          CustomField.find(child.id).format_store.to_hash.merge('parent_custom_field_id' => 99_999_999)
        )]
      )
      get page_path(child)
      expect(response).to have_http_status(200)
      expect(doc.at_css('p.nodata').text).to include(I18n.t(:text_dcf_parent_missing))
      expect(doc.css('input[name=confirm]')).to be_empty

      outside = dcf_list_field(name: "Outside-#{SecureRandom.hex(3)}", values: %w[A], is_for_all: false, projects: [other])
      unavailable = dcf_list_field(format: 'depending_list', name: "U-#{SecureRandom.hex(3)}", values: %w[c1],
                                   parent: outside, is_for_all: true)
      get page_path(unavailable)
      expect(response).to have_http_status(200)
      expect(doc.at_css('p.warning')).not_to be_nil
      expect(doc.css('input[name=confirm]')).to be_empty

      allow(User).to receive(:current).and_return(dcf_admin)
      get edit_custom_field_path(child_in(:global))
      expect(response).to have_http_status(200)
      expect(doc.css('input[name=confirm]')).to be_empty
    end

    it 'answers an editor save without confirm with 422, the warning flash and the posted mapping dirty, writing nothing' do
      child = child_in(:global)
      before = stored(child)
      posted = { 'value_dependencies' => { 'B' => %w[c2] }, 'default_value_dependencies' => { 'B' => 'c2' } }

      expect { save(child, JSON.generate(posted)) }.not_to change(events, :count)
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_warning').text.strip).to eq(warning)
      expect(doc.at_css('#flash_error')).to be_nil
      expect(editor['data-dcf-editor-dirty']).to eq('1')
      expect(JSON.parse(editor['data-dcf-editor-mapping'])).to eq(posted)
      expect(doc.css('input[name="dependencies_json"]').map { |input| input['value'] }).to eq([''])
      expect(doc.at_css('input[name="state_hash"]')['value']).to eq(service.state_hash(CustomField.find(child.id)))
      expect(confirm_boxes.size).to eq(1)
      expect(confirm_boxes.first['checked']).to be_nil
      expect(stored(child)).to eq(before)

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { dependencies_json: JSON.generate(posted), state_hash: doc.at_css('input[name="state_hash"]')['value'],
                      confirm: '1' }, headers: multipart
      expect(response).to redirect_to(page_path(child))
      expect(flash[:notice]).to eq(I18n.t(:notice_dependencies_saved))
      expect(stored(child)).to eq([{ 'B' => %w[c2] }, { 'B' => 'c2' }])
      row = rows(child).last
      expect([rows(child).count, row.action, row.status]).to eq([1, 'update_dependencies', 'success'])
    end

    it 'asks the same for a replace import, which then audits source import once confirmed' do
      child = child_in(:shared)
      import = { 'mode' => 'replace', 'rows' => 1 }
      raw = json({ 'B' => %w[c2] }, {}, 'source' => 'import', 'import' => import)

      expect { save(child, raw) }.not_to change(events, :count)
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_warning').text.strip).to eq(warning)
      expect(editor['data-dcf-editor-dirty']).to eq('1')
      expect(JSON.parse(editor['data-dcf-editor-mapping'])['value_dependencies']).to eq('B' => %w[c2])
      expect(stored(child)).to eq([{ 'A' => %w[c1] }, { 'A' => 'c1' }])

      expect { save(child, raw, confirm: '1') }.to change(events, :count).by(1)
      expect(response).to redirect_to(page_path(child))
      after = JSON.parse(rows(child).last.after_value)
      expect(after.values_at('v', 'source', 'import')).to eq([2, 'import', import])
    end

    it 'asks on the deprecated nested params and re-renders the stored mapping, not dirty' do
      child = child_in(:global)
      allow(Rails.logger).to receive(:warn).and_call_original
      expect do
        patch custom_field_configuration_update_dependencies_path(project, child),
              params: { value_dependencies: { 'B' => %w[c2] }, state_hash: service.state_hash(child) }
      end.not_to change(events, :count)
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_warning').text.strip).to eq(warning)
      expect(editor['data-dcf-editor-dirty']).to be_nil
      expect(JSON.parse(editor['data-dcf-editor-mapping']))
        .to eq('value_dependencies' => { 'A' => %w[c1] }, 'default_value_dependencies' => { 'A' => 'c1' })
      expect(Rails.logger).to have_received(:warn)
        .with(RedmineDependingCustomFields::DependencyMappingService::LEGACY_WARNING).once

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { value_dependencies: { 'B' => %w[c2] }, state_hash: service.state_hash(child), confirm: '1' }
      expect(response).to redirect_to(page_path(child))
      expect(stored(child)).to eq([{ 'B' => %w[c2] }, {}])
    end

    it 'refuses confirm[]=1 and confirm[a]=1 with the confirmation, never a 500' do
      child = child_in(:global)
      [{ 'confirm' => ['1'] }, { 'confirm' => { 'a' => '1' } }].each do |extra|
        save(child, json({ 'B' => %w[c2] }), extra)
        expect(response).to have_http_status(422), extra.inspect
        expect(doc.at_css('#flash_warning').text.strip).to eq(warning), extra.inspect
        expect(stored(child)).to eq([{ 'A' => %w[c1] }, { 'A' => 'c1' }])
      end
      expect(rows(child)).to be_empty
    end

    it 'keeps the audited 422 of a payload error without confirm and never pre-checks the box' do
      child = child_in(:global)
      save(child, '{')
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_error').text.strip).to eq(I18n.t(:error_invalid_dependency_payload))
      expect(doc.at_css('#flash_warning')).to be_nil
      expect(confirm_boxes.first['checked']).to be_nil

      save(child, json({ 'ZZ' => %w[c1] }), confirm: '1')
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_error').text.strip).to eq(I18n.t(:error_invalid_dependency))
      expect(confirm_boxes.first['checked']).to be_nil

      save(child, json({ 'B' => %w[c2] }), confirm: '1', state_hash: 'stale')
      expect(response).to have_http_status(409)
      expect(confirm_boxes.size).to eq(1)
      expect(confirm_boxes.first['checked']).to be_nil

      bytes = CustomField.connection.select_value(CustomField.where(id: child.id).select(:format_store).to_sql).bytesize
      allow(RedmineDependingCustomFields::StorageLimits).to receive(:column_limit).and_return(nil)
      allow(RedmineDependingCustomFields::StorageLimits).to receive(:column_limit).with('format_store').and_return(bytes)
      save(child, json({ 'A' => %w[c1 c2], 'B' => %w[c1 c2] }))
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_warning').text.strip).to eq(warning)
      save(child, json({ 'A' => %w[c1 c2], 'B' => %w[c1 c2] }), confirm: '1')
      expect(response).to have_http_status(422)
      expect(doc.at_css('#flash_error').text).to include(I18n.t(:error_dcf_mapping_too_large).split('%{').first.strip)
      expect(confirm_boxes.first['checked']).to be_nil
      expect(rows(child).pluck(:status)).to eq(%w[validation_failed validation_failed validation_failed validation_failed])
    end

    it 'saves a project-only field without confirm as before' do
      child = child_in(:project)
      expect { save(child, json({ 'B' => %w[c2] })) }.to change(events, :count).by(1)
      expect(response).to redirect_to(page_path(child))
      expect(stored(child).first).to eq('B' => %w[c2])
    end
  end

  describe 'sort panel' do
    def labels(count)
      (1..count).map { |i| format('Value %04d', i) }
    end

    it 'answers a global sort without confirm with the sort panel carrying direction, the posted state_hash and q' do
      field = list_in(:global, labels(60).reverse)
      state = service.state_hash(field)
      expect do
        patch sort_path(field), params: { direction: 'desc', state_hash: state, q: 'value', page: '2' }
      end.not_to change(events, :count)

      expect(response).to have_http_status(422)
      expect(doc.css('.dcf-confirm-panel').size).to eq(1)
      panel = doc.at_css('.dcf-confirm-panel')
      expect(panel.at_css('div.flash.warning')).not_to be_nil
      expect(doc.css('.dcf-confirm-panel form').size).to eq(1)
      expect(panel_form['action']).to eq(sort_path(field))
      expect(hidden_fields(panel_form)).to eq('_method' => 'patch', 'direction' => 'desc', 'state_hash' => state, 'q' => 'value')
      box = panel_form.at_css('input[type=checkbox][name=confirm][required]')
      expect([box['value'], box['checked']]).to eq(['1', nil])
      expect(panel.css('ul, li')).to be_empty
      [:label_usage_this_project, :label_usage_other_projects, :label_dependency_references,
       :label_affected_child_fields].each do |key|
        expect(panel.text).not_to include(I18n.t(key))
      end
      expect(panel.text).not_to include(field.name)
      expect(panel.text).to include(I18n.t(:text_confirm_cross_project_change))
      expect(panel.text).to include(I18n.t(:text_dcf_sort_confirm, count: 60))
      expect(panel_form.at_css('[type=submit]')['value']).to eq(I18n.t(:button_apply))
      expect(field.reload.possible_values).to eq(labels(60).reverse)

      params = hidden_fields(panel_form).except('_method').merge('confirm' => '1')
      expect { patch sort_path(field), params: params }.to change(events, :count).by(1)
      expect(response).to redirect_to(show_path(field, q: 'value'))
      expect(flash[:notice]).to eq(I18n.t(:notice_values_sorted))
      expect(field.reload.possible_values).to eq(labels(60).sort.reverse)
      expect([rows(field).last.action, rows(field).last.status]).to eq(%w[sort_values success])
    end

    it 'gives the panel no q without a filter and refuses with 409 when the field changed before Apply' do
      field = list_in(:shared, %w[c b a])
      patch sort_path(field), params: { direction: 'asc', state_hash: service.state_hash(field) }
      expect(response).to have_http_status(422)
      fields = hidden_fields(panel_form)
      expect(fields.keys.sort).to eq(%w[_method direction state_hash])
      field.update!(possible_values: %w[c b a d])

      patch sort_path(field), params: fields.except('_method').merge('confirm' => '1')
      expect(response).to have_http_status(409)
      expect(field.reload.possible_values).to eq(%w[c b a d])
    end

    it 'shows the panel for a global enumeration and an already sorted field, and an audited 422 for a bad direction' do
      enum = dcf_enum_field(names: %w[b c a])
      patch sort_path(enum), params: { direction: 'asc' }
      expect(response).to have_http_status(422)
      expect(doc.css('.dcf-confirm-panel form').size).to eq(1)
      expect(CustomFieldEnumeration.where(custom_field_id: enum.id).order(:position).pluck(:name)).to eq(%w[b c a])

      sorted = list_in(:global, %w[a b c])
      patch sort_path(sorted), params: { direction: 'asc' }
      expect(response).to have_http_status(422)
      expect(doc.css('.dcf-confirm-panel').size).to eq(1)

      expect { patch sort_path(sorted), params: { direction: 'up' } }.to change(events, :count).by(1)
      expect(response).to have_http_status(422)
      expect(doc.css('.dcf-confirm-panel')).to be_empty
      expect(doc.at_css('#flash_error').text.strip).to eq(I18n.t(:error_reorder_mismatch))
    end

    it 'refuses confirm[]=1 with the panel (strong params drop it), never a 500' do
      field = list_in(:global, %w[b a])
      patch sort_path(field), params: { 'direction' => 'asc', 'confirm' => ['1'] }
      expect(response).to have_http_status(422)
      expect(doc.css('.dcf-confirm-panel').size).to eq(1)
      patch sort_path(field), params: { 'direction' => 'asc', 'confirm' => { 'a' => '1' } }
      expect(response).to have_http_status(422)
      expect(field.reload.possible_values).to eq(%w[b a])
    end

    it 'keeps the browser question only on a project-only field' do
      [[:project, true], [:global, false], [:shared, false]].each do |scope, asks|
        field = list_in(scope, %w[b a c])
        get show_path(field)
        confirms = sort_forms.map { |form| form.at_css('[data-confirm]')&.[]('data-confirm') }
        expect(confirms).to eq(asks ? [I18n.t(:text_dcf_sort_confirm, count: 3)] * 2 : [nil, nil]), scope.to_s
        expect(doc.css('div.dcf-values-toolbar [data-confirm]').size).to eq(asks ? 2 : 0), scope.to_s
      end
    end

    it 'keeps rename and remove panels with their usage lines (unchanged)' do
      field = list_in(:global, %w[b a])
      patch custom_field_configuration_rename_value_path(project, field), params: { old_value: 'a', new_value: 'z' }
      expect(response).to have_http_status(422)
      expect(doc.css('.dcf-confirm-panel li').map { |li| li.text.squish }.first).to start_with(I18n.t(:label_usage_this_project))
      expect(panel_form['action']).to eq(custom_field_configuration_rename_value_path(project, field))
    end
  end

  # Owner scope: sort only. Drag-and-drop reorder, the enumeration batch
  # save, add and default value save a global field without confirmation.
  describe 'operations without confirmation' do
    it 'reorders, saves enumerations, adds a value and sets the default of a global field without confirm' do
      list = list_in(:global, %w[a b c])
      patch custom_field_configuration_reorder_values_path(project, list), params: { ordered_values: %w[c a b] }
      expect(response).to redirect_to(show_path(list))
      expect(list.reload.possible_values).to eq(%w[c a b])

      post custom_field_configuration_add_value_path(project, list), params: { value: 'd' }
      expect(response).to redirect_to(show_path(list))
      expect(list.reload.possible_values).to eq(%w[c a b d])

      patch custom_field_configuration_set_default_value_path(project, list), params: { default_value: 'd' }
      expect(response).to redirect_to(show_path(list))
      expect(list.reload.default_value).to eq('d')

      enum = dcf_enum_field(names: %w[X Y])
      rows_param = enum.enumerations.order(:position).each_with_index.to_h do |e, i|
        [e.id.to_s, { name: e.name, position: (2 - i).to_s, active: '1' }]
      end
      patch custom_field_configuration_update_enumerations_path(project, enum), params: { enumerations: rows_param }
      expect(response).to redirect_to(show_path(enum))
      expect(CustomFieldEnumeration.where(custom_field_id: enum.id).order(:position).pluck(:name)).to eq(%w[Y X])
      expect(events.where(custom_field_id: [list.id, enum.id]).pluck(:status).uniq).to eq(['success'])
    end
  end

  # SD-16 rule: a role-hidden or out-of-project dependent field is never
  # named, nor any of its values shown, by the new paths.
  describe 'hidden children (security)' do
    let(:other_role) { dcf_create_role }

    def hidden_child(parent, key = 'A')
      child = dcf_list_field(format: 'depending_list', name: "HIDDEN-CHILD-#{SecureRandom.hex(3)}",
                             values: %w[SECRET-V], parent: parent, is_for_all: false, projects: [project])
      dcf_set_dependencies(child, value_dependencies: { key => %w[SECRET-V] })
      child.update!(visible: false, role_ids: [other_role.id])
      child
    end

    def outside_child(parent)
      child = dcf_list_field(format: 'depending_list', name: "HIDDEN-CHILD-OUT-#{SecureRandom.hex(3)}",
                             values: %w[SECRET-V], parent: parent, is_for_all: false, projects: [other])
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[SECRET-V] })
    end

    def expect_unnamed
      expect(response.body).not_to include('HIDDEN-CHILD')
      expect(response.body).not_to include('SECRET-V')
      expect(flash.to_hash.values.join(' ')).not_to include('HIDDEN-CHILD')
    end

    def expect_clean_rows(field)
      rows(field).each do |row|
        expect([row.changes_summary, row.error_message, row.before_value, row.after_value].join(' '))
          .not_to match(/HIDDEN-CHILD|SECRET-V/)
      end
    end

    it 'never names a hidden child of a global parent in the sort panel, the confirmed sort or the flash' do
      [manager, dcf_admin].each do |user|
        allow(User).to receive(:current).and_return(user)
        parent = list_in(:global, %w[B A])
        hidden_child(parent)
        outside_child(parent)
        patch sort_path(parent), params: { direction: 'asc', state_hash: service.state_hash(parent) }
        expect(response).to have_http_status(422)
        expect(doc.css('.dcf-confirm-panel').size).to eq(1)
        expect_unnamed
        params = hidden_fields(panel_form).except('_method').merge('confirm' => '1')
        patch sort_path(parent), params: params
        expect(response).to redirect_to(show_path(parent))
        expect_unnamed
        follow_redirect!
        expect_unnamed
        expect_clean_rows(parent)
      end
    end

    it 'never names a hidden sibling or a hidden grandchild in the dependency confirmation re-render' do
      child = child_in(:shared)
      parent = CustomField.find(child.parent_custom_field_id)
      hidden_child(parent)
      grandchild = hidden_child(child, 'c1')
      get page_path(child)
      expect_unnamed
      save(child, json({ 'B' => %w[c2] }))
      expect(response).to have_http_status(422)
      expect_unnamed
      save(child, json({ 'B' => %w[c2] }), confirm: '1')
      expect(response).to redirect_to(page_path(child))
      expect_unnamed
      expect_clean_rows(child)
      expect(rows(child).last.affected_child_field_ids.to_s).not_to include(grandchild.id.to_s)
    end
  end
end
