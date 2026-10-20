# frozen_string_literal: true

require_relative '../rails_helper'
require_relative '../support/dcf_js_fixtures'
require 'tmpdir'

# WP-16: the only issue-form contract fixture (server design 2.5, quality
# 5.5). Each scenario renders a real page (issue edit, new and copy, bulk
# edit, time-entry bulk edit, the context-menu wizard, project settings,
# user forms) through the plugin overrides, extracts the custom field
# paragraphs, the read-only carriers or the wizard entry inside a minimal
# form scope, and writes or compares test/js/fixtures/markup/<scenario>.html
# (DCF_WRITE_JS_FIXTURES=1). Every id that reaches a fixture comes from the
# fixed ranges (dcf_fixture_record); labels carry no digits. WP-17 reads
# these files in jsdom; WP-18 and WP-19 regenerate them with this spec.
RSpec.describe 'Issue-form markup fixtures (WP-16)', type: :request do
  include DcfJsFixtures
  include DcfStoredCycle
  include ActiveSupport::Testing::TimeHelpers

  fixtures :users

  let(:group) { 'markup' }
  let(:every_field) { %w[data-dcf-context data-dcf-field data-dcf-kind] }
  let(:tricky) do
    ['[x]', 'a]', 'say "hi"', 'semi;colon', 'Ünïcødé ñ', '<b>&"', "O'Brien", 'comma, value', 'a: b', '# hash',
     "tab\tin", '- dash', '</script>', '"><script>alert(x)</script>']
  end

  def self.scenarios
    %w[list_single list_single_required list_multi_select radio radio_required multi_checkbox enumeration
       enumeration_inactive_child enumeration_inactive_parent chain_of_three read_only_parent role_invisible_parent
       parent_unavailable stored_cycle self_parent dangling_parent legacy_value legacy_value_multi
       legacy_parent_value issue_copy new_issue issue_time_entry_prefixes project_form user_form my_account
       bulk_single bulk_multi bulk_required bulk_chain time_entry_bulk wizard_template tricky_values
       read_only_child_carrier role_invisible_child hide_when_disabled bulk_hide_when_disabled]
  end

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def admin
    User.find(1)
  end

  def priority
    IssuePriority.first || IssuePriority.create!(name: 'Normal')
  end

  def dcf_names(node)
    node.attribute_nodes.map(&:name).grep(/\Adata-dcf-/).sort
  end

  # ---- records with fixed ids -------------------------------------------

  def fx_world
    status = dcf_fixture_record(IssueStatus, { name: 'Fixture new', is_closed: false })
    tracker = dcf_fixture_record(Tracker, { name: 'Fixture tracker' }) { |t| t.default_status = status }
    project = dcf_fixture_record(Project, { name: 'Fixture project', identifier: 'dcf-fixture-project' },
                                 validate: false)
    project.enabled_module_names = %w[issue_tracking time_tracking]
    project.trackers = [tracker]
    role = dcf_fixture_record(Role, { name: 'Fixture member role',
                                      permissions: [:view_issues, :add_issues, :edit_issues, :copy_issues] })
    other_role = dcf_fixture_record(Role, { name: 'Fixture other role', permissions: [:view_issues] })
    member = dcf_fixture_record(User, { login: 'fixturemember', firstname: 'Fixture', lastname: 'Member',
                                        status: User::STATUS_ACTIVE, language: 'en', admin: false }, validate: false)
    Member.create!(principal: member, project: project, roles: [role])
    { status: status, tracker: tracker, project: project, role: role, other_role: other_role, member: member }
  end

  def fx_list(world, name, values, format: 'list', parent: nil, type: IssueCustomField, on_tracker: true, **options)
    field = dcf_fixture_record(type, { name: name, field_format: format, possible_values: values, is_for_all: true,
                                       multiple: options.fetch(:multiple, false),
                                       is_required: options.fetch(:required, false) }) do |cf|
      cf.parent_custom_field_id = parent.id if parent
      cf.edit_tag_style = options[:style] if options[:style]
      cf.visible = options.fetch(:visible, true)
    end
    world[:tracker].custom_fields << field if on_tracker && type == IssueCustomField
    CustomField.find(field.id)
  end

  def fx_enum(world, name, names, format: 'enumeration', parent: nil, inactive: [], multiple: false)
    field = dcf_fixture_record(IssueCustomField, { name: name, field_format: format, is_for_all: true,
                                                   multiple: multiple }) do |cf|
      cf.parent_custom_field_id = parent.id if parent
    end
    names.each_with_index do |label, i|
      dcf_fixture_record(CustomFieldEnumeration, { custom_field_id: field.id, name: label, position: i + 1,
                                                   active: !inactive.include?(label) })
    end
    world[:tracker].custom_fields << field
    CustomField.find(field.id)
  end

  def fx_key(field, name)
    return name unless field.field_format.end_with?('enumeration')

    field.enumerations.detect { |e| e.name == name }.id.to_s
  end

  # Stores +links+ (parent name => child names) and +defaults+ (parent name
  # => child name or names) by direct assignment and save!.
  def fx_links(child, parent, links, defaults = {})
    field = CustomField.find(child.id)
    field.value_dependencies = links.to_h { |p, cs| [fx_key(parent, p), cs.map { |c| fx_key(field, c) }] }
    field.default_value_dependencies = defaults.to_h do |p, cs|
      [fx_key(parent, p), cs.is_a?(Array) ? cs.map { |c| fx_key(field, c) } : fx_key(field, cs)]
    end
    field.save!
    CustomField.find(field.id)
  end

  # Parent field (Alpha, Beta, Gamma) and a depending child (Ant, Ape, Bee):
  # Alpha allows Ant and Ape (default Ape), Beta allows Bee, Gamma nothing.
  def fx_pair(world, kind: :list, **child_options)
    if kind == :list
      parent = fx_list(world, 'Parent field', %w[Alpha Beta Gamma])
      child = fx_list(world, 'Child field', %w[Ant Ape Bee], format: 'depending_list', parent: parent, **child_options)
    else
      parent = fx_enum(world, 'Parent field', %w[Alpha Beta Gamma])
      child = fx_enum(world, 'Child field', %w[Ant Ape Bee], format: 'depending_enumeration', parent: parent,
                                                             multiple: child_options.fetch(:multiple, false))
    end
    [parent, fx_links(child, parent, { 'Alpha' => %w[Ant Ape], 'Beta' => %w[Bee] }, 'Alpha' => 'Ape')]
  end

  def fx_issue(world, values)
    issue = dcf_fixture_record(Issue, { project: world[:project], tracker: world[:tracker], subject: 'Fixture issue',
                                        author: admin, status: world[:status], priority: priority },
                               validate: false) do |record|
      record.custom_field_values = values.to_h do |field, names|
        keys = Array(names).map { |n| fx_key(field, n) }
        [field.id.to_s, field.multiple? ? keys : keys.first]
      end
    end
    Issue.find(issue.id)
  end

  def read_only(world, field)
    WorkflowPermission.create!(tracker_id: world[:tracker].id, old_status_id: world[:status].id,
                               role_id: world[:role].id, field_name: field.id.to_s, rule: 'readonly')
  end

  def hide(field, world)
    field.update!(visible: false, role_ids: [world[:other_role].id])
    CustomField.find(field.id)
  end

  # ---- rendering and extraction -----------------------------------------

  def fetch(method, path, user, params = {})
    as(user)
    travel_to(Time.utc(2026, 1, 1)) { send(method, path, params: params) }
    expect(response).to have_http_status(200), "#{method} #{path}"
    Nokogiri::HTML5(response.body)
  end

  def custom_field_paragraphs(scope, prefix)
    return [] unless scope

    scope.css('p').select { |p| p.at_css("[name^='#{prefix}[custom_field_values]']") }
  end

  def serialize_all(nodes)
    nodes.map { |node| "#{dcf_serialize(node)}\n" }.join
  end

  def issue_form(page)
    form = page.at_css('form#issue-form')
    attributes = form.at_css('#all_attributes')
    html = +"<form id=\"issue-form\">\n<div id=\"all_attributes\">\n"
    html << serialize_all(custom_field_paragraphs(attributes, 'issue'))
    html << serialize_all(attributes.css('[data-dcf-locked-parent]'))
    html << "</div>\n"
    time = custom_field_paragraphs(form.at_css('fieldset#log_time'), 'time_entry')
    html << "<fieldset id=\"log_time\">\n#{serialize_all(time)}</fieldset>\n" if time.any?
    html << "</form>\n"
  end

  def plain_form(page, prefix, id: nil)
    form = page.css('form').detect { |f| custom_field_paragraphs(f, prefix).any? }
    opening = id ? "<form id=\"#{id}\">" : '<form>'
    "#{opening}\n#{serialize_all(custom_field_paragraphs(form, prefix))}</form>\n"
  end

  def edit_page(issue, user = admin)
    issue_form(fetch(:get, "/issues/#{issue.id}/edit", user))
  end

  def bulk_page(issues, user = admin)
    plain_form(fetch(:get, '/issues/bulk_edit', user, ids: issues.map(&:id)), 'issue', id: 'bulk_edit_form')
  end

  # ---- scenarios ------------------------------------------------------------

  def scenario_list_single
    world = fx_world
    parent, child = fx_pair(world)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'))
  end

  def scenario_list_single_required
    world = fx_world
    parent, child = fx_pair(world, required: true)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'))
  end

  def scenario_list_multi_select
    world = fx_world
    parent, child = fx_pair(world, multiple: true)
    edit_page(fx_issue(world, parent => 'Alpha', child => %w[Ant Ape]))
  end

  def scenario_radio
    world = fx_world
    parent, child = fx_pair(world, style: 'check_box')
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'))
  end

  def scenario_radio_required
    world = fx_world
    parent, child = fx_pair(world, style: 'check_box', required: true)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'))
  end

  def scenario_multi_checkbox
    world = fx_world
    parent, child = fx_pair(world, style: 'check_box', multiple: true)
    edit_page(fx_issue(world, parent => 'Alpha', child => %w[Ant]))
  end

  def scenario_enumeration
    world = fx_world
    parent, child = fx_pair(world, kind: :enumeration)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'))
  end

  # QA-21: a stored inactive child id (Cat, legacy under Alpha), a default on
  # an inactive id (Dog under Alpha) and an inactive id in the map without an
  # option (Dog, not stored).
  def scenario_enumeration_inactive_child
    world = fx_world
    parent = fx_enum(world, 'Parent field', %w[Alpha Beta Gamma])
    child = fx_enum(world, 'Child field', %w[Ant Ape Bee Cat Dog], format: 'depending_enumeration', parent: parent,
                                                                   inactive: %w[Cat Dog])
    child = fx_links(child, parent, { 'Alpha' => %w[Ant Dog], 'Beta' => %w[Bee Cat] }, 'Alpha' => 'Dog',
                                                                                       'Beta' => 'Cat')
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Cat'))
  end

  # QA-21: a stored inactive parent value (Omega).
  def scenario_enumeration_inactive_parent
    world = fx_world
    parent = fx_enum(world, 'Parent field', %w[Alpha Beta Omega], inactive: %w[Omega])
    child = fx_enum(world, 'Child field', %w[Ant Ape Bee], format: 'depending_enumeration', parent: parent)
    child = fx_links(child, parent, { 'Alpha' => %w[Ant Ape], 'Omega' => %w[Bee] })
    edit_page(fx_issue(world, parent => 'Omega', child => 'Bee'))
  end

  def fx_chain(world)
    root = fx_list(world, 'Root field', %w[Alpha Beta])
    middle = fx_list(world, 'Middle field', %w[Ant Ape Bee], format: 'depending_list', parent: root)
    middle = fx_links(middle, root, 'Alpha' => %w[Ant Ape], 'Beta' => %w[Bee])
    leaf = fx_list(world, 'Leaf field', %w[Cub Calf Colt], format: 'depending_list', parent: middle)
    leaf = fx_links(leaf, middle, { 'Ant' => %w[Cub Calf], 'Bee' => %w[Colt] }, 'Ant' => 'Calf')
    [root, middle, leaf]
  end

  def scenario_chain_of_three
    world = fx_world
    root, middle, leaf = fx_chain(world)
    edit_page(fx_issue(world, root => 'Alpha', middle => 'Ant', leaf => 'Cub'))
  end

  def scenario_read_only_parent
    world = fx_world
    parent, child = fx_pair(world)
    read_only(world, parent)
    edit_page(fx_issue(world, parent => 'Beta', child => 'Bee'), world[:member])
  end

  def scenario_role_invisible_parent
    world = fx_world
    parent, child = fx_pair(world)
    parent = hide(parent, world)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'), world[:member])
  end

  def scenario_parent_unavailable
    world = fx_world
    parent, child = fx_pair(world)
    issue = fx_issue(world, parent => 'Alpha', child => 'Bee')
    world[:tracker].custom_fields.delete(parent)
    edit_page(issue)
  end

  def scenario_stored_cycle
    world = fx_world
    x = fx_list(world, 'Cycle field ex', %w[Ant Ape], format: 'depending_list')
    y = fx_list(world, 'Cycle field why', %w[Bee Cat], format: 'depending_list', parent: x)
    x = dcf_store_parent(x, y)
    y = fx_links(y, x, 'Ant' => %w[Bee])
    x = fx_links(x, y, 'Bee' => %w[Ant])
    edit_page(fx_issue(world, x => 'Ant', y => 'Bee'))
  end

  def scenario_self_parent
    world = fx_world
    field = fx_list(world, 'Self field', %w[Ant Ape], format: 'depending_list')
    field = dcf_store_parent(field, field)
    field = fx_links(field, field, 'Ant' => %w[Ant])
    edit_page(fx_issue(world, field => 'Ape'))
  end

  def scenario_dangling_parent
    world = fx_world
    field = fx_list(world, 'Dangling field', %w[Ant Ape], format: 'depending_list')
    field = dcf_store_parent(field, DcfConfigHelpers::DCF_FIXTURE_ID_BASES['CustomField'] + DcfJsFixtures::RANGE_WIDTH - 1)
    edit_page(fx_issue(world, field => 'Ant'))
  end

  def scenario_legacy_value
    world = fx_world
    parent, child = fx_pair(world)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Bee'))
  end

  def scenario_legacy_value_multi
    world = fx_world
    parent, child = fx_pair(world, multiple: true)
    edit_page(fx_issue(world, parent => 'Alpha', child => %w[Ant Bee]))
  end

  def scenario_legacy_parent_value
    world = fx_world
    parent, child = fx_pair(world)
    child = fx_links(child, parent, 'Alpha' => %w[Ant Ape], 'Beta' => %w[Bee], 'Gamma' => %w[Ape])
    issue = fx_issue(world, parent => 'Gamma', child => 'Ape')
    parent.update!(possible_values: %w[Alpha Beta])
    edit_page(issue)
  end

  def scenario_issue_copy
    world = fx_world
    parent, child = fx_pair(world)
    source = fx_issue(world, parent => 'Alpha', child => 'Bee')
    issue_form(fetch(:get, "/projects/#{world[:project].identifier}/issues/#{source.id}/copy", admin))
  end

  def scenario_new_issue
    world = fx_world
    parent, child = fx_pair(world)
    params = { issue: { tracker_id: world[:tracker].id,
                        custom_field_values: { parent.id.to_s => 'Alpha', child.id.to_s => 'Bee' } } }
    issue_form(fetch(:get, "/projects/#{world[:project].identifier}/issues/new", admin, params))
  end

  def scenario_issue_time_entry_prefixes
    world = fx_world
    parent, child = fx_pair(world)
    time_parent = fx_list(world, 'Time parent', %w[Alpha Beta], type: TimeEntryCustomField)
    time_child = fx_list(world, 'Time child', %w[Ant Bee], format: 'depending_list', parent: time_parent,
                                                           type: TimeEntryCustomField)
    fx_links(time_child, time_parent, 'Alpha' => %w[Ant], 'Beta' => %w[Bee])
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Ant'))
  end

  def scenario_project_form
    world = fx_world
    parent = fx_list(world, 'Project parent', %w[Alpha Beta Gamma], type: ProjectCustomField)
    child = fx_list(world, 'Project child', %w[Ant Ape Bee], format: 'depending_list', parent: parent,
                                                             type: ProjectCustomField)
    fx_links(child, parent, 'Alpha' => %w[Ant Ape], 'Beta' => %w[Bee])
    # A fresh instance: the saved world[:project] memoized its custom field
    # values before these fields existed and would drop the assignment.
    project = Project.find(world[:project].id)
    project.custom_field_values = { parent.id.to_s => 'Alpha', child.id.to_s => 'Bee' }
    project.save!(validate: false)
    plain_form(fetch(:get, "/projects/#{project.identifier}/settings", admin), 'project')
  end

  def fx_user_fields(world)
    parent = fx_list(world, 'User parent', %w[Alpha Beta], type: UserCustomField, visible: false)
    child = fx_list(world, 'User child', %w[Ant Bee], format: 'depending_list', parent: parent, type: UserCustomField)
    fx_links(child, parent, 'Alpha' => %w[Ant], 'Beta' => %w[Bee])
    member = User.find(world[:member].id) # fresh, as in scenario_project_form
    member.custom_field_values = { parent.id.to_s => 'Alpha', child.id.to_s => 'Ant' }
    member.save!(validate: false)
    User.find(member.id)
  end

  # QA-23: a parent hidden from non-admins (visible false): managed for an
  # admin (base rule).
  def scenario_user_form
    world = fx_world
    member = fx_user_fields(world)
    plain_form(fetch(:get, "/users/#{member.id}/edit", admin), 'user')
  end

  # QA-23: the same fields on My account for the member: the child is left
  # unmanaged, its parent is shown (editable) but not visible to the member.
  def scenario_my_account
    world = fx_world
    member = fx_user_fields(world)
    plain_form(fetch(:get, '/my/account', member), 'user')
  end

  def scenario_bulk_single
    world = fx_world
    parent, child = fx_pair(world)
    bulk_page([fx_issue(world, parent => 'Alpha', child => 'Ant'), fx_issue(world, parent => 'Beta', child => 'Bee')])
  end

  def scenario_bulk_multi
    world = fx_world
    parent, child = fx_pair(world, multiple: true)
    bulk_page([fx_issue(world, parent => 'Alpha', child => %w[Ant]), fx_issue(world, parent => 'Beta', child => [])])
  end

  def scenario_bulk_required
    world = fx_world
    parent, child = fx_pair(world, required: true)
    bulk_page([fx_issue(world, parent => 'Alpha', child => 'Ant'), fx_issue(world, parent => 'Beta', child => 'Bee')])
  end

  def scenario_bulk_chain
    world = fx_world
    root, middle, leaf = fx_chain(world)
    bulk_page([fx_issue(world, root => 'Alpha', middle => 'Ant', leaf => 'Cub'),
               fx_issue(world, root => 'Beta', middle => 'Bee', leaf => 'Colt')])
  end

  def scenario_time_entry_bulk
    world = fx_world
    parent = fx_list(world, 'Time parent', %w[Alpha Beta], type: TimeEntryCustomField)
    child = fx_list(world, 'Time child', %w[Ant Ape Bee], format: 'depending_list', parent: parent,
                                                         type: TimeEntryCustomField)
    fx_links(child, parent, 'Alpha' => %w[Ant Ape], 'Beta' => %w[Bee])
    activity = TimeEntryActivity.create!(name: 'Fixture activity', active: true)
    entries = Array.new(2) do
      entry = TimeEntry.new(project: world[:project], user: admin, author: admin, spent_on: Date.new(2026, 1, 1),
                            hours: 1, activity: activity)
      entry.save!(validate: false)
      entry
    end
    page = fetch(:get, '/time_entries/bulk_edit', admin, ids: entries.map(&:id))
    plain_form(page, 'time_entry', id: 'bulk_edit_form')
  end

  def scenario_wizard_template
    world = fx_world
    root, middle, leaf = fx_chain(world)
    issue = fx_issue(world, root => 'Alpha', middle => 'Ant', leaf => 'Cub')
    page = fetch(:post, '/issues/context_menu', admin, ids: [issue.id])
    entry = page.at_css("li.cf-parent[data-parent-id='#{root.id}']")
    template = page.at_css("template#cf-wizard-#{root.id}")
    "<div id=\"context-menu\"><ul>\n#{serialize_all([entry, template])}</ul></div>\n"
  end

  def scenario_tricky_values
    world = fx_world
    parent = fx_list(world, 'Parent <b>"&', tricky)
    child = fx_list(world, "Child [x] O'Brien", tricky, format: 'depending_list', parent: parent)
    field = CustomField.find(child.id)
    field.value_dependencies = { tricky[0] => [tricky[1], tricky[2]], tricky[3] => [tricky[5], tricky[13]],
                                 tricky[4] => tricky.last(4), tricky[5] => [tricky[0]] }
    field.default_value_dependencies = { tricky[0] => tricky[1], tricky[5] => tricky[0] }
    field.save!
    edit_page(fx_issue(world, parent => tricky[0], child => tricky[2]))
  end

  # UD-37: the child is read-only by workflow for the member; its stored Bee
  # is a legacy value under Alpha, allowed only by Beta.
  def scenario_read_only_child_carrier
    world = fx_world
    parent, child = fx_pair(world)
    read_only(world, child)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Bee'), world[:member])
  end

  def scenario_role_invisible_child
    world = fx_world
    parent, child = fx_pair(world)
    child = hide(child, world)
    edit_page(fx_issue(world, parent => 'Alpha', child => 'Bee'), world[:member])
  end

  # D3 (WP-17 F16 and B6): hide_when_disabled, the parent value Gamma
  # allows nothing.
  def scenario_hide_when_disabled
    world = fx_world
    parent, child = fx_pair(world)
    child.update!(hide_when_disabled: '1')
    edit_page(fx_issue(world, parent => 'Gamma', child => []))
  end

  def scenario_bulk_hide_when_disabled
    world = fx_world
    parent, child = fx_pair(world)
    child.update!(hide_when_disabled: '1')
    bulk_page([fx_issue(world, parent => 'Alpha', child => 'Ant'), fx_issue(world, parent => 'Gamma', child => [])])
  end

  def render_scenario(name)
    send("scenario_#{name}")
  end

  # One render and its legacy mapping inside a savepoint that is rolled
  # back, with the fixed ids starting again at the start of each range.
  def isolated_render(name)
    html = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      dcf_reset_fixture_ids
      html = dcf_js_normalize(render_scenario(name))
      html += JSON.generate(legacy_mapping)
      raise ActiveRecord::Rollback
    end
    html
  end

  # ---- contract checks ----------------------------------------------------

  # Table rules of server design 2.2 on every field of a fixture.
  def check_contract(name, fragment)
    fields = fragment.css('[data-dcf-field]')
    fields.each do |node|
      names = dcf_names(node)
      label = "#{name}: field #{node['data-dcf-field']}"
      (names & DcfJsFixtures::JSON_ATTRIBUTES).each { |attr| expect { JSON.parse(node[attr]) }.not_to raise_error, label }
      expect(node['data-dcf-hide']).to eq('1'), label if node['data-dcf-hide']
      expect(JSON.parse(node['data-dcf-defaults'])).to be_a(Hash).and(be_present), label if node['data-dcf-defaults']
      multiple = node['multiple'] || node.at_css('input[type=checkbox]')
      expected_every = multiple ? (every_field + ['data-dcf-multiple']).sort : every_field
      expect(names & (every_field + ['data-dcf-multiple'])).to eq(expected_every), label
      expect(%w[select span]).to include(node.name)
      context = node['data-dcf-context']
      expect(%w[form bulk]).to include(context), label
      if node['data-dcf-parent']
        expect(names).to include('data-dcf-parent-name', 'data-dcf-map'), label
        if context == 'form'
          expect(names).to include('data-dcf-parent-values', 'data-dcf-parent-label'), label
        else
          expect(names & %w[data-dcf-parent-values data-dcf-parent-label data-dcf-stored]).to eq([]), label
        end
      else
        expect(names - every_field - ['data-dcf-multiple']).to eq([]), label
      end
    end
    expect(fragment.to_html).not_to match(/data-dcf-(state|blank|required-none|wizard-field)/)
    expect(fragment.css('script')).to be_empty
    fields
  end

  def field_named(fragment, name_part)
    fragment.css('[data-dcf-field]').detect do |node|
      control_name = node['name'] || node.at_css('input[name]')&.[]('name')
      label = node.parent.at_css('label, span.field-description')
      control_name && label && label.text.include?(name_part)
    end
  end

  # The head global the legacy script reads (MappingBuilder, no visibility
  # or editability filter until WP-18) for the scenario's fields, rendered
  # or not (every one is in the fixed range and rolled back per example), so
  # the legacy jsdom suite runs every fixture with its production mapping.
  def legacy_mapping
    RedmineDependingCustomFields::MappingBuilder.build.select { |id, _| dcf_in_fixture_range?(id.to_i, DcfJsFixtures::CF) }
                                                .sort.to_h
  end

  def select_labelled(fragment, text)
    fragment.css('p').detect { |p| p.at_css('label')&.text.to_s.include?(text) }&.at_css('select')
  end

  def scenario_checks
    {
      'read_only_parent' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq(['Beta'])
        expect(node['data-dcf-parent-label']).to eq('Parent field')
        expect(fragment.css("[name*='[custom_field_values][#{node['data-dcf-parent']}]']")).to be_empty
      end,
      'role_invisible_parent' => lambda do |fragment|
        expect(dcf_names(field_named(fragment, 'Child field'))).to eq(every_field)
        expect(fragment.to_html).not_to include('Alpha')
      end,
      'parent_unavailable' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq([])
        expect(JSON.parse(node['data-dcf-stored'])).to eq('child' => [], 'parent' => [])
      end,
      'stored_cycle' => ->(fragment) { expect(fragment.css('[data-dcf-parent]')).to be_empty },
      'self_parent' => ->(fragment) { expect(fragment.css('[data-dcf-parent]')).to be_empty },
      'dangling_parent' => ->(fragment) { expect(fragment.css('[data-dcf-parent]')).to be_empty },
      'legacy_value' => lambda do |fragment|
        expect(JSON.parse(field_named(fragment, 'Child field')['data-dcf-stored'])).to eq('child' => ['Bee'], 'parent' => ['Alpha'])
      end,
      'legacy_value_multi' => lambda do |fragment|
        expect(JSON.parse(field_named(fragment, 'Child field')['data-dcf-stored']))
          .to eq('child' => %w[Ant Bee], 'parent' => ['Alpha'])
      end,
      'legacy_parent_value' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        expect(JSON.parse(node['data-dcf-map'])).to include('Gamma' => ['Ape'])
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq(['Gamma'])
      end,
      'issue_copy' => lambda do |fragment|
        expect(JSON.parse(field_named(fragment, 'Child field')['data-dcf-stored'])).to eq('child' => ['Bee'], 'parent' => ['Alpha'])
      end,
      'new_issue' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        expect(node['data-dcf-stored']).to be_nil
        expect(node.at_css('option[selected]')['value']).to eq('Bee')
      end,
      'enumeration' => lambda do |fragment|
        values = JSON.parse(field_named(fragment, 'Child field')['data-dcf-map']).values.flatten
        expect(values).to all(be_an(Integer))
      end,
      'enumeration_inactive_child' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        cat, dog = %w[Cat Dog].map { |n| CustomFieldEnumeration.find_by(name: n).id }
        expect(JSON.parse(node['data-dcf-map']).values.flatten).to include(cat, dog)
        expect(JSON.parse(node['data-dcf-defaults']).values).to include(dog, cat)
        expect(JSON.parse(node['data-dcf-stored'])['child']).to eq([cat.to_s])
        expect(node.css('option').pluck('value')).to include(cat.to_s)
        expect(node.css('option').pluck('value')).not_to include(dog.to_s)
      end,
      'enumeration_inactive_parent' => lambda do |fragment|
        omega = CustomFieldEnumeration.find_by(name: 'Omega').id.to_s
        node = field_named(fragment, 'Child field')
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq([omega])
        expect(JSON.parse(node['data-dcf-stored'])['parent']).to eq([omega])
      end,
      'issue_time_entry_prefixes' => lambda do |fragment|
        time_child = field_named(fragment, 'Time child')
        expect(time_child['data-dcf-parent-name']).to start_with('time_entry[custom_field_values]')
        expect(time_child['data-dcf-stored']).to be_nil
        expect(field_named(fragment, 'Child field')['data-dcf-parent-name']).to start_with('issue[custom_field_values]')
      end,
      'project_form' => lambda do |fragment|
        node = field_named(fragment, 'Project child')
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq(['Alpha'])
        expect(JSON.parse(node['data-dcf-stored'])).to eq('child' => ['Bee'], 'parent' => ['Alpha'])
        expect(node.at_css('option[selected]')['value']).to eq('Bee')
        expect(select_labelled(fragment, 'Project parent').at_css('option[selected]')['value']).to eq('Alpha')
      end,
      'user_form' => lambda do |fragment|
        node = field_named(fragment, 'User child')
        expect(node['data-dcf-parent']).not_to be_nil
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq(['Alpha'])
        expect(JSON.parse(node['data-dcf-stored'])).to eq('child' => ['Ant'], 'parent' => ['Alpha'])
      end,
      'my_account' => lambda do |fragment|
        node = field_named(fragment, 'User child')
        expect(dcf_names(node)).to eq(every_field)
        expect(node.at_css('option[selected]')['value']).to eq('Ant')
        expect(select_labelled(fragment, 'User parent').at_css('option[selected]')['value']).to eq('Alpha')
      end,
      'bulk_required' => lambda do |fragment|
        expect(field_named(fragment, 'Child field').css('option').pluck('value')).not_to include('__none__')
      end,
      'radio_required' => ->(fragment) { expect(fragment.css('input[data-dcf-blank]')).to be_empty },
      'wizard_template' => lambda do |fragment|
        selects = fragment.css('template select')
        expect(selects.size).to eq(3)
        expect(selects.first['data-dcf-field']).to be_nil # the root is a plain list
        expect(selects.drop(1).pluck('data-dcf-context')).to eq(%w[bulk bulk])
        expect(selects.drop(1).pluck('data-field-id')).to eq(selects.drop(1).pluck('data-dcf-field'))
        expect(selects.drop(1).pluck('data-dcf-parent')).to all(be_present)
      end,
      'tricky_values' => lambda do |fragment|
        node = field_named(fragment, 'Child')
        expect(JSON.parse(node['data-dcf-map']).keys).to include('[x]', 'semi;colon', '<b>&"')
        expect(node['data-dcf-parent-label']).to eq('Parent <b>"&')
      end,
      'read_only_child_carrier' => lambda do |fragment|
        carrier = fragment.at_css('[data-dcf-locked-parent]')
        expect(JSON.parse(carrier['data-dcf-locked-allowed-by'])).to eq([['Beta']])
        expect(JSON.parse(carrier['data-dcf-locked-stored'])).to eq(['Alpha'])
        expect(field_named(fragment, 'Child field')).to be_nil
      end,
      'role_invisible_child' => lambda do |fragment|
        expect(fragment.css('[data-dcf-locked-parent]')).to be_empty
        expect(fragment.to_html).not_to include('Child field')
        expect(fragment.to_html).not_to include('Bee')
      end,
      'hide_when_disabled' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        expect(node['data-dcf-hide']).to eq('1')
        expect(JSON.parse(node['data-dcf-parent-values'])).to eq(['Gamma'])
        expect(JSON.parse(node['data-dcf-map'])).not_to have_key('Gamma')
      end,
      'bulk_hide_when_disabled' => lambda do |fragment|
        node = field_named(fragment, 'Child field')
        expect(node['data-dcf-hide']).to eq('1')
        expect(node['data-dcf-context']).to eq('bulk')
      end
    }
  end

  # ---- examples -----------------------------------------------------------

  scenarios.each do |name|
    it "renders the #{name} scenario as its committed fixture" do
      html = dcf_js_fixture(group, name, render_scenario(name))
      dcf_js_mapping_fixture('legacy_mapping', name, legacy_mapping)
      fragment = dcf_parse_fragment(html)
      check_contract(name, fragment)
      instance_exec(fragment, &scenario_checks[name]) if scenario_checks.key?(name)
      expect(html).not_to match(/[\u2013\u2014]/)
    end
  end

  it 'renders every scenario identically after 37 throwaway rows of each kind (sequence-bump self check)' do
    first = self.class.scenarios.index_with { |name| isolated_render(name) }
    dcf_bump_sequences(37)
    second = self.class.scenarios.index_with { |name| isolated_render(name) }

    first.each { |name, html| expect(second[name]).to eq(html), name }
  end

  it 'has one committed fixture and one legacy mapping per scenario and no other' do
    skip 'compare mode only: the scenario examples are writing the files' if dcf_js_write_fixtures?
    { group => 'html', 'legacy_mapping' => 'json' }.each do |dir, ext|
      paths = Dir[File.join(dcf_js_fixture_dir, dir, '*')]
      files = paths.map { |path| File.basename(path, ".#{ext}").sub(/\.redmine-\d+\.\d+\z/, '') }

      expect(paths.map { |path| File.extname(path) }.uniq).to eq([".#{ext}"])
      expect(files.uniq.sort).to eq(self.class.scenarios.sort), dir
    end
  end

  describe 'the guard' do
    def leak(html)
      expect { dcf_js_guard!(html) }.to raise_error(DcfJsFixtures::LeakedId)
      begin
        dcf_js_guard!(html)
      rescue DcfJsFixtures::LeakedId => e
        e.message
      end
    end

    it 'names the position of a sequence id in an id-bearing place' do
      expect(leak('<p><select name="issue[custom_field_values][123]"></select></p>')).to include('123 at p > select @name')
      expect(leak('<select data-dcf-field="77"></select>')).to include('77', '@data-dcf-field')
      expect(leak('<label for="issue_custom_field_values_88"></label>')).to include('88', '@for')
      expect(leak('<select class="list_cf cf_99"></select>')).to include('99', '@class')
      expect(leak('<li data-issue-ids="5,9300001"></li>')).to include('5 at', 'Issue')
      expect(leak('<span data-dcf-locked-parent="42"></span>')).to include('42')
      expect(leak('<input type="hidden" name="ids[]" value="12">')).to include('12', 'Issue')
      expect(leak('<a href="/issues/31">x</a>')).to include('31', '@href')
      expect(leak('<template id="cf-wizard-13"></template>')).to include('13')
      expect(leak('<select class="depending_enumeration_cf cf_9100001"><option value="77">x</option></select>'))
        .to include('77', 'CustomFieldEnumeration')
      expect(leak('<select data-dcf-map="{&quot;12&quot;:[9200001]}"></select>')).to include('12', 'key')
      expect(leak('<select data-dcf-map="{&quot;a&quot;:[44]}"></select>')).to include('44')
      expect(leak('<span data-dcf-locked-allowed-by="[[&quot;55&quot;]]"></span>')).to include('55')
    end

    it 'checks the field ids and enumeration ids of a legacy mapping' do
      inside = { '9100002' => { parent_id: '9100001', map: { '9200001' => ['9200002'], 'a' => ['b'] }, defaults: {} } }
      expect(dcf_js_guard_mapping!(inside)).to be(true)
      [{ '12' => { parent_id: '9100001', map: {}, defaults: {} } },
       { '9100002' => { parent_id: '13', map: {}, defaults: {} } },
       { '9100002' => { parent_id: '9100001', map: { '14' => [] }, defaults: {} } },
       { '9100002' => { parent_id: '9100001', map: {}, defaults: { 'a' => '15' } } }].each do |mapping|
        expect { dcf_js_guard_mapping!(mapping) }.to raise_error(DcfJsFixtures::LeakedId)
      end
    end

    it 'accepts fixed-range ids and values without digits' do
      html = '<p><label for="issue_custom_field_values_9100001">A</label>' \
             '<select name="issue[custom_field_values][9100001]" id="issue_custom_field_values_9100001" ' \
             'class="depending_enumeration_cf cf_9100001" data-dcf-field="9100001" data-dcf-parent="9100002" ' \
             'data-dcf-map="{&quot;9200001&quot;:[9200002]}"><option value="9200002">x</option></select></p>' \
             '<li data-issue-ids="9300001,9300002"></li><a href="/issues/9300001">x</a>'
      expect(dcf_js_guard!(html)).to be(true)
      expect(dcf_js_guard!('<select data-dcf-map="{&quot;a: b&quot;:[&quot;1.0&quot;]}"></select>')).to be(true)
    end
  end

  # The variant logic of dcf_js_write_or_compare (quality 5.5), on a
  # temporary directory with the version and the mode stubbed.
  describe 'the writer' do
    let(:dir) { Dir.mktmpdir('dcf-js-fixtures') }
    let(:base) { File.join(dir, 'markup', 's.html') }
    let(:variant) { File.join(dir, 'markup', 's.redmine-6.0.html') }

    after { FileUtils.rm_rf(dir) }

    def on(version, write:)
      allow(self).to receive(:dcf_js_fixture_dir).and_return(dir)
      allow(self).to receive(:dcf_js_write_fixtures?).and_return(write)
      allow(self).to receive(:dcf_redmine_version).and_return(version)
    end

    def put(path, text)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end

    def files
      Dir[File.join(dir, 'markup', '*')].map { |path| File.basename(path) }.sort
    end

    it 'writes only the base file on the base version' do
      on('7.0', write: true)

      expect(dcf_js_write_or_compare('markup', 's', "A\n", 'html')).to eq("A\n")
      expect(files).to eq(['s.html'])
      expect(File.read(base)).to eq("A\n")
    end

    it 'removes a stale variant on another version when the output equals the base, else writes only the variant' do
      put(base, "A\n")
      put(variant, "old\n")
      on('6.0', write: true)

      dcf_js_write_or_compare('markup', 's', "A\n", 'html')
      expect(files).to eq(['s.html'])
      dcf_js_write_or_compare('markup', 's', "B\n", 'html')
      expect(files).to eq(['s.html', 's.redmine-6.0.html'])
      expect([File.read(base), File.read(variant)]).to eq(["A\n", "B\n"])
      FileUtils.rm_f(base)
      dcf_js_write_or_compare('markup', 's', "C\n", 'html')
      expect(files).to eq(['s.redmine-6.0.html'])
    end

    it 'compares against the variant of the running version when it exists, else the base' do
      put(base, "A\n")
      on('6.0', write: false)
      expect(dcf_js_write_or_compare('markup', 's', "A\n", 'html')).to eq("A\n")
      expect { dcf_js_write_or_compare('markup', 's', "B\n", 'html') }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError, %r{markup/s\.html differs})

      put(variant, "B\n")
      expect(dcf_js_write_or_compare('markup', 's', "B\n", 'html')).to eq("B\n")
      expect { dcf_js_write_or_compare('markup', 's', "A\n", 'html') }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError, /s\.redmine-6\.0\.html differs/)
      on('6.1', write: false)
      expect(dcf_js_write_or_compare('markup', 's', "A\n", 'html')).to eq("A\n")
      expect(files).to eq(['s.html', 's.redmine-6.0.html'])
    end

    it 'fails on a missing fixture in compare mode' do
      on('7.0', write: false)

      expect { dcf_js_write_or_compare('markup', 'none', "A\n", 'html') }
        .to raise_error(RuntimeError, %r{missing fixture .*markup/none\.html: run with DCF_WRITE_JS_FIXTURES=1})
      expect { dcf_js_mapping_fixture('legacy_mapping', 'none', {}) }.to raise_error(RuntimeError, /none\.json/)
    end
  end

  describe 'the normalizer' do
    it 'scrubs tokens, state hashes and asset digests and keeps values untouched' do
      digest = 'a' * 64
      html = '<input type="hidden" name="authenticity_token" value="abc"><meta name="csrf-token" content="xyz">' \
             '<input type="hidden" name="state_hash" value="0123abcd">' \
             "<script src=\"/assets/app-#{digest}.js?1700000000\"></script>" \
             "<select data-dcf-map=\"{&quot;a?123&quot;:[&quot;#{digest}&quot;,&quot;tab\tin&quot;]}\">" \
             '<option value="1.0">a: b</option></select>'
      out = dcf_js_normalize(html)

      expect(out).to include('value="{{TOKEN}}"', 'content="{{TOKEN}}"', 'value="{{STATE_HASH}}"', 'src="/assets/app.js"')
      expect(out).to include("{&quot;a?123&quot;:[&quot;#{digest}&quot;,&quot;tab\tin&quot;]}")
      expect(out).to include('<option value="1.0">a: b</option>')
      expect(dcf_js_normalize(out)).to eq(out)
    end
  end
end
