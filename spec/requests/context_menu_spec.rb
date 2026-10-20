# frozen_string_literal: true

require_relative '../rails_helper'

# Records every format_store payload deserialized while a log is set, so a
# spec can tell which records were parsed (DcfQueryCounter only counts).
module DcfContextMenuYamlLog
  def load(yaml)
    log = Thread.current[:dcf_context_menu_yaml_log]
    log << yaml if log
    super
  end
end
unless ActiveRecord::Store::IndifferentCoder <= DcfContextMenuYamlLog
  ActiveRecord::Store::IndifferentCoder.prepend(DcfContextMenuYamlLog)
end

# WP-15 (D4): the issue context menu without cache. The core submenus hide
# the depending fields with an effective parent that are available on the
# selection, and their parents (SelectionGraph); the wizard offers a parent
# only when the user may edit it on every selected issue, and nothing below
# a field the user cannot edit (fail closed). The path is /issues/context_menu
# on 5.x/6.x (ContextMenusController#issues) and 7.0
# (ContextMenus::IssuesController#index).
RSpec.describe 'Issue context menu without cache (WP-15)', type: :request do
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }
  let(:graph_class) { RedmineDependingCustomFields::SelectionGraph }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def priority
    IssuePriority.first || IssuePriority.create!(name: 'Normal')
  end

  # A new tracker of +target+ with +fields+ enabled.
  def tracker_with(*fields, target: project)
    tracker = dcf_tracker
    target.trackers << tracker unless target.trackers.include?(tracker)
    fields.each { |field| tracker.custom_fields << field }
    tracker
  end

  def issue_on(tracker, status: nil, target: project)
    target.trackers << tracker unless target.trackers.include?(tracker)
    issue = Issue.new(project: target, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: status || tracker.default_status, priority: priority)
    issue.save!(validate: false)
    issue
  end

  def depending(parent, values: %w[v1 v2], name: nil)
    dcf_list_field(format: 'depending_list', values: values, parent: parent, name: name)
  end

  def post_menu(issues, env: {})
    post '/issues/context_menu', params: { ids: issues.map(&:id) }, env: env
  end

  def open_menu(issues, env: {})
    post_menu(issues, env: env)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def core_folder(menu, field)
    menu.at_css("li.folder.cf_#{field.id}")
  end

  def folder_texts(folder)
    folder.css('ul li a').map { |a| a.text.strip }
  end

  def folder_links(folder)
    folder.css('ul li a').map { |a| [a.text.strip, CGI.unescape(a['href'].to_s)] }
  end

  def wizard_roots(menu)
    menu.css('li.folder.cf-parent').map { |li| li['data-parent-id'].to_i }
  end

  # Ids of the fields in each data-level column of the wizard template.
  def wizard_levels(menu, parent_field)
    template = menu.at_css("template#cf-wizard-#{parent_field.id}")
    return nil unless template

    template.css('div.cf-col').map do |col|
      col.css('select').map { |s| s['name'][/\[(\d+)\]\z/, 1].to_i }
    end
  end

  def select_names(menu)
    menu.css('select').map { |s| s['name'] }
  end

  def none
    I18n.t(:label_none)
  end

  def missing_id
    CustomField.maximum(:id).to_i + 1_000
  end

  # Raw selects of the topology helper (FieldIndex::QUERY_NAME) in the block.
  def field_index_queries(&block)
    count = 0
    callback = lambda do |*, payload|
      count += 1 if payload[:name] == RedmineDependingCustomFields::FieldIndex::QUERY_NAME
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    count
  end

  # The patch and the hook rescue every error (menu unfiltered, no wizard), so
  # the examples of a group that spies on warnings also assert that nothing
  # was rescued, unless tagged dcf_warns.
  def self.fail_on_rescued_errors
    before { allow(Rails.logger).to receive(:warn).and_call_original }
    after do |example|
      expect(Rails.logger).not_to have_received(:warn).with(/\[DCF\]/) unless example.metadata[:dcf_warns]
    end
  end

  describe 'core submenus per selection' do
    fail_on_rescued_errors

    before { as(dcf_admin) }

    it 'hides a chain and an enumeration pair available on the selection and offers their parents in the wizard' do
      parent = dcf_list_field(values: %w[A B])
      child = depending(parent)
      grandchild = depending(child)
      enum_parent = dcf_enum_field
      enum_child = dcf_enum_field(format: 'depending_enumeration', parent: enum_parent)
      tracker = tracker_with(parent, child, grandchild, enum_parent, enum_child)
      menu = open_menu([issue_on(tracker), issue_on(tracker)])

      [parent, child, grandchild, enum_parent, enum_child].each do |field|
        expect(core_folder(menu, field)).to be_nil, field.name
      end
      expect(wizard_roots(menu)).to contain_exactly(parent.id, enum_parent.id)
      expect(wizard_levels(menu, parent)).to eq([[parent.id], [child.id], [grandchild.id]])
      expect(wizard_levels(menu, enum_parent)).to eq([[enum_parent.id], [enum_child.id]])
    end

    it 'brings back a parent whose dependent field is not available on the selection, with its full list' do
      parent = dcf_list_field(values: %w[A B])
      depending(parent)
      menu = open_menu([issue_on(tracker_with(parent))])

      expect(folder_texts(core_folder(menu, parent))).to eq(['A', 'B', none])
      expect(wizard_roots(menu)).to eq([])
    end

    it 'shows dependent fields of a deleted parent, of a parent of another type or family and of themselves as plain lists' do
      dangling = dcf_store_parent(depending(dcf_list_field, values: %w[d1 d2]), missing_id)
      other_type = dcf_store_parent(depending(dcf_list_field, values: %w[t1]), dcf_list_field(type: ProjectCustomField))
      enum = dcf_enum_field(names: %w[E1])
      other_family = dcf_store_parent(depending(dcf_list_field, values: %w[f1]), enum)
      itself = dcf_store_parent(depending(dcf_list_field, values: %w[s1]), nil)
      itself = dcf_store_parent(itself, itself)
      menu = open_menu([issue_on(tracker_with(dangling, other_type, enum, other_family, itself))])

      expect(folder_texts(core_folder(menu, dangling))).to eq(['d1', 'd2', none])
      expect(folder_texts(core_folder(menu, other_type))).to eq(['t1', none])
      expect(folder_texts(core_folder(menu, other_family))).to eq(['f1', none])
      expect(folder_texts(core_folder(menu, itself))).to eq(['s1', none])
      expect(folder_texts(core_folder(menu, enum))).to eq(['E1', none])
      expect(wizard_roots(menu)).to eq([])
    end

    [:list, :enumeration].each do |kind|
      it "shows the members of a stored cycle and the fields below them as plain lists (#{kind})" do
        world = dcf_stored_cycles(kind)
        menu = open_menu([issue_on(tracker_with(world.root, *world.depending))])

        world.depending.each do |field|
          folder = core_folder(menu, field)
          expect(folder).not_to be_nil, field.name
          expect(folder_texts(folder).size).to eq(3), field.name
        end
        expect(folder_texts(core_folder(menu, world.x)).first(2)).to eq(%w[x1 x2])
        expect(wizard_roots(menu)).to eq([])
      end
    end

    it 'hides a child common to the selection whose parent is not on every issue, without a wizard' do
      parent = dcf_list_field
      child = depending(parent)
      menu = open_menu([issue_on(tracker_with(parent, child)), issue_on(tracker_with(child))])

      expect(core_folder(menu, parent)).to be_nil
      expect(core_folder(menu, child)).to be_nil
      expect(wizard_roots(menu)).to eq([])
      expect(select_names(menu)).not_to include("issue[custom_field_values][#{child.id}]")
    end

    it 'hides a parent on every issue whose child is on some issues only, and offers it as a single level' do
      parent = dcf_list_field
      child = depending(parent)
      menu = open_menu([issue_on(tracker_with(parent, child)), issue_on(tracker_with(parent))])

      expect(core_folder(menu, parent)).to be_nil
      expect(core_folder(menu, child)).to be_nil
      expect(wizard_levels(menu, parent)).to eq([[parent.id]])
    end

    it 'keeps a depending field without a parent' do
      parentless = dcf_list_field(format: 'depending_list', values: %w[p1 p2])
      menu = open_menu([issue_on(tracker_with(parentless))])

      expect(folder_texts(core_folder(menu, parentless))).to eq(['p1', 'p2', none])
    end

    it 'removes the __group_* rows of an extended_user field, also with nothing to hide' do
      field = IssueCustomField.new(name: "ExtUser-#{SecureRandom.hex(3)}", field_format: 'extended_user', is_for_all: true)
      field.show_active = '1'
      field.save!
      menu = open_menu([issue_on(tracker_with(field.reload))])
      links = folder_links(core_folder(menu, field))

      expect(links.map(&:first)).to eq(["<< #{I18n.t(:label_me)} >>", dcf_admin.name, none])
      expect(links.map(&:last).grep(/__group_/)).to be_empty
    end
  end

  describe 'wizard availability' do
    let(:parent) { dcf_list_field(values: %w[A B]) }
    let(:child) { depending(parent) }
    let(:tracker) { tracker_with(parent, child) }

    fail_on_rescued_errors

    before { as(dcf_admin) }

    it 'renders no wizard on a closed project and builds no selection graph' do
      issue = issue_on(tracker)
      project.update_column(:status, Project::STATUS_CLOSED)
      expect(graph_class).not_to receive(:new)

      menu = open_menu([issue])
      expect(wizard_roots(menu)).to eq([])
      expect(menu.css('template')).to be_empty
    end

    it 'renders no wizard when one selected issue is in a closed project' do
      closed = dcf_create_project
      other = issue_on(tracker_with(parent, child, target: closed), target: closed)
      closed.update_column(:status, Project::STATUS_CLOSED)

      expect(wizard_roots(open_menu([issue_on(tracker), other]))).to eq([])
    end

    it 'builds no selection graph for a member without the edit permission' do
      viewer = dcf_create_user("viewer-#{SecureRandom.hex(3)}")
      dcf_add_member(viewer, project, dcf_create_role(permissions: [:view_issues]))
      issue = issue_on(tracker)
      as(viewer)
      expect(graph_class).not_to receive(:new)

      menu = open_menu([issue])
      expect(wizard_roots(menu)).to eq([])
      expect(core_folder(menu, parent)).to be_nil
    end

    it 'builds the selection graph once per request for the patch and the hook' do
      expect(graph_class).to receive(:new).once.and_call_original

      expect(wizard_roots(open_menu([issue_on(tracker), issue_on(tracker)]))).to eq([parent.id])
    end

    it 'checks the wizard levels for the user of the edit gate' do
      expect(RedmineDependingCustomFields::ParentDetector).to receive(:wizard_levels)
        .with(parent, kind_of(Array), graph: kind_of(graph_class), user: dcf_admin).and_call_original

      expect(wizard_levels(open_menu([issue_on(tracker)]), parent)).to eq([[parent.id], [child.id]])
    end

    it 'builds no graph and logs no warning for an unknown issue or an issue the user cannot see' do
      issue = issue_on(tracker)
      project.update_column(:is_public, false)
      outsider = dcf_create_user("outsider-#{SecureRandom.hex(3)}")
      expect(graph_class).not_to receive(:new)
      allow(Rails.logger).to receive(:warn).and_call_original

      post '/issues/context_menu', params: { ids: [0] }
      expect(response).to have_http_status(:not_found)
      as(outsider)
      post_menu([issue])
      expect(response).to have_http_status(:forbidden)
      expect(Rails.logger).not_to have_received(:warn).with(/\[DCF\]/)
    end

    it 'renders the menu without a wizard when the wizard fails, and logs only the error class', dcf_warns: true do
      allow(RedmineDependingCustomFields::ParentDetector).to receive(:for_issues).and_raise(RuntimeError, 'secret value')
      allow(Rails.logger).to receive(:warn).and_call_original

      menu = open_menu([issue_on(tracker)])
      expect(wizard_roots(menu)).to eq([])
      expect(response.body).not_to include('secret value')
      expect(Rails.logger).to have_received(:warn).with('[DCF] context menu wizard failed: RuntimeError').once
    end
  end

  describe 'wizard form' do
    let(:parent) { dcf_list_field(values: %w[A B]) }
    let(:child) { depending(parent) }
    let(:tracker) { tracker_with(parent, child) }

    before { as(dcf_admin) }

    def form_of(menu)
      menu.at_css("template#cf-wizard-#{parent.id} form.cf-wizard-form")
    end

    it 'posts to the named save route' do
      form = form_of(open_menu([issue_on(tracker)]))

      expect(form['action']).to eq(Rails.application.routes.url_helpers.depending_custom_fields_save_path)
      expect(form['action']).to eq('/depending_custom_fields/save')
      expect(form['method']).to eq('post')
    end

    it 'prefixes the form action with the relative URL root' do
      form = form_of(open_menu([issue_on(tracker)], env: { 'SCRIPT_NAME' => '/redmine' }))

      expect(form['action']).to eq('/redmine/depending_custom_fields/save')
    end

    # Core loads the selection without ORDER BY: ids are compared as sets and
    # the carriers with each other.
    it 'keeps the markup the legacy wizard script reads' do
      issues = [issue_on(tracker), issue_on(tracker)]
      ids = issues.map { |i| i.id.to_s }
      menu = open_menu(issues)
      entry = menu.at_css("li.folder.cf-parent[data-parent-id='#{parent.id}']")
      form = form_of(menu)
      joined = entry['data-issue-ids']

      expect(joined.split(',')).to match_array(ids)
      expect(entry['data-template-id']).to eq("cf-wizard-#{parent.id}")
      expect(entry.at_css('a.submenu')['data-template-id']).to eq("cf-wizard-#{parent.id}")
      expect([form['data-parent-id'], form['data-issue-ids']]).to eq([parent.id.to_s, joined])
      expect(form.css("input[type=hidden][name='ids[]']").map { |i| i['value'] }).to eq(joined.split(','))
      expect(form.at_css("input[type=hidden][name='issue_ids']")['value']).to eq(joined)
      expect(form.at_css("input[type=hidden][name='authenticity_token']")).not_to be_nil
      expect(form.css('div.cf-cols > div.cf-col').map { |col| col['data-level'] }).to eq(%w[0 1])
      field = form.at_css('div.cf-col div.cf-wizard-field')
      expect(field.at_css('span.field-description').text).to eq(parent.name)
      expect(field.at_css('select')['data-field-id']).to eq(parent.id.to_s)
    end

    it 'escapes field names and descriptions exactly once' do
      raw = '<b>"x"&'
      parent.update!(name: raw, description: raw)
      menu = open_menu([issue_on(tracker)])

      expect(response.body).to include('&lt;b&gt;&quot;x&quot;&amp;')
      expect(response.body).not_to include(raw)
      expect(response.body).not_to include('&amp;lt;')
      expect(response.body).not_to include('&amp;quot;')
      expect(menu.at_css("li.cf-parent[data-parent-id='#{parent.id}'] a.submenu").text).to eq(raw)
      expect(form_of(menu).at_css('span.field-description')['title']).to eq(raw)
    end
  end

  describe 'fields the member may edit' do
    let(:role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
    let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
    let(:member) do
      user = dcf_create_user("member-#{SecureRandom.hex(3)}")
      dcf_add_member(user, project, role)
      user
    end
    let(:parent) { dcf_list_field(values: %w[A B], name: "P-#{SecureRandom.hex(3)}") }
    let(:child) { depending(parent, name: "C-#{SecureRandom.hex(3)}") }
    let(:grandchild) { depending(child, name: "G-#{SecureRandom.hex(3)}") }
    let(:tracker) { tracker_with(parent, child, grandchild) }
    let(:other_status) { dcf_issue_status }
    let(:first) { issue_on(tracker) }
    let(:second) { issue_on(tracker, status: other_status) }

    before { as(member) }

    def read_only(field, status)
      WorkflowPermission.create!(tracker_id: tracker.id, old_status_id: status.id, role_id: role.id,
                                 field_name: field.id.to_s, rule: 'readonly')
    end

    def names_of(*fields)
      fields.map { |field| "issue[custom_field_values][#{field.id}]" }
    end

    # Core loads the selection in database order, so each variant creates the
    # issues in its own order: the read-only one gets the lower id once.
    it 'offers no wizard for a parent that is read-only by workflow on one selected issue, whatever the order' do
      read_only(parent, other_status)

      [[nil, other_status], [other_status, nil]].each do |statuses|
        menu = open_menu(statuses.map { |status| issue_on(tracker, status: status) })
        expect(wizard_roots(menu)).to eq([])
        expect(select_names(menu) & names_of(parent, child, grandchild)).to eq([])
        [parent, child, grandchild].each { |field| expect(core_folder(menu, field)).to be_nil }
      end
      expect(wizard_levels(open_menu([first]), parent)).to eq([[parent.id], [child.id], [grandchild.id]])
    end

    it 'offers nothing below a child that is read-only on one selected issue (fail closed)' do
      read_only(child, other_status)
      menu = open_menu([first, second])

      expect(wizard_levels(menu, parent)).to eq([[parent.id]])
      expect(select_names(menu) & names_of(child, grandchild)).to eq([])
      expect(core_folder(menu, child)).to be_nil
      expect(core_folder(menu, grandchild)).to be_nil
    end

    it 'offers only fields core lets the member edit on every selected issue' do
      read_only(grandchild, other_status)
      selection = [first, second]
      menu = open_menu(selection)
      offered = menu.css('template select').map { |s| s['name'][/\[(\d+)\]\z/, 1].to_i }.uniq

      editable = selection.map { |i| Issue.find(i.id).editable_custom_fields(member).map(&:id) }.reduce(:&)
      expect(offered).to eq([parent.id, child.id])
      expect(offered - editable).to eq([])
    end

    it 'never names a dependent field hidden for the member role, nor its values' do
      secret = depending(parent, values: %w[zz-secret], name: 'SecretChildZz')
      secret.update!(visible: false, role_ids: [other_role.id])
      below = depending(secret)
      hidden_root = dcf_list_field(values: %w[zz-root], name: 'SecretRootZz')
      hidden_root.update!(visible: false, role_ids: [other_role.id])
      visible_child = depending(hidden_root)
      [secret, below, hidden_root, visible_child].each { |field| tracker.custom_fields << field }
      menu = open_menu([first, Issue.find(second.id)])

      expect(wizard_roots(menu)).to eq([parent.id])
      expect(wizard_levels(menu, parent)).to eq([[parent.id], [child.id], [grandchild.id]])
      [secret, hidden_root].each do |field|
        ["cf_#{field.id}", "cf-wizard-#{field.id}", "[#{field.id}]", "data-parent-id=\"#{field.id}\""].each do |text|
          expect(response.body).not_to include(text)
        end
      end
      %w[SecretChildZz zz-secret SecretRootZz zz-root].each { |text| expect(response.body).not_to include(text) }
      expect(select_names(menu) & names_of(below, visible_child)).to eq([])
    end
  end

  describe 'cost' do
    before { as(dcf_admin) }

    it 'calls neither Rails.cache nor MappingBuilder nor FieldIndex.load' do
      parent = dcf_list_field
      child = depending(parent)
      offstage = depending(dcf_list_field)
      issues = [issue_on(tracker_with(parent, child, offstage))]
      calls = []
      [:fetch, :read, :write, :delete, :exist?, :fetch_multi, :read_multi, :write_multi].each do |method|
        allow(Rails.cache).to receive(method).and_wrap_original do |original, *args, &block|
          calls << [method, args.first.to_s, caller_locations.map(&:path)]
          original.call(*args, &block)
        end
      end
      expect(RedmineDependingCustomFields::MappingBuilder).not_to receive(:build)
      expect(RedmineDependingCustomFields::FieldIndex).not_to receive(:load)

      menu = open_menu(issues)
      expect(wizard_roots(menu)).to eq([parent.id])
      plugin_root = File.expand_path('../..', __dir__)
      offending = calls.select do |_method, key, paths|
        key.match?(/depending_custom_fields|dcf/) || paths.any? { |path| path.start_with?(plugin_root) && !path.include?('/spec/') }
      end
      expect(offending.map { |method, key, _| [method, key] }).to eq([])
    end

    it 'deserializes no format_store of a hidden child that the wizard does not render, for 1 or 5 of them' do
      results = [1, 5].map do |n|
        children = Array.new(n) { depending(dcf_list_field) }
        issue = issue_on(tracker_with(*children))
        raw = children.map { |c| CustomField.find(c.id).read_attribute_before_type_cast('format_store') }
        post_menu([issue])
        log = []
        Thread.current[:dcf_context_menu_yaml_log] = log
        begin
          count = dcf_count_yaml_loads { open_menu([issue]) }
        ensure
          Thread.current[:dcf_context_menu_yaml_log] = nil
        end
        expect(log & raw).to eq([])
        count
      end

      expect(results.uniq.size).to eq(1)
    end

    it 'adds the same queries for 1 and 10 selected issues (plugin overhead)' do
      role = dcf_create_role(permissions: [:view_issues, :edit_issues])
      member = dcf_create_user("cost-#{SecureRandom.hex(3)}")
      dcf_add_member(member, project, role)
      as(member)
      parent = dcf_list_field
      child = depending(parent)
      tracker = tracker_with(parent, child, depending(child))
      WorkflowPermission.create!(tracker_id: tracker.id, old_status_id: tracker.default_status_id, role_id: role.id,
                                 field_name: 'due_date', rule: 'readonly')
      hook = RedmineDependingCustomFields::Hooks::ContextMenuHook.instance
      empty = graph_class.new([])

      overheads = [1, 10].map do |n|
        issues = Array.new(n) { issue_on(tracker) }
        post_menu(issues)
        with = dcf_count_queries { post_menu(issues) }
        expect(wizard_roots(Nokogiri::HTML(response.body))).to eq([parent.id])
        allow(graph_class).to receive(:new).and_return(empty)
        allow(hook).to receive(:view_issues_context_menu_end).and_return(nil)
        without = dcf_count_queries { post_menu(issues) }
        allow(graph_class).to receive(:new).and_call_original
        allow(hook).to receive(:view_issues_context_menu_end).and_call_original
        with - without
      end

      expect(overheads.uniq.size).to eq(1)
      expect(overheads.first).to eq(0)
    end

    # Queries alone do not show a global scan (one select for all fields), so
    # the format_store deserializations are compared too.
    it 'runs the same queries and deserializations with 5 or 25 custom fields in the system' do
      parent = dcf_list_field
      child = depending(parent)
      issues = [issue_on(tracker_with(parent, child)), issue_on(tracker_with(parent, child))]
      extra = ->(n) { Array.new(n) { depending(depending(dcf_list_field)) } }
      measure = lambda do
        post_menu(issues)
        loads = nil
        queries = dcf_count_queries { loads = dcf_count_yaml_loads { post_menu(issues) } }
        [queries, loads]
      end
      extra.call(5)
      small = measure.call
      extra.call(20)
      large = measure.call

      expect(large).to eq(small)
      expect(wizard_roots(Nokogiri::HTML(response.body))).to eq([parent.id])
    end

    it 'fetches parents and grandparents outside the selection with one query per level, for 5 or 25 children' do
      results = [5, 25].map do |n|
        shallow = issue_on(tracker_with(*Array.new(n) { depending(dcf_list_field) }))
        children = Array.new(n) { depending(depending(dcf_list_field)) }
        deep = issue_on(tracker_with(*children))
        [shallow, deep].each { |issue| post_menu([issue]) }
        shallow_count = field_index_queries { post_menu([shallow]) }
        deep_count = field_index_queries { post_menu([deep]) }
        menu = Nokogiri::HTML(response.body)
        children.each { |c| expect(core_folder(menu, c)).to be_nil }
        [deep_count, deep_count - shallow_count]
      end

      expect(results.map(&:first).uniq.size).to eq(1)
      expect(results.map(&:last)).to eq([1, 1])
    end
  end

  describe 'context-menu code' do
    let(:root) { File.expand_path('../..', __dir__) }

    def source(path)
      File.read(File.join(root, path))
    end

    it 'has no cache, mapping or global field query on the context-menu path, and ParentMenuBuilder is gone' do
      %w[lib/redmine_depending_custom_fields/patches/context_menus_controller_patch.rb
         lib/redmine_depending_custom_fields/hooks/context_menu_hook.rb
         app/models/redmine_depending_custom_fields/parent_detector.rb
         app/models/redmine_depending_custom_fields/selection_graph.rb
         app/views/depending_custom_fields/_context_menu_wizard.html.erb].each do |path|
        expect(source(path)).not_to match(/Rails\.cache|MappingBuilder|ParentMenuBuilder|CustomFieldVisibility|CustomField\.where/), path
      end
      expect(File).not_to exist(File.join(root, 'app/services/redmine_depending_custom_fields/parent_menu_builder.rb'))
      expect(defined?(RedmineDependingCustomFields::ParentMenuBuilder)).to be_nil
      expect(RedmineDependingCustomFields::MappingBuilder).to respond_to(:build)
    end

    it 'keeps CustomFieldVisibility loaded, with no caller in app or lib' do
      callers = Dir[File.join(root, '{app,lib}', '**', '*.{rb,erb}')].select do |path|
        File.read(path).include?('CustomFieldVisibility') || File.read(path).include?('custom_field_visibility')
      end
      expect(callers.map { |path| path.delete_prefix("#{root}/") }).to contain_exactly(
        'lib/redmine_depending_custom_fields.rb', 'lib/redmine_depending_custom_fields/custom_field_visibility.rb'
      )
      expect(RedmineDependingCustomFields::CustomFieldVisibility).to respond_to(:visible_to_user?)
    end
  end

  describe 'time-entry context menu (SD-03, unchanged)' do
    it 'builds no graph and offers the full list of a depending time-entry field' do
      as(dcf_admin)
      parent = dcf_list_field(type: TimeEntryCustomField, values: %w[A B])
      child = dcf_list_field(type: TimeEntryCustomField, format: 'depending_list', values: %w[a1 b1], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      activity = TimeEntryActivity.create!(name: "Dev-#{SecureRandom.hex(3)}", active: true)
      entry = TimeEntry.new(project: project, user: dcf_admin, author: dcf_admin, spent_on: Date.today, hours: 1,
                            activity: activity)
      entry.save!(validate: false)
      expect(graph_class).not_to receive(:new)

      post '/time_entries/context_menu', params: { ids: [entry.id] }
      expect(response).to have_http_status(:ok)
      menu = Nokogiri::HTML(response.body)

      expect(folder_texts(core_folder(menu, child))).to eq(['a1', 'b1', I18n.t(:label_none)])
    end
  end
end

# WP-15 pins (SD-01 tracked separately): the wizard save still requires a
# login, issue visibility and issue editability, and the plan never widens
# it. No User.current stub here: the examples go through Redmine's own
# authentication.
RSpec.describe 'Context menu wizard save gates (WP-15 pins)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:field) { dcf_list_field(values: %w[A B]) }
  let!(:issue) { dcf_real_issue(project, field => 'A') }

  def post_save(target = issue, **options)
    post '/depending_custom_fields/save',
         params: { issue_ids: Array(target).map(&:id).join(','), issue: { custom_field_values: { field.id.to_s => 'B' } } },
         **options
  end

  def stored(target = issue)
    target.reload.custom_field_value(field)
  end

  def log_in(user, password)
    post '/login', params: { username: user.login, password: password }
    expect(response).to have_http_status(:redirect)
    expect(session[:user_id]).to eq(user.id)
  end

  def member_with(permissions, target = project)
    login = "gate-#{SecureRandom.hex(3)}"
    user = User.new(login: login, firstname: 'F', lastname: 'L', mail: "#{login}@example.net", status: User::STATUS_ACTIVE)
    user.password = 'secret-12345'
    user.password_confirmation = 'secret-12345'
    user.save!
    dcf_add_member(user, target, dcf_create_role(permissions: permissions))
    user
  end

  it 'redirects an anonymous browser to the login page and answers 401 to XHR, even when anonymous may edit' do
    Role.anonymous.update!(permissions: [:view_issues, :edit_issues])
    expect(issue.visible?(User.anonymous)).to be(true)

    post_save
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include('/login')
    post_save(issue, xhr: true)
    expect(response).to have_http_status(:unauthorized)
    expect(stored).to eq('A')
  end

  it 'answers 403 to a logged-in user who cannot see one of the issues and writes on none' do
    user = member_with([:view_issues, :edit_issues])
    hidden_project = dcf_create_project
    hidden_project.update_column(:is_public, false)
    hidden = dcf_real_issue(hidden_project, field => 'A')
    log_in(user, 'secret-12345')

    post_save([issue, hidden])
    expect(response).to have_http_status(:forbidden)
    expect([stored(issue), stored(hidden)]).to eq(%w[A A])
  end

  it 'answers 403 to a member without the edit permission and writes nothing' do
    log_in(member_with([:view_issues]), 'secret-12345')

    post_save
    expect(response).to have_http_status(:forbidden)
    expect(stored).to eq('A')
  end

  it 'writes for a member with the edit permission (control)' do
    log_in(member_with([:view_issues, :edit_issues]), 'secret-12345')

    post_save
    expect(response).to have_http_status(:ok)
    expect(stored).to eq('B')
  end

  it 'never authenticates the save with an API key and ignores the session on .json' do
    allow(Setting).to receive(:rest_api_enabled?).and_return(true)
    user = member_with([:view_issues, :edit_issues])
    values = { issue_ids: issue.id.to_s, issue: { custom_field_values: { field.id.to_s => 'B' } } }

    post '/depending_custom_fields/save', params: values.merge(key: user.api_key)
    expect(response).to have_http_status(:redirect)
    post '/depending_custom_fields/save.json', params: values.merge(key: user.api_key)
    expect(response).to have_http_status(:forbidden)
    post '/depending_custom_fields/save.json', params: values, headers: { 'X-Redmine-API-Key' => user.api_key }
    expect(response).to have_http_status(:forbidden)
    log_in(user, 'secret-12345')
    post '/depending_custom_fields/save.json', params: values
    expect(response).to have_http_status(:forbidden)
    expect(stored).to eq('A')
  end

  it 'refuses a save without a valid authenticity token' do
    user = member_with([:view_issues, :edit_issues])
    log_in(user, 'secret-12345')
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      post_save
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    expect(response).to have_http_status(422)
    expect(stored).to eq('A')
  end
end
