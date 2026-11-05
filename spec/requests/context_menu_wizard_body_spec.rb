# frozen_string_literal: true

require_relative '../rails_helper'

# WP-36 (UD-13 changed by the owner on 2026-11-02): the context menu holds
# only the wizard entry; context_menu_wizard.js fetches the body from GET
# /depending_custom_fields/wizard (ContextMenuWizardController#show). The
# action applies the rules of the menu (login, every issue visible, the edit
# permission on every project, one SelectionGraph, ParentDetector) and
# answers the same generic 404 for every parent it does not offer, so a
# hidden field is never named and cannot be told from a missing one.
RSpec.describe 'Context menu wizard body (WP-36)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:graph_class) { RedmineDependingCustomFields::SelectionGraph }
  let(:detector) { RedmineDependingCustomFields::ParentDetector }
  let(:path) { '/depending_custom_fields/wizard' }
  let(:parent) { dcf_list_field(values: %w[A B], name: "WizBodyRootZz-#{SecureRandom.hex(3)}") }
  let(:child) { dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, name: "WizBodyChildZz-#{SecureRandom.hex(3)}") }
  let(:tracker) { tracker_with(parent, child) }
  let(:names) { [parent.name, child.name, 'a1', 'b1'] }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def priority
    IssuePriority.first || IssuePriority.create!(name: 'Normal')
  end

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

  def member(permissions, target = project)
    user = dcf_create_user("wiz-#{SecureRandom.hex(3)}")
    dcf_add_member(user, target, dcf_create_role(permissions: permissions))
    user
  end

  def body_form
    Nokogiri::HTML(response.body).at_css('form.cf-wizard-form')
  end

  def levels
    body_form.css('div.cf-col').map { |col| col.css('select').map { |s| s['name'][/\[(\d+)\]\z/, 1].to_i } }
  end

  def expect_no_names(texts = names)
    texts.each { |text| expect(response.body).not_to include(text), text }
    long = texts.select { |text| text.size >= 6 } # short values match random request ids
    response.headers.each_value { |value| long.each { |text| expect(value.to_s).not_to include(text) } }
  end

  # Rack::ETag still adds a weak ETag to a 200 (it does not look at
  # no-store); the body holds a per-request masked token, so it never
  # repeats ('never answers 304' below).
  def no_store
    expect(response.headers['Cache-Control'].to_s).to include('no-store')
    expect(response.headers['Cache-Control'].to_s).not_to match(/public|max-age=[1-9]/)
    expect(response.headers['Last-Modified']).to be_nil
    expect(response.headers['ETag']).to be_nil unless response.status == 200
  end

  describe 'route' do
    it 'reaches the wizard action, never the API show, and names the route' do
      expect(Rails.application.routes.recognize_path(path, method: :get))
        .to include(controller: 'context_menu_wizard', action: 'show')
      expect(Rails.application.routes.url_helpers.depending_custom_fields_wizard_path).to eq(path)
      %w[json xml html js].each do |ext|
        recognized = Rails.application.routes.recognize_path("#{path}.#{ext}", method: :get)
        expect(recognized[:controller]).to eq('context_menu_wizard'), ext
      end
    end
  end

  describe 'body' do
    before { as(dcf_admin) }

    it 'answers the form fragment only, as HTML without layout, never cached' do
      issue = issue_on(tracker)
      dcf_get_wizard(parent.id, [issue.id])

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/html')
      expect(response.body.lstrip).to start_with('<form class="cf-wizard-form"')
      # Changed by WP-39 (R1): the JSON mapping script of the child is the
      # only script (a data block); was no script at all.
      expect(response.body).not_to match(/<html|<head|<body|<template|<li\b/i)
      expect(response.body.scan(/<script\b[^>]*>/i)).to eq(
        ["<script type=\"application/json\" data-dcf-map-id=\"dcf-map-bulk-issue_custom_field_values_#{child.id}\">"]
      )
      expect(Nokogiri::HTML(response.body).css('form').size).to eq(1)
      expect(levels).to eq([[parent.id], [child.id]])
      no_store
    end

    it 'never answers 304 to a conditional request: the ETag of an earlier answer never matches' do
      issue = issue_on(tracker)
      etags = Array.new(3) do
        dcf_get_wizard(parent.id, [issue.id])
        response.headers['ETag']
      end
      expect(etags.compact.uniq.size).to eq(etags.compact.size)

      dcf_get_wizard(parent.id, [issue.id], headers: DcfConfigHelpers::DCF_WIZARD_HEADERS.merge('If-None-Match' => etags.last.to_s))
      expect(response).to have_http_status(:ok)
      expect(response.headers['Last-Modified']).to be_nil
    end

    # Changed by review round 1: the ids keep the requested order (the order
    # of the menu entry's data-issue-ids); was compared with match_array.
    it 'lists the resolved issue ids in ids[], issue_ids and the data attribute, in the requested order' do
      first, second, third = Array.new(3) { issue_on(tracker) }
      requested = [third, first, second].map(&:id)
      dcf_get_wizard(parent.id, requested)
      form = body_form
      inputs = form.css("input[type=hidden][name='ids[]']").map { |input| input['value'] }

      expect(inputs).to eq(requested.map(&:to_s))
      expect(form.at_css("input[type=hidden][name='issue_ids']")['value']).to eq(inputs.join(','))
      expect(form['data-issue-ids']).to eq(inputs.join(','))
      expect(form['data-parent-id']).to eq(parent.id.to_s)
      expect(form['action']).to eq('/depending_custom_fields/save')
      expect(form.at_css("input[type=hidden][name='authenticity_token']")['value']).to be_present
    end

    it 'prefixes the form action with the relative URL root' do
      issue = issue_on(tracker)
      dcf_get_wizard(parent.id, [issue.id], env: { 'SCRIPT_NAME' => '/redmine' })

      expect(body_form['action']).to eq('/redmine/depending_custom_fields/save')
    end

    it 'accepts the ids as a comma string, collapses duplicates and ignores unknown ids next to known ones' do
      issue = issue_on(tracker)
      missing = Issue.maximum(:id).to_i + 1_000
      get path, params: { parent_id: parent.id.to_s, ids: "#{issue.id},#{issue.id},#{missing}" },
                headers: DcfConfigHelpers::DCF_WIZARD_HEADERS

      expect(response).to have_http_status(:ok)
      expect(body_form.css("input[name='ids[]']").map { |i| i['value'] }).to eq([issue.id.to_s])
      dcf_get_wizard(parent.id, [issue.id.to_s] * 2_000)
      expect(response).to have_http_status(:ok)
      expect(body_form.css("input[name='ids[]']").map { |i| i['value'] }).to eq([issue.id.to_s])
      expect(body_form.at_css("input[name='issue_ids']")['value']).to eq(issue.id.to_s)
    end

    it 'escapes field names and descriptions exactly once' do
      raw = '<b>"x"&'
      parent.update!(name: raw, description: raw)
      dcf_get_wizard(parent.id, [issue_on(tracker).id])

      expect(response.body).to include('&lt;b&gt;&quot;x&quot;&amp;')
      expect(response.body).not_to include(raw)
      expect(response.body).not_to include('&amp;lt;')
      expect(body_form.at_css('span.field-description')['title']).to eq(raw)
      expect(body_form.at_css('span.field-description').text).to eq(raw)
    end

    it 'gives a required child core options without (none) and no marker; an optional field keeps (none)' do
      leaf = dcf_list_field(format: 'depending_list', values: %w[x1], parent: child)
      tracker.custom_fields << leaf
      CustomField.find(child.id).update!(is_required: true)
      dcf_get_wizard(parent.id, [issue_on(tracker).id])
      form = body_form

      expect(form.css("select[name='issue[custom_field_values][#{child.id}]'] option").map { |o| o['value'] })
        .to eq(['', 'a1', 'b1'])
      expect(form.css("select[name='issue[custom_field_values][#{leaf.id}]'] option").map { |o| o['value'] })
        .to eq(['', '__none__', 'x1'])
      expect(form.css('[data-dcf-required-none]')).to be_empty
      expect(form.css('option[selected]')).to be_empty
    end

    it 'builds one selection graph and checks the levels for the current user' do
      issues = [issue_on(tracker), issue_on(tracker)]
      expect(graph_class).to receive(:new).once.and_call_original
      expect(detector).to receive(:for_issues)
        .with(kind_of(Array), graph: kind_of(graph_class), user: dcf_admin).once.and_call_original
      expect(detector).to receive(:wizard_levels)
        .with(parent, kind_of(Array), graph: kind_of(graph_class), user: dcf_admin).once.and_call_original

      dcf_get_wizard(parent.id, issues.map(&:id))
      expect(response).to have_http_status(:ok)
    end

    # Review round 1: no per-issue query (visibility, the edit permission and
    # the editable fields of each selected issue are checked without one).
    it 'runs the same number of queries for 2 and for 20 selected issues of one project and tracker' do
      user = member([:view_issues, :edit_issues])
      issues = Array.new(20) { issue_on(tracker) }
      as(user)
      dcf_get_wizard(parent.id, issues.first(2).map(&:id))
      expect(response).to have_http_status(:ok)

      counts = [2, 20].map do |size|
        count = dcf_count_queries { dcf_get_wizard(parent.id, issues.first(size).map(&:id)) }
        expect(response).to have_http_status(:ok)
        expect(body_form.css("input[name='ids[]']").size).to eq(size)
        count
      end
      expect(counts[1]).to eq(counts[0]), counts.inspect
    end

    it 'calls neither Rails.cache nor FieldIndex.load' do
      issue = issue_on(tracker)
      expect(Rails.cache).not_to receive(:fetch)
      expect(Rails.cache).not_to receive(:read)
      expect(Rails.cache).not_to receive(:write)
      expect(RedmineDependingCustomFields::FieldIndex).not_to receive(:load)

      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:ok)
    end

    it 'writes nothing' do
      issue = dcf_real_issue(project, parent => 'A', child => '')
      counts = -> { [Issue.count, CustomValue.count, Journal.count, JournalDetail.count, issue.reload.updated_on] }
      before = counts.call

      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:ok)
      expect(counts.call).to eq(before)
    end
  end

  describe 'parent not offered' do
    let(:viewer_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
    let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
    let(:user) do
      user = dcf_create_user("wizhide-#{SecureRandom.hex(3)}")
      dcf_add_member(user, project, viewer_role)
      user
    end

    it 'answers the same generic 404 for a hidden root, a child, an unknown field and a root without levels' do
      hidden_root = dcf_list_field(values: %w[zz-root], name: 'SecretRootZz')
      hidden_root.update!(visible: false, role_ids: [other_role.id])
      hidden_child = dcf_list_field(format: 'depending_list', values: %w[zz-secret], parent: hidden_root, name: 'SecretChildZz')
      lonely = dcf_list_field(values: %w[L1], name: 'LonelyRootZz')
      lonely_child = dcf_list_field(format: 'depending_list', values: %w[l1], parent: lonely)
      tracker.custom_fields << hidden_root
      tracker.custom_fields << hidden_child
      tracker.custom_fields << lonely
      issue = issue_on(tracker)
      WorkflowPermission.create!(tracker_id: tracker.id, old_status_id: issue.status_id, role_id: viewer_role.id,
                                 field_name: lonely.id.to_s, rule: 'readonly')
      as(user)

      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:ok)
      hidden_texts = %w[SecretRootZz SecretChildZz zz-root zz-secret LonelyRootZz] + [child.name]
      answers = [hidden_root.id, child.id, CustomField.maximum(:id).to_i + 1_000, lonely.id].map do |id|
        dcf_get_wizard(id, [issue.id])
        expect_no_names(hidden_texts)
        no_store
        [response.status, response.body]
      end
      expect(answers.map(&:first).uniq).to eq([404])
      expect(answers.map(&:last).uniq.size).to eq(1)
      expect(lonely_child).to be_present
    end

    it 'never names a dependent field hidden for the role, nor its values, and offers nothing below it' do
      secret = dcf_list_field(format: 'depending_list', values: %w[zz-secret], parent: parent, name: 'SecretChildZz')
      secret.update!(visible: false, role_ids: [other_role.id])
      below = dcf_list_field(format: 'depending_list', values: %w[zz-below], parent: secret, name: 'SecretBelowZz')
      [secret, below].each { |field| tracker.custom_fields << field }
      issue = issue_on(tracker)
      as(user)

      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:ok)
      expect(levels).to eq([[parent.id], [child.id]])
      expect_no_names(%w[SecretChildZz zz-secret SecretBelowZz zz-below])
      [secret, below].each do |field|
        ["[#{field.id}]", "cf_#{field.id}", "=\"#{field.id}\""].each { |text| expect(response.body).not_to include(text) }
      end
    end

    it 'offers nothing below a child that is read-only on one selected issue (fail closed)' do
      other_status = dcf_issue_status
      leaf = dcf_list_field(format: 'depending_list', values: %w[x1], parent: child)
      tracker.custom_fields << leaf
      WorkflowPermission.create!(tracker_id: tracker.id, old_status_id: other_status.id, role_id: viewer_role.id,
                                 field_name: child.id.to_s, rule: 'readonly')
      selection = [issue_on(tracker), issue_on(tracker, status: other_status)]
      as(user)

      dcf_get_wizard(parent.id, selection.map(&:id))
      expect(levels).to eq([[parent.id]])
      editable = selection.map { |i| Issue.find(i.id).editable_custom_fields(user).map(&:id) }.reduce(:&)
      expect(levels.flatten - editable).to eq([])
    end

    it 'fails closed on any error: a generic answer without the error text, only the class logged' do
      issue = issue_on(tracker)
      as(dcf_admin)
      allow(detector).to receive(:for_issues).and_raise(RuntimeError, 'secret value')
      allow(Rails.logger).to receive(:warn).and_call_original
      allow(Rails.logger).to receive(:error).and_call_original

      dcf_get_wizard(parent.id, [issue.id])
      # Changed by review round 1: exactly a 500 without a body; was any
      # status from 400 on.
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to be_blank
      expect(Rails.logger).to have_received(:warn).with('[DCF] context menu wizard failed: RuntimeError').once
      expect(Rails.logger).not_to have_received(:error).with(/secret value/)
      no_store
    end
  end

  # contract: the gate of the menu hook (edit_issues on every project) and
  # core find_issues (404 when no id resolves, 403 when one is not visible).
  describe 'permission matrix' do
    def answer(user, issues)
      as(user) if user
      dcf_get_wizard(parent.id, Array(issues).map(&:id))
      expect_no_names unless response.status == 200
      no_store
      response.status
    end

    it 'answers 200 to a member with the edit permission (control)' do
      expect(answer(member([:view_issues, :edit_issues]), issue_on(tracker))).to eq(200)
    end

    it 'answers 403 to a member without the edit permission' do
      expect(answer(member([:view_issues]), issue_on(tracker))).to eq(403)
    end

    it 'answers 403 to a non-member of a public project' do
      Role.non_member.update!(permissions: [:view_issues])
      expect(answer(dcf_create_user("nm-#{SecureRandom.hex(3)}"), issue_on(tracker))).to eq(403)
    end

    it 'answers 403 for an issue of a private project the user is not a member of' do
      issue = issue_on(tracker)
      project.update_column(:is_public, false)
      expect(answer(dcf_create_user("out-#{SecureRandom.hex(3)}"), issue)).to eq(403)
    end

    it 'answers 403 for an issue the member cannot see although the role may edit issues (own issues only)' do
      issue = issue_on(tracker)
      role = dcf_create_role(permissions: [:view_issues, :edit_issues])
      role.update!(issues_visibility: 'own')
      user = dcf_create_user("own-#{SecureRandom.hex(3)}")
      dcf_add_member(user, project, role)
      expect([issue.visible?(user), user.allowed_to?(:edit_issues, project)]).to eq([false, true])
      expect(answer(user, issue)).to eq(403)
      expect(answer(user, [issue_on(tracker).tap { |i| i.update_column(:author_id, user.id) }, issue])).to eq(403)
    end

    it 'answers 403 to a mixed selection where one project lacks the edit permission, and nothing for the others' do
      other = dcf_create_project
      user = member([:view_issues, :edit_issues])
      dcf_add_member(user, other, dcf_create_role(permissions: [:view_issues]))
      issues = [issue_on(tracker), issue_on(tracker_with(parent, child, target: other), target: other)]
      expect(answer(user, issues)).to eq(403)
    end

    it 'answers 403 on a closed project' do
      user = member([:view_issues, :edit_issues])
      issue = issue_on(tracker)
      project.update_column(:status, Project::STATUS_CLOSED)
      expect(answer(user, issue)).to eq(403)
    end

    it 'answers 403 on an archived project' do
      user = member([:view_issues, :edit_issues])
      issue = issue_on(tracker)
      project.update_column(:status, Project::STATUS_ARCHIVED)
      expect(answer(user, issue)).to eq(403)
    end

    it 'answers 403 when the issue tracking module is disabled' do
      user = member([:view_issues, :edit_issues])
      issue = issue_on(tracker)
      project.enabled_module_names = %w[wiki]
      expect(answer(user, issue)).to eq(403)
    end

    it 'answers 404 when no requested id resolves' do
      as(dcf_admin)
      dcf_get_wizard(parent.id, [Issue.maximum(:id).to_i + 1_000])
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authentication' do
    def log_in(user)
      user.mail = "#{user.login}@example.net"
      user.password = 'secret-12345'
      user.password_confirmation = 'secret-12345'
      user.save!
      post '/login', params: { username: user.login, password: 'secret-12345' }
      expect(session[:user_id]).to eq(user.id)
    end

    it 'redirects an anonymous browser to the login page and answers 401 to XHR, even when anonymous may edit' do
      Role.anonymous.update!(permissions: [:view_issues, :edit_issues])
      issue = issue_on(tracker)
      expect(issue.visible?(User.anonymous)).to be(true)

      get path, params: { parent_id: parent.id.to_s, ids: [issue.id.to_s], back_url: 'http://evil.example/x' }
      expect(response).to have_http_status(:redirect)
      location = URI.parse(response.location)
      expect([location.host, location.path]).to eq(['www.example.com', '/login'])
      expect_no_names
      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:unauthorized)
      expect_no_names
    end

    it 'never authenticates with an API key and never runs the API show for .json or .xml' do
      allow(Setting).to receive(:rest_api_enabled?).and_return(true)
      user = member([:view_issues, :edit_issues])
      issue = issue_on(tracker)
      params = { parent_id: parent.id.to_s, ids: [issue.id.to_s] }
      expect_any_instance_of(DependingCustomFieldsApiController).not_to receive(:show)

      get path, params: params.merge(key: user.api_key), headers: DcfConfigHelpers::DCF_WIZARD_HEADERS
      expect(response).to have_http_status(:unauthorized)
      get path, params: params, headers: DcfConfigHelpers::DCF_WIZARD_HEADERS.merge('X-Redmine-API-Key' => user.api_key)
      expect(response).to have_http_status(:unauthorized)
      log_in(user)
      %w[json xml].each do |ext|
        [params.merge(key: user.api_key), params].each do |query|
          get "#{path}.#{ext}", params: query, headers: { 'X-Redmine-API-Key' => user.api_key }
          expect(response.status).to be_between(400, 499), ext
          expect(response.body).not_to include('cf-wizard')
          expect_no_names
        end
      end
      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:ok)
    end

    it 'puts a token into the form that a save with forgery protection accepts, and refuses a save without it' do
      user = member([:view_issues, :edit_issues])
      issue = dcf_real_issue(project, parent => 'A', child => '')
      log_in(user)
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        dcf_get_wizard(parent.id, [issue.id])
        expect(response).to have_http_status(:ok)
        token = body_form.at_css("input[name='authenticity_token']")['value']
        values = ->(value) { { ids: [issue.id.to_s], issue: { custom_field_values: { parent.id.to_s => value } } } }
        post '/depending_custom_fields/save', params: values.call('B').merge(authenticity_token: token), xhr: true
        expect(response).to have_http_status(:ok)
        expect(issue.reload.custom_field_value(parent)).to eq('B')
        # Last: Redmine logs the session out after a refused token.
        post '/depending_custom_fields/save', params: values.call('A'), xhr: true
        expect(response).to have_http_status(422)
      ensure
        ActionController::Base.allow_forgery_protection = previous
      end
      expect(issue.reload.custom_field_value(parent)).to eq('B')
    end
  end

  describe 'parameters' do
    before { as(dcf_admin) }

    it 'answers 404, never 500, to malformed ids and parent ids, and reflects nothing' do
      issue = issue_on(tracker)
      id = issue.id.to_s
      allow(Rails.logger).to receive(:error).and_call_original
      payload = '<script>alert(1)</script>'
      cases = [
        { ids: { a: id } }, { ids: [{ a: id }] }, { ids: 'abc' }, { ids: '0' }, { ids: '-1' },
        { ids: "#{id};2" }, { ids: '' }, { ids: nil }, { ids: '99999999999999999999' }, { ids: [id, 'x'] },
        { ids: payload }, { ids: [' 1'] }, { ids: ['01'] },
        { parent_id: [parent.id.to_s] }, { parent_id: { a: parent.id.to_s } }, { parent_id: '1e3' },
        { parent_id: '0x10' }, { parent_id: '"><img src=x onerror=alert(1)>' }, { parent_id: '' }, { parent_id: nil },
        { parent_id: "0#{parent.id}" }, { parent_id: '99999999999999999999' }
      ]
      cases.each do |change|
        params = { parent_id: parent.id.to_s, ids: [id] }.merge(change)
        get path, params: params, headers: DcfConfigHelpers::DCF_WIZARD_HEADERS
        expect(response).to have_http_status(:not_found), change.inspect
        expect(response.body).not_to include('<script>alert'), change.inspect
        expect(response.body).not_to include('<img src=x'), change.inspect
        expect(response.body).not_to include(parent.name), change.inspect
      end
      # ids[][]=<id>: whatever the parser makes of it, never a 500.
      get "#{path}?parent_id=#{parent.id}&ids[][]=#{id}&ids[][]=x", headers: DcfConfigHelpers::DCF_WIZARD_HEADERS
      expect([200, 404]).to include(response.status)
      expect(Rails.logger).not_to have_received(:error).with(/NoMethodError|RangeError|TypeError/)
    end

    it 'never reflects an unknown parameter' do
      issue = issue_on(tracker)
      get path, params: { parent_id: parent.id.to_s, ids: [issue.id.to_s], x: '<script>alert(1)</script>',
                          back_url: 'http://evil.example/' },
                headers: DcfConfigHelpers::DCF_WIZARD_HEADERS

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('alert(1)')
      expect(response.body).not_to include('evil.example')
      expect(response.headers['Location']).to be_nil
    end
  end
end
