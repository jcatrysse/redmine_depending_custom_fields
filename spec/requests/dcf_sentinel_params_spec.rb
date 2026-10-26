# frozen_string_literal: true

require_relative '../rails_helper'

# WP-19: the id-less blank sentinel of a managed single radio child (server
# design 2.2) through real pages and requests. Rack and ActionDispatch keep
# the last value of a repeated scalar key, so the sentinel (rendered first)
# loses to a checked radio and clears the field when no radio is checked;
# the server still decides (a required child is cleared only while its parent
# value allows nothing, the CustomFieldPatch bypass). A Ruby Hash cannot
# repeat a key, so the bodies are raw strings.
RSpec.describe 'Radio blank sentinel (WP-19)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:project) do
    record = dcf_create_project
    record.enabled_module_names = %w[issue_tracking time_tracking]
    record
  end
  let(:blank) { I18n.t('activerecord.errors.messages.blank') }
  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :add_issue_notes, :log_time]) }
  let(:member) do
    user = dcf_create_user("wp19-#{SecureRandom.hex(3)}")
    dcf_add_member(user, project, role)
    user
  end

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def name_of(field, prefix = 'issue')
    "#{prefix}[custom_field_values][#{field.id}]"
  end

  def urlencoded(pairs)
    pairs.map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value)}" }.join('&')
  end

  # A multipart/form-data body (the issue form is multipart) with the parts
  # in the given order.
  def multipart(pairs)
    boundary = 'dcf-wp19-boundary'
    parts = pairs.map do |key, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
    end
    ["#{parts.join}--#{boundary}--\r\n", "multipart/form-data; boundary=#{boundary}"]
  end

  def send_body(verb, path, pairs, encoding)
    if encoding == :multipart
      body, type = multipart(pairs)
    else
      body = urlencoded(pairs)
      type = 'application/x-www-form-urlencoded'
    end
    send(verb, path, params: body, headers: { 'CONTENT_TYPE' => type })
  end

  # Parent A, B, C; A allows a1 and a2, B allows b1, C allows nothing.
  def radio_kit(kind, required: false, multiple: false)
    parent, child = build_kit(kind, multiple: multiple)
    child.update!(edit_tag_style: 'check_box', is_required: required)
    [parent, CustomField.find(child.id)]
  end

  def stored(issue, field)
    Issue.find(issue.id).custom_field_value(field)
  end

  def sentinels
    doc.css('input[data-dcf-blank]')
  end

  def error_items
    doc.css('#errorExplanation li').map { |li| li.text.squish }
  end

  def message(field, text)
    "#{Issue.human_attribute_name(field.name)} #{text}"
  end

  describe 'last-wins parsing of a repeated scalar key' do
    let(:key) { 'issue[custom_field_values][7]' }

    def parsed(pairs, encoding)
      if encoding == :multipart
        body, type = multipart(pairs)
      else
        body = urlencoded(pairs)
        type = 'application/x-www-form-urlencoded'
      end
      env = Rack::MockRequest.env_for('/issues/1', { method: 'POST', input: body }.merge('CONTENT_TYPE' => type))
      ActionDispatch::Request.new(env).request_parameters.dig('issue', 'custom_field_values', '7')
    end

    [:urlencoded, :multipart].each do |encoding|
      it "keeps the last value, so the sentinel must come first (#{encoding})" do
        expect(parsed([[key, ''], [key, 'r1']], encoding)).to eq('r1')
        expect(parsed([[key, '']], encoding)).to eq('')
        expect(parsed([[key, 'r1'], [key, '']], encoding)).to eq('')
        expect(parsed([["#{key}[]", 'r1'], [key, '']], encoding)).to eq('')
      end

      # Why a multi field never gets a scalar sentinel.
      it "refuses a scalar key before the same key with [] (#{encoding})" do
        expect { parsed([[key, ''], ["#{key}[]", 'r1']], encoding) }.to raise_error(ActionController::BadRequest)
      end
    end
  end

  describe 'the rendered forms' do
    [:list, :enumeration].each do |kind|
      it "renders one id-less sentinel right before a managed #{kind} radio group on the edit, new and copy forms" do
        parent, child = radio_kit(kind, required: true)
        issue = kit_issue(project, parent => 'A', child => 'a1')
        as(dcf_admin)
        ["/issues/#{issue.id}/edit", "/projects/#{project.identifier}/issues/new?issue[tracker_id]=#{issue.tracker_id}",
         "/projects/#{project.identifier}/issues/#{issue.id}/copy"].each do |path|
          get path
          expect(response).to have_http_status(200), path
          group = doc.at_css("span.check_box_group[data-dcf-field='#{child.id}']")
          sentinel = group.previous_element

          expect(sentinels.size).to eq(1), path
          expect(sentinel.matches?('input[type=hidden][data-dcf-blank="1"]')).to be(true), path
          expect([sentinel['name'], sentinel['value'], sentinel['id']]).to eq([name_of(child), '', nil]), path
          expect(group.css('input[type=radio]').map { |radio| radio['name'] }.uniq).to eq([name_of(child)]), path
          expect(sentinel.parent.at_css('label')['for']).to be_nil, path
        end
      end
    end

    it 'renders none for multi check boxes, drop-downs and a radio child whose parent the member cannot see' do
      _parent, multi = radio_kit(:list, multiple: true)
      select_parent, select = build_kit(:list)
      hidden_parent, radio = radio_kit(:list, required: true)
      hidden_parent.update!(visible: false, role_ids: [dcf_create_role(permissions: [:view_issues]).id])
      issue = kit_issue(project, multi => %w[a1], select_parent => 'A', select => 'a1',
                                 CustomField.find(hidden_parent.id) => 'A', radio => 'a1')
      as(member)
      get "/issues/#{issue.id}/edit"
      expect(response).to have_http_status(200)

      expect(sentinels).to be_empty
      expect(doc.at_css("[data-dcf-field='#{radio.id}']")['data-dcf-parent']).to be_nil
      multi_p = doc.at_css("span.check_box_group[data-dcf-field='#{multi.id}']").parent
      expect(multi_p.css('input[type=hidden]').map { |input| input['name'] }).to all(end_with('[]'))
      expect(doc.at_css("select[data-dcf-field='#{select.id}']")['data-dcf-parent']).to eq(select_parent.id.to_s)

      as(dcf_admin)
      get "/issues/#{issue.id}/edit"
      expect(sentinels.map { |input| input['name'] }).to eq([name_of(radio)])
    end

    it 'names the sentinel of a time-entry radio child with the time_entry prefix inside the issue form' do
      parent, child = build_kit(:list)
      time_parent = dcf_list_field(values: %w[A B], type: TimeEntryCustomField)
      time_child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: time_parent, type: TimeEntryCustomField)
      time_child = dcf_set_dependencies(time_child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      time_child.update!(edit_tag_style: 'check_box')
      issue = kit_issue(project, parent => 'A', child => 'a1')
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"

      expect(response).to have_http_status(200)
      expect(sentinels.map { |input| input['name'] }).to eq([name_of(time_child, 'time_entry')])
      expect(sentinels.first.ancestors('fieldset#log_time')).not_to be_empty
    end
  end

  describe 'PATCH /issues/:id' do
    before { as(dcf_admin) }

    [:list, :enumeration].each do |kind|
      [:urlencoded, :multipart].each do |encoding|
        context "with a #{kind} radio child (#{encoding})" do
          it 'stores the checked radio posted after the sentinel, required or not' do
            [false, true].each do |required|
              parent, child = radio_kit(kind, required: required)
              issue = kit_issue(project, parent => 'A', child => 'a1')
              send_body(:patch, "/issues/#{issue.id}",
                        [[name_of(parent), kit_key(parent, 'A')], [name_of(child), ''],
                         [name_of(child), kit_key(child, 'a2')]], encoding)

              expect(response).to have_http_status(302), required.to_s
              expect(stored(issue, child)).to eq(kit_key(child, 'a2'))
            end
          end

          it 'clears a non-required child with the sentinel alone' do
            parent, child = radio_kit(kind)
            issue = kit_issue(project, parent => 'A', child => 'a1')
            send_body(:patch, "/issues/#{issue.id}", [[name_of(parent), kit_key(parent, 'A')], [name_of(child), '']], encoding)

            expect(response).to have_http_status(302)
            expect(stored(issue, child)).to be_blank
          end

          it 'clears a required child when the new parent value allows nothing (no-options bypass)' do
            parent, child = radio_kit(kind, required: true)
            issue = kit_issue(project, parent => 'A', child => 'a1')
            send_body(:patch, "/issues/#{issue.id}", [[name_of(parent), kit_key(parent, 'C')], [name_of(child), '']], encoding)

            expect(response).to have_http_status(302)
            expect([stored(issue, parent), stored(issue, child)]).to eq([kit_key(parent, 'C'), ''])
          end

          it 'refuses to clear a required child while its parent value allows options, keeping the stored value' do
            parent, child = radio_kit(kind, required: true)
            issue = kit_issue(project, parent => 'A', child => 'a1')
            send_body(:patch, "/issues/#{issue.id}", [[name_of(parent), kit_key(parent, 'B')], [name_of(child), '']], encoding)

            expect(response).to have_http_status(200)
            expect(error_items).to eq([message(child, blank)])
            expect([stored(issue, parent), stored(issue, child)]).to eq([kit_key(parent, 'A'), kit_key(child, 'a1')])
          end

          it 'keeps a stored legacy value posted after the sentinel and refuses a new disallowed one (D1)' do
            parent, child = radio_kit(kind, required: true)
            legacy = kit_issue(project, parent => 'A', child => 'b1')
            send_body(:patch, "/issues/#{legacy.id}",
                      [[name_of(parent), kit_key(parent, 'A')], [name_of(child), ''], [name_of(child), kit_key(child, 'b1')],
                       ['issue[notes]', 'kept']], encoding)
            expect(response).to have_http_status(302)
            expect(stored(legacy, child)).to eq(kit_key(child, 'b1'))

            issue = kit_issue(project, parent => 'A', child => 'a1')
            send_body(:patch, "/issues/#{issue.id}",
                      [[name_of(parent), kit_key(parent, 'A')], [name_of(child), ''], [name_of(child), kit_key(child, 'b1')]],
                      encoding)
            expect(response).to have_http_status(200)
            expect(error_items).to eq([message(child, invalid)])
            expect(stored(issue, child)).to eq(kit_key(child, 'a1'))
          end
        end
      end
    end

    it 'stores the checked boxes of a multi child posted with core\'s trailing hidden blank' do
      parent, child = radio_kit(:list, multiple: true)
      issue = kit_issue(project, parent => 'A', child => %w[a2])
      send_body(:patch, "/issues/#{issue.id}",
                [[name_of(parent), 'A'], ["#{name_of(child)}[]", 'a1'], ["#{name_of(child)}[]", '']], :urlencoded)

      expect(response).to have_http_status(302)
      expect(stored(issue, child)).to eq(%w[a1])
    end

    it 'creates no time entry for the sentinel of a time-entry radio child while hours and comments are blank' do
      parent, child = build_kit(:list)
      time_parent = dcf_list_field(values: %w[A B], type: TimeEntryCustomField)
      time_child = dcf_list_field(format: 'depending_list', values: %w[a1], parent: time_parent, type: TimeEntryCustomField)
      time_child.update!(edit_tag_style: 'check_box')
      issue = kit_issue(project, parent => 'A', child => 'a1')

      expect do
        send_body(:patch, "/issues/#{issue.id}",
                  [['issue[notes]', 'note'], ['time_entry[hours]', ''], ['time_entry[comments]', ''],
                   [name_of(time_child, 'time_entry'), '']], :urlencoded)
      end.not_to change(TimeEntry, :count)
      expect(response).to have_http_status(302)
      expect(Issue.find(issue.id).journals.last.notes).to eq('note')
    end
  end

  # The open input from WP-17: core renders a required single drop-down with
  # a default value without a '' option (only fields saved before the
  # clear-on-save rule hold one), so the runtime's selectedIndex = -1 posts
  # nothing; the sentinel posts '' instead.
  describe 'a managed required drop-down without a blank option' do
    before { as(dcf_admin) }

    def select_kit(kind)
      parent, child = build_kit(kind)
      child.update!(is_required: true)
      child.update_column(:default_value, kit_key(child, 'a1'))
      [parent, CustomField.find(child.id)]
    end

    [:list, :enumeration].each do |kind|
      it "renders one id-less sentinel right before the #{kind} select, keeping label for=" do
        parent, child = select_kit(kind)
        issue = kit_issue(project, parent => 'A', child => 'a1')
        get "/issues/#{issue.id}/edit"
        expect(response).to have_http_status(200)
        form = doc
        select = form.at_css("select[data-dcf-field='#{child.id}']")
        sentinel = form.at_css('input[data-dcf-blank]')

        expect(select.css('option').map { |option| option['value'] }).not_to include('')
        expect(form.css('input[data-dcf-blank]').size).to eq(1)
        expect(sentinel.next_element).to eq(select)
        expect([sentinel['name'], sentinel['value'], sentinel['id']]).to eq([name_of(child), '', nil])
        expect(sentinel.parent.to_html.scan(' id="').size).to eq(1)
        expect(sentinel.parent.at_css('label')['for']).to eq(select['id'])
      end

      [:urlencoded, :multipart].each do |encoding|
        context "with a #{kind} drop-down (#{encoding})" do
          it 'clears it when the new parent value allows nothing, where posting nothing was refused as invalid' do
            parent, child = select_kit(kind)
            issue = kit_issue(project, parent => 'A', child => 'a1')
            send_body(:patch, "/issues/#{issue.id}", [[name_of(parent), kit_key(parent, 'C')]], encoding)
            expect(response).to have_http_status(200)
            expect(error_items).to eq([message(child, invalid)])

            send_body(:patch, "/issues/#{issue.id}", [[name_of(parent), kit_key(parent, 'C')], [name_of(child), '']], encoding)
            expect(response).to have_http_status(302)
            expect([stored(issue, parent), stored(issue, child)]).to eq([kit_key(parent, 'C'), ''])
          end

          it 'stores the option selected after the sentinel' do
            parent, child = select_kit(kind)
            issue = kit_issue(project, parent => 'A', child => 'a2')
            send_body(:patch, "/issues/#{issue.id}",
                      [[name_of(parent), kit_key(parent, 'A')], [name_of(child), ''], [name_of(child), kit_key(child, 'a1')]],
                      encoding)

            expect(response).to have_http_status(302)
            expect(stored(issue, child)).to eq(kit_key(child, 'a1'))
          end

          it 'refuses the sentinel alone while the parent value allows options, keeping the stored value' do
            parent, child = select_kit(kind)
            issue = kit_issue(project, parent => 'A', child => 'a1')
            send_body(:patch, "/issues/#{issue.id}", [[name_of(parent), kit_key(parent, 'B')], [name_of(child), '']], encoding)

            expect(response).to have_http_status(200)
            expect(error_items).to eq([message(child, blank)])
            expect([stored(issue, parent), stored(issue, child)]).to eq([kit_key(parent, 'A'), kit_key(child, 'a1')])
          end
        end
      end
    end
  end

  describe 'POST /projects/:id/issues (new issue)' do
    before { as(dcf_admin) }

    it 'creates the issue with the required radio child blank only while the parent value allows nothing' do
      parent, child = radio_kit(:list, required: true)
      tracker, status, priority = dcf_issue_infra(project)
      tracker.custom_fields << parent << child
      base = [['issue[tracker_id]', tracker.id.to_s], ['issue[subject]', 'New'], ['issue[status_id]', status.id.to_s],
              ['issue[priority_id]', priority.id.to_s]]

      expect do
        send_body(:post, "/projects/#{project.identifier}/issues",
                  base + [[name_of(parent), 'C'], [name_of(child), '']], :urlencoded)
      end.to change(Issue, :count).by(1)
      expect(response).to have_http_status(302)
      expect(Issue.order(:id).last.custom_field_value(child)).to be_blank

      expect do
        send_body(:post, "/projects/#{project.identifier}/issues",
                  base + [[name_of(parent), 'A'], [name_of(child), '']], :urlencoded)
      end.not_to change(Issue, :count)
      expect(error_items).to eq([message(child, blank)])
    end
  end

  # Recorded in the WP-19 Delivered block: the sentinel always posts the
  # radio child, so core validates the custom values on every form save, as
  # for a required drop-down. A required radio child stored blank under a
  # parent value with options (the parent read-only for the member) now
  # needs a value on a notes-only save; before WP-19 nothing was posted.
  describe 'a notes-only save' do
    it 'needs a value for a blank required radio child whose read-only parent allows options' do
      parent, child = radio_kit(:list, required: true)
      issue = kit_issue(project, parent => 'A', child => [])
      WorkflowPermission.create!(tracker_id: issue.tracker_id, old_status_id: issue.status_id, role_id: role.id,
                                 field_name: parent.id.to_s, rule: 'readonly')
      as(member)
      get "/issues/#{issue.id}/edit"
      expect(sentinels.map { |input| input['name'] }).to eq([name_of(child)])
      expect(doc.css("[name='#{name_of(parent)}']")).to be_empty

      send_body(:patch, "/issues/#{issue.id}", [['issue[notes]', 'only a note'], [name_of(child), '']], :urlencoded)
      expect(response).to have_http_status(200)
      expect(error_items).to eq([message(child, blank)])

      send_body(:patch, "/issues/#{issue.id}", [['issue[notes]', 'only a note']], :urlencoded)
      expect(response).to have_http_status(302)
      expect(Issue.find(issue.id).journals.last.notes).to eq('only a note')
    end
  end
end
