# frozen_string_literal: true

require_relative '../rails_helper'

# WP-16: the issue-form data contract (server design 2.2) through real
# requests. Parent data reaches the page only for a parent the user can see
# (SP-05), in form, bulk and wizard context; rendering adds no query per
# field for parents the issue carries and no format_store parse (G6); a
# failure leaves the field as core renders it (fail open, BC-12); the
# validation does not depend on the user. UD-37 (resolved on the owner's
# mandate): a visible read-only child gets one hidden carrier element in the
# form scope, a role-invisible child gets nothing at all.
RSpec.describe 'Issue-form data contract (WP-16)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:client) { RedmineDependingCustomFields::ClientData }
  let(:project) { dcf_create_project }
  let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:role) do
    dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :copy_issues, :add_issue_notes,
                                  :edit_project])
  end
  let(:member) do
    user = dcf_create_user("wp16-#{SecureRandom.hex(3)}")
    dcf_add_member(user, project, role)
    user
  end
  let(:every_field) { %w[data-dcf-context data-dcf-field data-dcf-kind] }
  let(:secret) { "Zq#{SecureRandom.hex(4)}" }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def control(page, field)
    page.at_css("[data-dcf-field='#{field.id}']")
  end

  def dcf_names(node)
    node.attribute_nodes.map(&:name).grep(/\Adata-dcf-/).sort
  end

  # The whole page (FM-20b). WP-18: the head script that carried every
  # mapping is gone (SD-15), so nothing is stripped any more; was the page
  # without the window.DependingCustomFieldData script.
  def body_without_mapping
    expect(response.body).not_to include('window.DependingCustomFieldData')
    response.body
  end

  def priority
    IssuePriority.first || IssuePriority.create!(name: 'Normal')
  end

  # The form of an edit.js response (replaceIssueFormWith('...') on its first
  # line), escape_javascript undone.
  def js_form(body)
    escaped = body[/replaceIssueFormWith\('(.*)'\);$/, 1]
    expect(escaped).not_to be_nil
    Nokogiri::HTML(escaped.gsub(/\\(.)/) { Regexp.last_match(1) == 'n' ? "\n" : Regexp.last_match(1) })
  end

  # Parent values P1 P2 P3 P4 named after +tag+; P1 allows c1 and c2, P2
  # allows c3, P3 allows nothing, P4 allows c3 and c2.
  def pair(tag: secret, type: IssueCustomField, multiple: false)
    parent = dcf_list_field(values: %W[#{tag}P1 #{tag}P2 #{tag}P3 #{tag}P4], type: type, name: "#{tag}Parent")
    child = dcf_list_field(format: 'depending_list', values: %W[#{tag}c1 #{tag}c2 #{tag}c3], parent: parent,
                           type: type, multiple: multiple, name: "#{tag}Child")
    child = dcf_set_dependencies(child, value_dependencies: { "#{tag}P1" => %W[#{tag}c1 #{tag}c2],
                                                              "#{tag}P2" => %W[#{tag}c3],
                                                              "#{tag}P4" => %W[#{tag}c3 #{tag}c2] })
    [parent, child]
  end

  def hide(field, roles: [other_role])
    field.update!(visible: false, role_ids: roles.map(&:id))
    CustomField.find(field.id)
  end

  def read_only(issue, field, rule_role: role)
    WorkflowPermission.find_or_create_by!(tracker_id: issue.tracker_id, old_status_id: issue.status_id,
                                          role_id: rule_role.id, field_name: field.id.to_s, rule: 'readonly')
  end

  # Issue with +values+ (field => value), stored without validation.
  def stored_issue(values, target = project)
    kit_issue(target, values)
  end

  describe 'parent visibility (SP-05)' do
    it 'emits no parent data on the issue form for a role-invisible parent, the full set for an admin' do
      parent, child = pair
      parent = hide(parent)
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(member)
      ["/issues/#{issue.id}/edit", "/projects/#{project.identifier}/issues/new",
       "/projects/#{project.identifier}/issues/#{issue.id}/copy"].each do |path|
        get path
        expect(response).to have_http_status(200), path
        expect(dcf_names(control(doc, child))).to eq(every_field), path
        expect(body_without_mapping).not_to include('data-dcf-map')
        expect(body_without_mapping).not_to include("#{secret}P")
        expect(body_without_mapping).not_to include("#{secret}Parent")
      end

      as(dcf_admin)
      get "/issues/#{issue.id}/edit"
      expect(dcf_names(control(doc, child))).to include('data-dcf-parent', 'data-dcf-map', 'data-dcf-parent-values',
                                                        'data-dcf-parent-label', 'data-dcf-stored')
    end

    it 'emits the parent data for a member who holds the parent role' do
      parent, child = pair
      parent = hide(parent, roles: [role])
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(member)
      get "/issues/#{issue.id}/edit"
      node = control(doc, child)

      expect(node['data-dcf-parent']).to eq(parent.id.to_s)
      expect(JSON.parse(node['data-dcf-map'])).to eq(RedmineDependingCustomFields::DependencyRules.mapping(child))
    end

    it 'emits no parent data in bulk edit for a role-invisible parent, the full set for an admin' do
      parent, child = pair
      parent = hide(parent)
      issues = [stored_issue(parent => "#{secret}P1", child => "#{secret}c1"),
                stored_issue(parent => "#{secret}P2", child => "#{secret}c3")]
      as(member)
      get '/issues/bulk_edit', params: { ids: issues.map(&:id) }
      expect(response).to have_http_status(200)
      node = control(doc, child)

      expect(node.name).to eq('select')
      expect(node['data-dcf-context']).to eq('bulk')
      expect(dcf_names(node)).to eq(every_field)
      expect(body_without_mapping).not_to include("#{secret}P")

      as(dcf_admin)
      get '/issues/bulk_edit', params: { ids: issues.map(&:id) }
      node = control(doc, child)
      expect(dcf_names(node)).to eq((every_field + %w[data-dcf-parent data-dcf-parent-name data-dcf-map]).sort)
    end

    it 'gates bulk edit on every selected project' do
      second = dcf_create_project
      other_member_role = dcf_create_role(permissions: [:view_issues, :edit_issues])
      dcf_add_member(member, second, other_member_role)
      parent, child = pair
      parent = hide(parent, roles: [role])
      first_issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      second_issue = stored_issue({ parent => "#{secret}P1", child => "#{secret}c1" }, second)
      as(member)

      get '/issues/bulk_edit', params: { ids: [first_issue.id] }
      expect(control(doc, child)['data-dcf-parent']).to eq(parent.id.to_s)
      get '/issues/bulk_edit', params: { ids: [first_issue.id, second_issue.id] }
      expect(dcf_names(control(doc, child))).to eq(every_field)
    end

    it 'offers the wizard maps only for parents the member can see' do
      tag = secret
      root = dcf_list_field(values: %W[#{tag}R1 #{tag}R2], name: "#{tag}Root")
      hidden = dcf_list_field(format: 'depending_list', values: %W[#{tag}H1 #{tag}H2], parent: root,
                              name: "#{tag}Hidden")
      hidden = dcf_set_dependencies(hidden, value_dependencies: { "#{tag}R1" => %W[#{tag}H1] })
      below = dcf_list_field(format: 'depending_list', values: %W[#{tag}B1], parent: hidden, name: "#{tag}Below")
      below = dcf_set_dependencies(below, value_dependencies: { "#{tag}H1" => %W[#{tag}B1] })
      visible = dcf_list_field(format: 'depending_list', values: %W[#{tag}V1], parent: root, name: "#{tag}Visible")
      visible = dcf_set_dependencies(visible, value_dependencies: { "#{tag}R1" => %W[#{tag}V1], '<select x>' => %W[#{tag}V1] })
      hidden = hide(hidden)
      issue = stored_issue(root => "#{tag}R1", hidden => "#{tag}H1", below => "#{tag}B1", visible => "#{tag}V1")

      as(member)
      post '/issues/context_menu', params: { ids: [issue.id] }
      expect(response).to have_http_status(200)
      menu = doc
      template = menu.at_css("template#cf-wizard-#{root.id}")
      wizard_select = template.at_css("select[data-dcf-field='#{visible.id}']")
      expect(wizard_select['data-dcf-context']).to eq('bulk')
      expect(wizard_select['data-dcf-parent']).to eq(root.id.to_s)
      # WP-18: no data-field-id any more (was the field id).
      expect(wizard_select['data-field-id']).to be_nil
      expect(wizard_select.ancestors('[data-dcf-wizard-field]').first['data-dcf-wizard-field']).to eq(visible.id.to_s)
      expect(response.body).not_to include("#{tag}H")
      expect(response.body).not_to include("#{tag}Hidden")
      expect(response.body).not_to include("[#{hidden.id}]")
      expect(template.css('[data-dcf-map]').size).to eq(1)

      as(dcf_admin)
      post '/issues/context_menu', params: { ids: [issue.id] }
      template = doc.at_css("template#cf-wizard-#{root.id}")
      # WP-18: one wrapper per field instead of one data-field-id per select.
      expect(template.css("[data-dcf-wizard-field='#{visible.id}']").size).to eq(1)
      expect(response.body).not_to include('data-field-id')
      below_select = template.at_css("select[data-dcf-field='#{below.id}']")
      expect(JSON.parse(below_select['data-dcf-map'])).to eq("#{tag}H1" => %W[#{tag}B1])
      expect(below_select['data-field-id']).to be_nil
      expect(template.css('select[data-dcf-map]').size).to eq(3)
    end

    it 'decides visibility against the project of the re-rendered issue (updateIssueFrom)' do
      second = dcf_create_project
      second.trackers << dcf_issue_infra(project).first
      dcf_add_member(member, second, dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues]))
      parent, child = pair
      parent = hide(parent, roles: [role])
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(member)

      patch "/issues/#{issue.id}/edit.js", params: { issue: { subject: 'S' } }, xhr: true
      expect(response).to have_http_status(200)
      expect(response.body).to include('data-dcf-map')
      patch "/issues/#{issue.id}/edit.js", params: { issue: { project_id: second.id } }, xhr: true
      expect(response).to have_http_status(200)
      expect(response.body).to include("data-dcf-field=\\\"#{child.id}\\\"")
      expect(response.body).not_to include('data-dcf-map')
    end

    # The member holds the parent role in +second+ only, where the parent is
    # read-only by workflow, so core never shows its value to the member.
    def foreign_parent_world
      second = dcf_create_project
      tracker = dcf_issue_infra(project).first
      second.trackers << tracker
      second_role = dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :copy_issues])
      dcf_add_member(member, second, second_role)
      parent, child = pair
      parent = hide(parent, roles: [second_role])
      [second, second_role, parent, child]
    end

    def read_only_everywhere(issue, field, rule_role)
      [issue.status_id, issue.tracker.default_status_id].uniq.each do |status_id|
        WorkflowPermission.find_or_create_by!(tracker_id: issue.tracker_id, old_status_id: status_id,
                                              role_id: rule_role.id, field_name: field.id.to_s, rule: 'readonly')
      end
    end

    # A copy shows the source issue's values (UD-06): the parent must also be
    # visible in the source project (fail closed).
    it 'emits no parent data on a copy whose source project hides the parent' do
      second, second_role, parent, child = foreign_parent_world
      source = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      read_only_everywhere(source, parent, second_role)
      as(member)
      get "/projects/#{second.identifier}/issues/new", params: { copy_from: source.id }
      expect(response).to have_http_status(200)
      node = control(doc, child)

      expect(doc.css("[name='issue[custom_field_values][#{parent.id}]']")).to be_empty
      expect(node).not_to be_nil
      expect(dcf_names(node)).to eq(every_field)
      expect(body_without_mapping).not_to include("#{secret}P")
      expect(body_without_mapping).not_to include('data-dcf-stored')
      expect(body_without_mapping).not_to include('data-dcf-parent-values')

      same = stored_issue({ parent => "#{secret}P1", child => "#{secret}c1" }, second)
      get "/projects/#{second.identifier}/issues/new", params: { copy_from: same.id }
      expect(response).to have_http_status(200)
      expect(JSON.parse(control(doc, child)['data-dcf-stored'])).to eq('child' => ["#{secret}c1"],
                                                                        'parent' => ["#{secret}P1"])
    end

    it 'decides visibility also against the stored project of an issue moved in memory (updateIssueFrom)' do
      second, second_role, parent, child = foreign_parent_world
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      read_only_everywhere(issue, parent, second_role)
      as(member)
      patch "/issues/#{issue.id}/edit.js", params: { issue: { project_id: second.id } }, xhr: true
      expect(response).to have_http_status(200)
      form = js_form(response.body)

      expect(form.css("[name='issue[custom_field_values][#{parent.id}]']")).to be_empty
      expect(dcf_names(control(form, child))).to eq(every_field)
      expect(response.body).not_to include("#{secret}P")
    end

    # QA-23, UD-39 (WP-18): registration shows a user field as a control
    # when the setting shows editable fields or the field is required,
    # whatever its visibility; such a parent counts as visible there.
    # Flipped by WP-18: was 'emits no parent data on the registration form
    # for a parent hidden from non-admins' (base rule).
    it 'emits the parent data on the registration form for a parent hidden from non-admins that core renders there' do
      parent, child = pair(type: UserCustomField)
      parent.update!(visible: false)
      child.update!(is_required: true)
      allow(Setting).to receive(:self_registration?).and_return(true)
      allow(Setting).to receive(:show_custom_fields_on_registration?).and_return(true)
      as(User.anonymous)
      get '/account/register'
      expect(response).to have_http_status(200)
      node = control(doc, child)

      expect(doc.at_css("select[name='user[custom_field_values][#{parent.id}]']")).not_to be_nil
      expect(node['data-dcf-parent']).to eq(parent.id.to_s)
      expect(JSON.parse(node['data-dcf-map'])).to eq(RedmineDependingCustomFields::DependencyRules.mapping(child))
      expect(node['data-dcf-parent-label']).to eq(parent.name)
      expect(node['data-dcf-stored']).to be_nil
    end

    # UD-39 mirrors core's predicate: without the setting, an editable but
    # not required parent is not on the registration page, so nothing of it
    # reaches the page (its name and values stay hidden from visitors).
    it 'emits no parent data on the registration form for a hidden parent that core does not render there' do
      parent, child = pair(type: UserCustomField)
      parent.update!(visible: false)
      child.update!(is_required: true)
      allow(Setting).to receive(:self_registration?).and_return(true)
      allow(Setting).to receive(:show_custom_fields_on_registration?).and_return(false)
      as(User.anonymous)
      get '/account/register'
      expect(response).to have_http_status(200)
      node = control(doc, child)

      expect(node).not_to be_nil
      expect(doc.css("[name='user[custom_field_values][#{parent.id}]']")).to be_empty
      expect(dcf_names(node)).to eq(every_field)
      expect(response.body).not_to include('data-dcf-map')
      expect(response.body).not_to include("#{secret}P")
      expect(response.body).not_to include("#{secret}Parent")

      parent.update!(is_required: true)
      get '/account/register'
      expect(control(doc, child)['data-dcf-parent']).to eq(parent.id.to_s)
    end

    # The setting shows editable fields only: a hidden parent that is not
    # editable and not required is not on the page, so none of it leaks.
    it 'emits no parent data on the registration form for a hidden parent that is not editable' do
      parent, child = pair(type: UserCustomField)
      parent.update!(visible: false, editable: false)
      child.update!(is_required: true)
      allow(Setting).to receive(:self_registration?).and_return(true)
      allow(Setting).to receive(:show_custom_fields_on_registration?).and_return(true)
      as(User.anonymous)
      get '/account/register'
      expect(response).to have_http_status(200)
      node = control(doc, child)

      expect(node).not_to be_nil
      expect(doc.css("[name='user[custom_field_values][#{parent.id}]']")).to be_empty
      expect(dcf_names(node)).to eq(every_field)
      expect(response.body).not_to include('data-dcf-map')
      expect(response.body).not_to include("#{secret}P")
    end

    # QA-23, UD-39 (WP-18): My account renders an editable user field
    # whatever its visibility, so a parent hidden from non-admins counts as
    # visible there; the roles of a user field are still ignored. Flipped by
    # WP-18: was 'emits no parent data on My account for a parent hidden
    # from non-admins, also with roles the user holds' (base rule).
    it 'emits the parent data on My account for an editable parent hidden from non-admins' do
      parent, child = pair(type: UserCustomField)
      parent.update!(visible: false, role_ids: [role.id])
      person = User.find(member.id)
      person.custom_field_values = { parent.id.to_s => "#{secret}P1", child.id.to_s => "#{secret}c1" }
      person.save!(validate: false)
      as(User.find(person.id)) # a fresh instance: value_was is the stored value
      get '/my/account'
      expect(response).to have_http_status(200)
      parent_select = doc.at_css("select[name='user[custom_field_values][#{parent.id}]']")
      node = control(doc, child)

      expect(parent_select).not_to be_nil
      expect(parent_select.at_css('option[selected]')['value']).to eq("#{secret}P1")
      expect(node['data-dcf-parent']).to eq(parent.id.to_s)
      expect(JSON.parse(node['data-dcf-parent-values'])).to eq(["#{secret}P1"])
      expect(JSON.parse(node['data-dcf-stored'])).to eq('child' => ["#{secret}c1"], 'parent' => ["#{secret}P1"])
      expect(node.at_css('option[selected]')['value']).to eq("#{secret}c1")
    end

    it 'emits no parent data on My account for a hidden parent that is not editable there' do
      parent, child = pair(type: UserCustomField)
      parent.update!(visible: false, editable: false)
      person = User.find(member.id)
      person.custom_field_values = { parent.id.to_s => "#{secret}P1", child.id.to_s => "#{secret}c1" }
      person.save!(validate: false)
      as(person)
      get '/my/account'
      expect(response).to have_http_status(200)

      expect(doc.css("[name='user[custom_field_values][#{parent.id}]']")).to be_empty
      expect(dcf_names(control(doc, child))).to eq(every_field)
      expect(response.body).not_to include('data-dcf-map')
      expect(response.body).not_to include("#{secret}P")
    end

    it 'keeps the validation independent of the user: a hidden parent still rejects a disallowed child value' do
      parent, child = pair
      parent = hide(parent)
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(member)
      put "/issues/#{issue.id}", params: { issue: { custom_field_values: { child.id.to_s => "#{secret}c3" } } }

      expect(response).to have_http_status(200)
      expect(doc.css('#errorExplanation').text.downcase).to include(child.name.downcase)
      expect(Issue.find(issue.id).custom_field_value(child)).to eq("#{secret}c1")
    end
  end

  describe 'markup on the issue form' do
    it 'puts the attributes on the select, keeps label for= and adds no id' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"
      node = control(doc, child)
      label = node.parent.at_css('label')

      expect(node.name).to eq('select')
      expect(label['for']).to eq(node['id'])
      expect(node['data-dcf-context']).to eq('form')
      expect(node['data-dcf-parent-name']).to eq("issue[custom_field_values][#{parent.id}]")
      expect(JSON.parse(node['data-dcf-parent-values'])).to eq(["#{secret}P1"])
      expect(JSON.parse(node['data-dcf-stored'])).to eq('child' => ["#{secret}c3"], 'parent' => ["#{secret}P1"])
      expect(doc.css("##{node['id']}").size).to eq(1)
      expect(response.body).not_to include('data-dcf-blank')
      expect(response.body).not_to include('data-dcf-required-none')
    end

    it 'keeps the stored baseline in data-dcf-stored when updateIssueFrom posts another parent value' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(member)
      patch "/issues/#{issue.id}/edit.js",
            params: { issue: { custom_field_values: { parent.id.to_s => "#{secret}P2" } } }, xhr: true
      expect(response).to have_http_status(200)
      node = control(js_form(response.body), child)

      expect(JSON.parse(node['data-dcf-parent-values'])).to eq(["#{secret}P2"])
      expect(JSON.parse(node['data-dcf-stored'])).to eq('child' => ["#{secret}c1"], 'parent' => ["#{secret}P1"])
    end

    it 'emits parent values and label for a parent that is read-only by workflow' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P2", child => "#{secret}c3")
      read_only(issue, parent)
      as(member)
      get "/issues/#{issue.id}/edit"
      node = control(doc, child)

      expect(doc.css("[name='issue[custom_field_values][#{parent.id}]']")).to be_empty
      expect(JSON.parse(node['data-dcf-parent-values'])).to eq(["#{secret}P2"])
      expect(node['data-dcf-parent-label']).to eq(parent.name)
    end

    it 'renders in en and de without a missing translation' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      admin = dcf_admin
      as(admin)
      %w[en de].each do |language|
        admin.language = language
        get "/issues/#{issue.id}/edit"
        expect(response).to have_http_status(200)
        expect(response.body).not_to include('translation missing')
        expect(response.body).not_to include('translation_missing')
        expect(control(doc, child)['data-dcf-map']).not_to be_nil
      end
    end
  end

  describe 'fail open (BC-12)' do
    it 'renders the field as core does when ClientData fails, and logs the class only' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(dcf_admin)
      allow(RedmineDependingCustomFields::DependencyRules).to receive(:mapping).and_raise(RuntimeError, 'sql secret')
      allow(Rails.logger).to receive(:warn).and_call_original
      get "/issues/#{issue.id}/edit"

      expect(response).to have_http_status(200)
      select = doc.at_css("select#issue_custom_field_values_#{child.id}")
      expect(select).not_to be_nil
      expect(dcf_names(select)).to eq([])
      expect(Rails.logger).to have_received(:warn).with(/\[DCF\] .*##{child.id}: RuntimeError\z/)
      expect(Rails.logger).not_to have_received(:warn).with(/sql secret/)
    end

    it 'renders a field whose stored mapping is not a Hash without any data-dcf-* attribute' do
      parent, child = pair
      store = CustomField.find(child.id).format_store.to_hash.merge('value_dependencies' => %w[corrupt])
      CustomField.where(id: child.id).update_all(['format_store = ?', CustomField.type_for_attribute('format_store').serialize(store)])
      issue = stored_issue(parent => "#{secret}P1", child => [])
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"

      expect(response).to have_http_status(200)
      select = doc.at_css("select#issue_custom_field_values_#{child.id}")
      expect(dcf_names(select)).to eq([])
    end
  end

  describe 'cost (G6)' do
    let(:g6_role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues]) }
    let(:g6_member) do
      user = dcf_create_user("g6-#{SecureRandom.hex(3)}")
      user
    end

    # +children+ depending children with value a1; each depends on its own
    # parent when +distinct+, else all on the first parent. The first parent
    # is role-restricted in every world (core loads its roles either way):
    # to a role the member holds when +member_holds_role+.
    def g6_world(children:, distinct:, member_holds_role: true, parent_on_tracker: true, restricted: true)
      tracker = dcf_tracker
      target = dcf_create_project
      target.trackers << tracker unless target.trackers.include?(tracker)
      dcf_add_member(g6_member, target, g6_role)
      parents = Array.new(distinct ? children : 1) { dcf_list_field(values: %w[A B]) }
      restricted_to = member_holds_role ? g6_role : other_role
      parents[0] = hide(parents[0], roles: [restricted_to]) if restricted
      kids = Array.new(children) do |i|
        parent = distinct ? parents[i] : parents[0]
        child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      end
      carried = parent_on_tracker ? parents + kids : kids
      carried.each { |f| tracker.custom_fields << f }
      issue = Issue.new(project: target, tracker: tracker, subject: 'S', author: dcf_admin,
                        status: tracker.default_status, priority: priority)
      values = parents.to_h { |p| [p.id.to_s, 'A'] }
      kids.each { |c| values[c.id.to_s] = 'a1' }
      issue.custom_field_values = values
      issue.save!(validate: false)
      { issue: Issue.find(issue.id), children: kids, parents: parents }
    end

    # The new issue form on the tracker of a world (core reads the tracker
    # from issue[tracker_id]; the project also has the other worlds' trackers).
    def measure_new(world)
      measure("/projects/#{world[:issue].project.identifier}/issues/new",
              params: { issue: { tracker_id: world[:issue].tracker_id } })
    end

    def measure(path, method: :get, params: {})
      send(method, path, params: params)
      expect(response).to have_http_status(200)
      count = dcf_count_queries { send(method, path, params: params) }
      expect(response).to have_http_status(200)
      count
    end

    def stub_client
      allow(client).to receive(:attributes_for).and_return({})
      allow(client).to receive(:locked_children).and_return([])
      yield
    ensure
      allow(client).to receive(:attributes_for).and_call_original
      allow(client).to receive(:locked_children).and_call_original
    end

    # Database round trips: a repeated SELECT in one request is a query
    # cache hit, which every supported Rails reports with the statement's own
    # name and cached: true (dcf_count_queries counts it).
    def round_trips(&block)
      count = 0
      callback = lambda do |*, payload|
        next if payload[:cached] || payload[:name].to_s.match?(DcfQueryCounter::IGNORED)
        next if payload[:sql].to_s.match?(/\A\s*(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

        count += 1
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
      count
    end

    # Plugin overhead in database round trips: real minus ClientData stubbed.
    def trip_overhead(path, managed:, params: {})
      get path, params: params
      real = round_trips { get path, params: params }
      expect(response).to have_http_status(200)
      expect(doc.css('[data-dcf-map]').size).to eq(managed)
      stubbed = stub_client do
        get path, params: params
        round_trips { get path, params: params }
      end
      expect(response.body).not_to include('data-dcf-field')
      real - stubbed
    end

    def overhead(path, managed:, method: :get, params: {})
      real = measure(path, method: method, params: params)
      expect(doc.css('[data-dcf-map]').size).to eq(managed)
      stubbed = stub_client do
        count = measure(path, method: method, params: params)
        expect(client).to have_received(:attributes_for).at_least(:once)
        count
      end
      expect(response.body).not_to include('data-dcf-field')
      real - stubbed
    end

    [true, false].each do |holds|
      context(holds ? 'for a member holding the restricted parent role' : 'for a member without it') do
        it 'renders the edit and new forms with the same queries for 1 parent and 5 distinct parents' do
          one = g6_world(children: 1, distinct: true, member_holds_role: holds)
          five = g6_world(children: 5, distinct: true, member_holds_role: holds)
          as(g6_member)

          expect(measure("/issues/#{five[:issue].id}/edit")).to eq(measure("/issues/#{one[:issue].id}/edit"))
          hidden = holds ? 0 : 1 # the first parent is restricted
          new_one = measure_new(one)
          expect(doc.css('[data-dcf-map]').size).to eq(1 - hidden)
          new_five = measure_new(five)
          expect(doc.css('[data-dcf-map]').size).to eq(5 - hidden)
          expect(new_five).to eq(new_one)
        end
      end
    end

    it 'renders the edit and new forms with the same queries for 1 and 5 children of one parent' do
      one = g6_world(children: 1, distinct: false)
      five = g6_world(children: 5, distinct: false)
      as(g6_member)

      expect(measure("/issues/#{five[:issue].id}/edit")).to eq(measure("/issues/#{one[:issue].id}/edit"))
      new_one = measure_new(one)
      expect(doc.css('[data-dcf-map]').size).to eq(1)
      new_five = measure_new(five)
      expect(doc.css('[data-dcf-map]').size).to eq(5)
      expect(new_five).to eq(new_one)
    end

    it 'adds no query to the edit form when every parent is on the issue (differential)' do
      world = g6_world(children: 5, distinct: true)
      as(g6_member)

      expect(overhead("/issues/#{world[:issue].id}/edit", managed: 5)).to eq(0)
    end

    it 'adds one database round trip per distinct parent that the issue does not carry' do
      as(g6_member)
      results = [[1, false], [2, false], [2, true]].map do |children, distinct|
        world = g6_world(children: children, distinct: distinct, parent_on_tracker: false, restricted: false)
        trip_overhead("/issues/#{world[:issue].id}/edit", managed: children)
      end

      expect(results).to eq([1, 1, 2])
    end

    it 'adds no format_store deserialization to the edit form (SP-20d)' do
      world = g6_world(children: 3, distinct: true)
      as(g6_member)
      path = "/issues/#{world[:issue].id}/edit"
      get path
      real = dcf_yaml_payloads { get path }
      expect(doc.css('[data-dcf-map]').size).to eq(3)
      stubbed = stub_client do
        get path
        dcf_yaml_payloads { get path }
      end

      expect(real.size).to be > 0
      expect(real.sort).to eq(stubbed.sort)
    end

    it 'renders bulk edit with the same queries for 1 and 5 distinct parents' do
      one = g6_world(children: 1, distinct: true)
      five = g6_world(children: 5, distinct: true)
      as(g6_member)
      path = '/issues/bulk_edit'

      count_one = measure(path, params: { ids: [one[:issue].id] })
      expect(doc.css('[data-dcf-map]').size).to eq(1)
      count_five = measure(path, params: { ids: [five[:issue].id] })
      expect(doc.css('[data-dcf-map]').size).to eq(5)
      expect(count_five).to eq(count_one)
    end

    it 'renders bulk edit with the same queries for 1 and 5 children of one parent' do
      one = g6_world(children: 1, distinct: false)
      five = g6_world(children: 5, distinct: false)
      as(g6_member)
      path = '/issues/bulk_edit'

      count_one = measure(path, params: { ids: [one[:issue].id] })
      expect(doc.css('[data-dcf-map]').size).to eq(1)
      count_five = measure(path, params: { ids: [five[:issue].id] })
      expect(doc.css('[data-dcf-map]').size).to eq(5)
      expect(count_five).to eq(count_one)
    end

    # The statements ClientData runs in bulk context repeat what core's
    # bulk_edit already ran for the same request (available fields, the
    # restricted parent's roles): query cache hits, no round trip.
    it 'adds no database round trip to bulk edit when every parent is available (differential)' do
      world = g6_world(children: 5, distinct: true)
      as(g6_member)

      expect(trip_overhead('/issues/bulk_edit', managed: 5, params: { ids: [world[:issue].id] })).to eq(0)
    end

    it 'adds one database round trip to bulk edit per distinct parent the selected issues do not carry' do
      as(g6_member)
      results = [[1, false], [2, false], [2, true]].map do |children, distinct|
        world = g6_world(children: children, distinct: distinct, parent_on_tracker: false, restricted: false)
        trip_overhead('/issues/bulk_edit', managed: children, params: { ids: [world[:issue].id] })
      end

      expect(results).to eq([1, 1, 2])
    end

    it 'adds the same overhead to bulk edit for 1 and 10 selected issues' do
      world = g6_world(children: 2, distinct: true)
      as(g6_member)
      more = Array.new(9) do
        issue = Issue.new(project: world[:issue].project, tracker: world[:issue].tracker, subject: 'S',
                          author: dcf_admin, status: world[:issue].status, priority: priority)
        issue.custom_field_values = world[:issue].custom_field_values.to_h { |v| [v.custom_field_id.to_s, v.value] }
        issue.save!(validate: false)
        issue
      end
      one = overhead('/issues/bulk_edit', managed: 2, params: { ids: [world[:issue].id] })
      ten = overhead('/issues/bulk_edit', managed: 2, params: { ids: [world[:issue].id] + more.map(&:id) })

      expect(ten).to eq(one)
    end

    it 'adds the same overhead to bulk edit for 1 and 5 distinct parents' do
      one = g6_world(children: 1, distinct: true)
      five = g6_world(children: 5, distinct: true)
      as(g6_member)

      overhead_one = overhead('/issues/bulk_edit', managed: 1, params: { ids: [one[:issue].id] })
      overhead_five = overhead('/issues/bulk_edit', managed: 5, params: { ids: [five[:issue].id] })
      expect(overhead_five).to eq(overhead_one)
    end

    it 'renders time-entry bulk edit with the same queries for 1 and 5 entries' do
      parent = dcf_list_field(values: %w[A B], type: TimeEntryCustomField)
      child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, type: TimeEntryCustomField)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      activity = TimeEntryActivity.create!(name: "Dev-#{SecureRandom.hex(3)}", active: true)
      entries = Array.new(5) do
        entry = TimeEntry.new(project: project, user: dcf_admin, author: dcf_admin, spent_on: Date.new(2026, 1, 1),
                              hours: 1, activity: activity)
        entry.save!(validate: false)
        entry
      end
      as(dcf_admin)
      path = '/time_entries/bulk_edit'

      count_one = measure(path, params: { ids: [entries.first.id] })
      node = control(doc, child)
      expect(node['data-dcf-context']).to eq('bulk')
      expect(node['data-dcf-parent']).to eq(parent.id.to_s)
      expect(node['data-dcf-parent-name']).to eq("time_entry[custom_field_values][#{parent.id}]")
      count_five = measure(path, params: { ids: entries.map(&:id) })
      expect(count_five).to eq(count_one)
    end

    # Time-entry fields do not depend on the project: the selection's
    # projects do not multiply ClientData's statements.
    it 'adds the same overhead to time-entry bulk edit for 1 entry and 5 entries in 5 projects' do
      te_role = dcf_create_role(permissions: [:view_time_entries, :log_time, :edit_time_entries])
      te_user = dcf_create_user("te-#{SecureRandom.hex(3)}")
      parent = dcf_list_field(values: %w[A B], type: TimeEntryCustomField)
      parent.update!(visible: false, role_ids: [te_role.id])
      2.times do
        child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, type: TimeEntryCustomField)
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      end
      activity = TimeEntryActivity.create!(name: "Dev-#{SecureRandom.hex(3)}", active: true)
      entries = Array.new(5) do
        target = dcf_create_project
        dcf_add_member(te_user, target, te_role)
        entry = TimeEntry.new(project: target, user: te_user, author: te_user, spent_on: Date.new(2026, 1, 1),
                              hours: 1, activity: activity)
        entry.save!(validate: false)
        entry
      end
      as(te_user)
      path = '/time_entries/bulk_edit'

      one = overhead(path, managed: 2, params: { ids: [entries.first.id] })
      five = overhead(path, managed: 2, params: { ids: entries.map(&:id) })
      expect(five).to eq(one)
    end

    it 'adds no database round trip to time-entry bulk edit for one or two depending fields (differential)' do
      parent = dcf_list_field(values: %w[A B], type: TimeEntryCustomField)
      activity = TimeEntryActivity.create!(name: "Dev-#{SecureRandom.hex(3)}", active: true)
      entries = Array.new(2) do
        entry = TimeEntry.new(project: project, user: dcf_admin, author: dcf_admin, spent_on: Date.new(2026, 1, 1),
                              hours: 1, activity: activity)
        entry.save!(validate: false)
        entry
      end
      add_child = lambda do
        child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, type: TimeEntryCustomField)
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      end
      as(dcf_admin)
      path = '/time_entries/bulk_edit'
      params = { ids: entries.map(&:id) }

      add_child.call
      one = trip_overhead(path, managed: 1, params: params)
      add_child.call
      two = trip_overhead(path, managed: 2, params: params)
      expect([one, two]).to eq([0, 0])
    end
  end

  # G6 payload budget (C4): the map and defaults of one S1 or S2 child on the
  # issue form, as the escaped attribute bytes of the response. The map is
  # bounded by the stored mapping, so the budget is twice the stored YAML of
  # value_dependencies and default_value_dependencies; the global inline
  # mapping still doubles the page until WP-18.
  describe 'payload budget (G6)' do
    def s1_child(kind)
      parent_values = DcfLargeList.names(27, prefix: 'P')
      child_values = DcfLargeList.names(5570, tricky_every: 97)
      storage = RedmineDependingCustomFields::StorageLimits
      needed = DcfLargeList.yaml_list_bytes(child_values)
      limit = %w[possible_values format_store].filter_map { |c| storage.column_limit(c) }.min
      skip "UD-38: S1 needs #{needed} bytes, the column limit is #{limit} bytes" if limit && limit < needed
      if kind == :list
        parent = dcf_list_field(values: parent_values)
        child = dcf_list_field(format: 'depending_list', values: child_values, parent: parent)
        parent_keys = parent_values
        child_keys = child_values
      else
        parent = dcf_enum_field(names: parent_values)
        child = dcf_enum_field(format: 'depending_enumeration', names: [], parent: parent)
        rows = child_values.each_with_index.map do |name, i|
          { custom_field_id: child.id, name: name, position: i + 1, active: true }
        end
        CustomFieldEnumeration.insert_all(rows)
        parent_keys = parent.enumerations.sort_by(&:position).map { |e| e.id.to_s }
        child_keys = CustomFieldEnumeration.where(custom_field_id: child.id).order(:position).pluck(:id).map(&:to_s)
      end
      mapping = DcfLargeList.partition(parent_keys, child_keys)
      field = CustomField.find(child.id)
      field.value_dependencies = mapping
      field.default_value_dependencies = DcfLargeList.first_child_defaults(mapping)
      field.save!
      [parent, CustomField.find(child.id), parent_keys.first]
    end

    [[:list, 'S1'], [:enumeration, 'S2']].each do |kind, scenario|
      it "keeps the #{scenario} map and defaults within twice their stored YAML", :large do
        parent, child, first_key = s1_child(kind)
        first = kind == :list ? first_key : parent.enumerations.find(first_key.to_i).name
        issue = stored_issue(parent => first, child => [])
        as(dcf_admin)
        get "/issues/#{issue.id}/edit"
        expect(response).to have_http_status(200)
        tag = response.body[/<select[^>]*data-dcf-field="#{child.id}"[^>]*>/]
        bytes = %w[data-dcf-map data-dcf-defaults].sum { |name| tag[/ #{name}="([^"]*)"/, 1].to_s.bytesize }
        type = CustomField.type_for_attribute('format_store')
        stored = type.serialize('value_dependencies' => child.value_dependencies.to_hash,
                                'default_value_dependencies' => child.default_value_dependencies.to_hash).bytesize

        expect(JSON.parse(Nokogiri::HTML(tag).at_css('select')['data-dcf-map']).values.flatten.size).to eq(5570)
        expect(bytes).to be <= 2 * stored
      end
    end
  end

  # UD-37 (resolved on the owner's mandate): a visible read-only child gets
  # one hidden carrier with the parent id, the stored parent baseline and,
  # per stored child value, the parent keys that allow it; the runtime
  # consumer is WP-17. A role-invisible child gets nothing at all.
  describe 'children the user cannot edit (UD-37)' do
    let(:carrier_names) { %w[data-dcf-locked-allowed-by data-dcf-locked-parent data-dcf-locked-stored] }

    def carriers(page = doc)
      page.css('[data-dcf-locked-parent]')
    end

    def carrier_data(node)
      { parent: node['data-dcf-locked-parent'].to_i, stored: JSON.parse(node['data-dcf-locked-stored']),
        allowed_by: JSON.parse(node['data-dcf-locked-allowed-by']) }
    end

    it 'renders one hidden carrier for a child that is read-only by workflow, inside the form scope' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      read_only(issue, child)
      as(member)
      get "/issues/#{issue.id}/edit"
      expect(response).to have_http_status(200)
      nodes = carriers

      expect(nodes.size).to eq(1)
      node = nodes.first
      expect(carrier_data(node)).to eq(parent: parent.id, stored: ["#{secret}P1"],
                                       allowed_by: [["#{secret}P2", "#{secret}P4"]])
      expect(node.name).to eq('span')
      expect(node['hidden']).not_to be_nil
      expect(node['id']).to be_nil
      expect(node['name']).to be_nil
      expect(node['class']).to be_nil
      expect(node.attribute_nodes.map(&:name).sort).to eq((['hidden'] + carrier_names).sort)
      c1 = %w[data-dcf-field data-dcf-context data-dcf-kind data-dcf-multiple data-dcf-parent data-dcf-parent-name
              data-dcf-map data-dcf-defaults data-dcf-hide data-dcf-parent-values data-dcf-parent-label data-dcf-stored]
      expect(carrier_names & c1).to eq([])
      expect(carrier_names.grep(/\Adata-dcf-parent/)).to eq([])
      expect(node.ancestors('form#issue-form').size).to eq(1)
      expect(node.ancestors('#all_attributes').size).to eq(1)
      expect(control(doc, child)).to be_nil
      expect(doc.css('form#issue-form [name]').pluck('name').grep(/locked/)).to eq([])
    end

    # Quality G XSS rule for the carrier, a data-attribute emission point of
    # its own: tricky stored child values and parent keys round-trip, escaped
    # exactly once.
    it 'escapes the tricky values of a carrier exactly once' do
      script = '"><script>alert(1)</script>'
      bold = '<b>&"'
      quote = "O'Brien"
      other = "<i>&'"
      parent = dcf_list_field(values: ['[x]', bold, script, quote], name: "#{secret}Parent")
      child = dcf_list_field(format: 'depending_list', values: [script, other], parent: parent, name: "#{secret}Child")
      child = dcf_set_dependencies(child, value_dependencies: { '[x]' => [other], bold => [script],
                                                                script => [script, other], quote => [other] })
      issue = stored_issue(parent => quote, child => script)
      read_only(issue, child)
      as(member)
      get "/issues/#{issue.id}/edit"
      expect(response).to have_http_status(200)
      raw = response.body[/<span hidden="hidden" data-dcf-locked-parent=[^>]*>/]

      expect(raw).not_to be_nil
      expect(raw).to include('&quot;')
      expect(raw).not_to match(/&amp;(?:quot|lt|gt|amp|#39|#x27);/)
      expect(raw.count('<')).to eq(1)
      expect(response.body).not_to include('<script>alert(1)', '<b>&', '<i>&')
      node = Nokogiri::HTML(raw).at_css('span')
      expect(JSON.parse(node['data-dcf-locked-stored'])).to eq([quote])
      expect(JSON.parse(node['data-dcf-locked-allowed-by'])).to eq([[bold, script]])
      expect(carriers.map { |n| carrier_data(n) }).to eq([{ parent: parent.id, stored: [quote], allowed_by: [[bold, script]] }])
    end

    it 'lists the allowing parent keys per stored value of a multiple child' do
      parent, child = pair(multiple: true)
      issue = stored_issue(parent => "#{secret}P1", child => %W[#{secret}c2 #{secret}c3])
      read_only(issue, child)
      as(member)
      get "/issues/#{issue.id}/edit"

      expect(carriers.map { |n| carrier_data(n) }).to eq(
        [{ parent: parent.id, stored: ["#{secret}P1"],
           allowed_by: [["#{secret}P1", "#{secret}P4"], ["#{secret}P2", "#{secret}P4"]] }]
      )
    end

    it 're-renders the carrier on updateIssueFrom (edit.js)' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      read_only(issue, child)
      as(member)
      patch "/issues/#{issue.id}/edit.js", params: { issue: { custom_field_values: { parent.id.to_s => "#{secret}P2" } } },
                                          xhr: true

      expect(response).to have_http_status(200)
      expect(response.body).to include('replaceIssueFormWith')
      expect(response.body).to include("data-dcf-locked-parent=\\\"#{parent.id}\\\"")
      expect(carriers(js_form(response.body)).map { |n| carrier_data(n) }).to eq(
        [{ parent: parent.id, stored: ["#{secret}P1"], allowed_by: [["#{secret}P2", "#{secret}P4"]] }]
      )
    end

    # Core renders the issue form of edit.js also for a user who may only add
    # notes; its custom fields are not on that form (safe_attribute?).
    it 'renders no carrier for a user who cannot edit the issue attributes' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      notes_role = dcf_create_role(permissions: [:view_issues, :add_issues, :add_issue_notes])
      notes_user = dcf_create_user("notes-#{SecureRandom.hex(3)}")
      dcf_add_member(notes_user, project, notes_role)
      read_only(issue, child)
      read_only(issue, child, rule_role: notes_role)
      path = "/issues/#{issue.id}/edit.js"

      as(member)
      patch path, params: { issue: { notes: 'N' } }, xhr: true
      expect(response).to have_http_status(200)
      expect(carriers(js_form(response.body)).size).to eq(1)

      as(notes_user)
      patch path, params: { issue: { notes: 'N' } }, xhr: true
      expect(response).to have_http_status(200)
      form = js_form(response.body)
      expect(form.css("[name^='issue[custom_field_values]']")).to be_empty
      expect(carriers(form)).to be_empty
      expect(response.body).not_to include('data-dcf-locked')
    end

    it 'renders no carrier for an editable child, a child without a stored value, a new issue or a copy' do
      parent, child = pair
      editable = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      as(member)
      get "/issues/#{editable.id}/edit"
      expect(carriers).to be_empty

      blank = stored_issue(parent => "#{secret}P1", child => [])
      read_only(blank, child)
      get "/issues/#{blank.id}/edit"
      expect(carriers).to be_empty

      get "/projects/#{project.identifier}/issues/new", params: { issue: { tracker_id: blank.tracker_id } }
      expect(response).to have_http_status(200)
      expect(carriers).to be_empty
      source = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      get "/projects/#{project.identifier}/issues/#{source.id}/copy"
      expect(response).to have_http_status(200)
      expect(carriers).to be_empty
    end

    it 'renders no carrier when the parent is hidden, read-only, unavailable, cyclic or dangling' do
      as(member)
      cases = {
        'hidden parent' => lambda do |parent, child, issue|
          hide(parent)
          read_only(issue, child)
        end,
        'read-only parent' => lambda do |parent, child, issue|
          read_only(issue, parent)
          read_only(issue, child)
        end,
        'unavailable parent' => lambda do |parent, child, issue|
          issue.tracker.custom_fields.delete(parent)
          read_only(issue, child)
        end,
        'dangling parent' => lambda do |parent, child, issue|
          dcf_store_parent_pointer(child, CustomField.maximum(:id).to_i + 1_000)
          read_only(issue, child)
          parent
        end,
        'cyclic parent' => lambda do |parent, child, issue|
          dcf_store_parent_pointer(parent, child.id, format: 'depending_list')
          read_only(issue, child)
        end
      }
      cases.each_with_index do |(label, setup), index|
        tag = "#{secret}k#{index}"
        parent, child = pair(tag: tag)
        issue = stored_issue(parent => "#{tag}P1", child => "#{tag}c3")
        setup.call(parent, child, issue)
        get "/issues/#{issue.id}/edit"
        expect(response).to have_http_status(200), label
        expect(carriers).to be_empty, label
      end
    end

    it 'never mentions a role-invisible child: the edit page is byte-identical whatever value it holds' do
      parent, child = pair
      child = hide(child)
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c1")
      as(member)
      get "/issues/#{issue.id}/edit" # the jump box lists the project as recently used from now on
      bodies = ["#{secret}c1", "#{secret}c3"].map do |value|
        CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: child.id)
                   .update_all(value: value)
        get "/issues/#{issue.id}/edit"
        expect(response).to have_http_status(200)
        body = body_without_mapping
        # Flipped by WP-18: the value was in the legacy head script (FM-20b).
        expect(response.body).not_to include(value)
        expect(body).not_to include(value)
        expect(body).not_to include(child.name)
        expect(body).not_to include("[custom_field_values][#{child.id}]")
        expect(body).not_to include("custom_field_values_#{child.id}")
        expect(body).not_to include("cf_#{child.id}")
        expect(body).not_to include("data-dcf-field=\"#{child.id}\"")
        expect(carriers(Nokogiri::HTML(body))).to be_empty
        page = Nokogiri::HTML(body)
        page.css('input[name="authenticity_token"], meta[name="csrf-token"]').each(&:remove)
        page.css('form[name]').each { |form| form['name'] = form['name'].sub(/-\h{8}\z/, '') } # random per render
        page.to_html
      end

      expect(bodies.first).to eq(bodies.last)
    end

    it 'renders no carrier and nothing of a role-invisible child on the project settings page' do
      parent, child = pair(type: ProjectCustomField)
      child = hide(child)
      project.custom_field_values = { parent.id.to_s => "#{secret}P1", child.id.to_s => "#{secret}c3" }
      project.save!(validate: false)
      as(member)
      get "/projects/#{project.identifier}/settings"
      expect(response).to have_http_status(200)
      body = body_without_mapping

      expect(carriers(Nokogiri::HTML(body))).to be_empty
      expect(body).not_to include("#{secret}c3")
      expect(body).not_to include(child.name)
      expect(body).not_to include("[custom_field_values][#{child.id}]")
      expect(Nokogiri::HTML(body).at_css("select[name='project[custom_field_values][#{parent.id}]']")).not_to be_nil
    end

    it 'predicts exactly the parent changes the server refuses' do
      single_parent, single = pair(tag: "#{secret}s")
      multi_parent, multi = pair(tag: "#{secret}m", multiple: true)
      setups = { single => [single_parent, "#{secret}sc3"], multi => [multi_parent, %W[#{secret}mc2 #{secret}mc3]] }
      suffixes = %w[P1 P2 P3 P4]
      as(member)
      setups.each do |child, (parent, value)|
        suffixes.each do |suffix|
          tag = child == single ? "#{secret}s" : "#{secret}m"
          choice = "#{tag}#{suffix}"
          issue = stored_issue(parent => "#{tag}P1", child => value)
          read_only(issue, child)
          get "/issues/#{issue.id}/edit"
          data = carrier_data(carriers.first)
          predicted_refusal = choice != data[:stored].first && data[:allowed_by].any? { |keys| !keys.include?(choice) }

          put "/issues/#{issue.id}", params: { issue: { custom_field_values: { parent.id.to_s => choice } } }
          refused = response.status == 200
          expect(refused).to eq(predicted_refusal), "#{child.name} -> #{choice}"
          expect(response.status).to eq(302) unless refused
        end
      end
    end

    it 'fails open: a carrier error renders the form without carrier and logs the class' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      read_only(issue, child)
      as(member)
      allow(client).to receive(:locked_children).and_raise(RuntimeError, 'secret detail')
      allow(Rails.logger).to receive(:warn).and_call_original
      get "/issues/#{issue.id}/edit"

      expect(response).to have_http_status(200)
      expect(carriers).to be_empty
      expect(Rails.logger).to have_received(:warn).with(/\A\[DCF\] .*RuntimeError\z/)
      expect(Rails.logger).not_to have_received(:warn).with(/secret detail/)
    end

    it 'adds no query and no format_store parse without a read-only depending child, no query with one' do
      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      as(member)
      path = "/issues/#{issue.id}/edit"
      differential = lambda do
        get path
        real = nil
        real_queries = dcf_count_queries { real = dcf_yaml_payloads { get path } }
        rendered = carriers.size
        allow(client).to receive(:locked_children).and_return([])
        get path
        bare = nil
        bare_queries = dcf_count_queries { bare = dcf_yaml_payloads { get path } }
        allow(client).to receive(:locked_children).and_call_original
        [real_queries - bare_queries, real.size - bare.size, rendered]
      end

      expect(differential.call).to eq([0, 0, 0])
      read_only(issue, child)
      queries, loads, rendered = differential.call
      expect(rendered).to eq(1)
      expect(queries).to eq(0)
      expect(loads).to be <= 1
    end

    it 'registers one stateless listener on both form hooks' do
      hook = RedmineDependingCustomFields::Hooks::ReadOnlyCarrierHook.instance
      expect(Redmine::Hook.hook_listeners(:view_issues_form_details_bottom)).to include(hook)
      expect(Redmine::Hook.hook_listeners(:view_projects_form)).to include(hook)

      parent, child = pair
      issue = stored_issue(parent => "#{secret}P1", child => "#{secret}c3")
      read_only(issue, child)
      as(member)
      get "/issues/#{issue.id}/edit"
      expect(carriers.size).to eq(1)
      expect(hook.instance_variables - [:@_routes]).to eq([])
    end
  end

  # Writes +pointer+ as the stored parent of +field+ without callbacks
  # (pointers a save would refuse); +format+ turns a plain list into a
  # depending list first.
  def dcf_store_parent_pointer(field, pointer, format: nil)
    store = CustomField.find(field.id).format_store.to_hash.merge('parent_custom_field_id' => pointer)
    raw = CustomField.type_for_attribute('format_store').serialize(store)
    updates = ['format_store = ?', raw]
    updates = ['format_store = ?, field_format = ?', raw, format] if format
    CustomField.where(id: field.id).update_all(updates)
  end
end
