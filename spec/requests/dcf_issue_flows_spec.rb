# frozen_string_literal: true

require_relative '../rails_helper'

# WP-09: D1 per value (UD-04) on persisted issues, through the paths that
# assign custom values: Issue#safe_attributes= (used by the issue form, bulk
# edit, the REST API, mail replies and the wizard), then the REST API, bulk
# update, a mail reply and the context menu wizard themselves. While the
# parent is unchanged a stored value is kept and only newly added values must
# be allowed; a changed parent makes every value strict; a parent that is not
# available on the issue counts as changed (UD-05). UD-07 keeps today's
# result for a child the user cannot edit.
#
# Every issue stores the legacy combination parent A with child b1 (multiple:
# b1 and a1); A allows a1 and a2, B allows b1, C allows nothing, D allows a1
# and b2 is linked under no parent value.
RSpec.describe 'Depending fields on issue updates (D1)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :add_issue_notes]) }
  let(:user) do
    member = dcf_create_user("d1-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end

  def d1_kit(kind, multiple: false, type: IssueCustomField)
    names = %w[a1 a2 b1 b2]
    if kind == :list
      parent = dcf_list_field(values: %w[A B C D], type: type)
      child = dcf_list_field(format: 'depending_list', values: names, parent: parent, multiple: multiple, type: type)
    else
      parent = dcf_enum_field(names: %w[A B C D], type: type)
      child = dcf_enum_field(format: 'depending_enumeration', names: names, parent: parent, type: type)
      child.update!(multiple: true) if multiple
    end
    links = { kit_key(parent, 'A') => [kit_key(child, 'a1'), kit_key(child, 'a2')],
              kit_key(parent, 'B') => [kit_key(child, 'b1')],
              kit_key(parent, 'D') => [kit_key(child, 'a1')] }
    [parent, dcf_set_dependencies(child, value_dependencies: links)]
  end

  # The posted form of +names+ ('' or [] for blank), as Strings.
  def posted(field, names)
    keys = Array(names).reject(&:empty?).map { |n| kit_key(field, n) }
    return (keys.empty? ? [''] : keys) if field.multiple?

    keys.first || ''
  end

  # Assigns +values+ (field => names) like the issue paths do: init_journal,
  # then safe_attributes= for the user.
  def assign(issue, values)
    issue.init_journal(user)
    attributes = { 'custom_field_values' => values.to_h { |f, names| [f.id.to_s, posted(f, names)] } }
    issue.send(:safe_attributes=, attributes, user)
    issue
  end

  def stored_keys(issue, field)
    Array(Issue.find(issue.id).custom_field_value(field)).reject(&:blank?)
  end

  def json_headers
    { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
  end

  describe 'Issue#safe_attributes= (D1 matrix)' do
    # A single child keeps b1, which neither D nor C allows, so each changed
    # column rejects it only because the change withdraws the tolerance: D
    # allows another value (a1), C allows nothing.
    single_columns = { 'the parent unchanged' => 'A', 'the parent changed to D' => 'D',
                       'the parent changed to C' => 'C', 'the parent unavailable' => nil }
    # row => [posted child, valid with the parent unchanged, changed to D, changed to C, unavailable]
    single_rows = {
      'kept unchanged' => ['b1', true, false, false, false],
      'cleared' => ['', true, true, true, true],
      'replaced by an allowed value' => ['a1', true, true, false, false],
      'replaced by a disallowed value' => ['b2', false, false, false, false]
    }
    multi_columns = { 'the parent unchanged' => 'A', 'the parent changed to B' => 'B', 'the parent unavailable' => nil }
    # row => [posted child, valid with the parent unchanged, changed to B, unavailable]
    multi_rows = {
      'kept unchanged' => [%w[b1 a1], true, false, false],
      'reordered' => [%w[a1 b1], true, false, false],
      'with one value removed' => [%w[b1], true, true, false],
      'with an allowed value added' => [%w[b1 a1 a2], true, false, false],
      'with a disallowed value added' => [%w[b1 a1 b2], false, false, false]
    }
    variants = {
      'list child' => [:list, false, false],
      'multiple list child' => [:list, true, false],
      'enumeration child' => [:enumeration, false, false],
      'multiple enumeration child' => [:enumeration, true, false],
      'enumeration child with the stored b1 inactive' => [:enumeration, false, true],
      'multiple enumeration child with the stored b1 inactive' => [:enumeration, true, true]
    }

    variants.each do |variant, (kind, multiple, inactive)|
      context variant do
        let(:kit) { d1_kit(kind, multiple: multiple) }
        let(:parent) { kit.first }
        let(:child) { kit.last }

        def legacy_issue(stored, inactive:, parent_available:)
          issue = kit_issue(project, parent => 'A', child => stored)
          child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false) if inactive
          issue.tracker.custom_fields.delete(parent) unless parent_available
          Issue.find(issue.id)
        end

        rows, columns = multiple ? [multi_rows, multi_columns] : [single_rows, single_columns]
        rows.each do |row, (child_names, *expected)|
          columns.each_with_index do |(column, parent_name), i|
            valid = expected[i]
            it "#{valid ? 'accepts' : 'rejects'} the child #{row} with #{column}" do
              issue = legacy_issue(multiple ? %w[b1 a1] : 'b1', inactive: inactive, parent_available: !parent_name.nil?)
              values = { child => child_names }
              values[parent] = parent_name if parent_name
              assign(issue, values)

              expect(issue.editable_custom_field_values(user).map(&:custom_field_id)).to include(child.id)
              expect(issue.custom_field_values.map(&:custom_field_id).include?(parent.id)).to be(!parent_name.nil?)
              expect(Array(issue.custom_field_value(child)).reject(&:empty?))
                .to match_array(Array(child_names).reject(&:empty?).map { |n| kit_key(child, n) })
              expect(issue.valid?).to be(valid), issue.errors.full_messages.inspect
              expect(issue.errors[child.name]).to eq(valid ? [] : [invalid])
            end
          end
        end
      end
    end

    it 'saves a legacy multiple child with an added allowed value and keeps the legacy value' do
      parent, child = d1_kit(:list, multiple: true)
      issue = kit_issue(project, parent => 'A', child => %w[b1])
      assign(issue, { parent => 'A', child => %w[b1 a1] })
      expect(issue.save).to be(true), issue.errors.full_messages.inspect
      expect(stored_keys(issue, child)).to match_array(%w[b1 a1])
    end

    it 'counts duplicate stored parent rows and a reordered multiple parent as unchanged' do
      parent = dcf_list_field(values: %w[A B C], multiple: true)
      child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: { 'A' => ['a1'] })
      issue = kit_issue(project, parent => %w[A C], child => 'b1')
      CustomValue.create!(customized: issue, custom_field: parent, value: 'A')
      issue = Issue.find(issue.id)
      stored = issue.custom_field_values.detect { |v| v.custom_field_id == parent.id }
      expect(stored.value_was).to match_array(%w[A C A])
      assign(issue, { parent => %w[C A], child => 'b1' })
      expect(issue.valid?).to be(true), issue.errors.full_messages.inspect
    end

    it 'counts a parent without a stored row posted blank as unchanged' do
      parent, child = d1_kit(:list)
      issue = kit_issue(project, child => 'b1')
      tracker = issue.tracker
      tracker.custom_fields << parent unless tracker.custom_fields.include?(parent)
      issue = Issue.find(issue.id)
      expect(issue.custom_field_values.detect { |v| v.custom_field_id == parent.id }.value_was).to be_nil
      assign(issue, { parent => '', child => 'b1' })
      expect(issue.valid?).to be(true), issue.errors.full_messages.inspect
    end

    it 'keeps rejecting a disallowed value on a new issue (no baseline)' do
      parent, child = d1_kit(:list)
      tracker, status, priority = dcf_issue_infra(project)
      [parent, child].each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: user,
                        status: status, priority: priority)
      issue.send(:safe_attributes=, { 'custom_field_values' => { parent.id.to_s => 'A', child.id.to_s => 'b1' } }, user)
      expect(issue.valid?).to be(false)
      expect(issue.errors[child.name]).to eq([invalid])
    end
  end

  describe 'REST API (PUT /issues/:id.json)' do
    let(:kit) { d1_kit(:list, multiple: true) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:other) { dcf_list_field(values: %w[X Y]) }
    let(:issue) { kit_issue(project, parent => 'A', child => %w[b1 a1], other => 'X') }

    before { allow(User).to receive(:current).and_return(user) }

    def put_issue(attributes)
      put "/issues/#{issue.id}.json", params: { issue: attributes }.to_json, headers: json_headers
    end

    it 'keeps a legacy combination on a notes-only update' do
      put_issue(notes: 'Only a note')
      expect(response).to have_http_status(204)
      expect(stored_keys(issue, child)).to match_array(%w[b1 a1])
      expect(Issue.find(issue.id).journals.last.notes).to eq('Only a note')
    end

    it 'keeps a legacy combination when the stored custom fields are sent unchanged with notes' do
      put_issue(notes: 'Resent', custom_fields: [{ id: parent.id, value: 'A' }, { id: child.id, value: %w[b1 a1] }])
      expect(response).to have_http_status(204), response.body
      expect(stored_keys(issue, child)).to match_array(%w[b1 a1])
      expect(Issue.find(issue.id).journals.last.notes).to eq('Resent')
    end

    it 'keeps a legacy combination when only another custom field changes' do
      put_issue(custom_fields: [{ id: other.id, value: 'Y' }])
      expect(response).to have_http_status(204), response.body
      expect(Issue.find(issue.id).custom_field_value(other)).to eq('Y')
      expect(stored_keys(issue, child)).to match_array(%w[b1 a1])
    end

    it 'counts a repeated stored value as unchanged' do
      put_issue(custom_fields: [{ id: child.id, value: %w[b1 b1 a1] }])
      expect(response).to have_http_status(204), response.body
      expect(stored_keys(issue, child)).to match_array(%w[b1 a1])
    end

    it 'rejects a newly added disallowed value with 422 and an errors array' do
      put_issue(custom_fields: [{ id: child.id, value: %w[b1 a1 b2] }])
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
      expect(stored_keys(issue, child)).to match_array(%w[b1 a1])
    end

    it 'rejects the stored legacy value once the parent changes, with 422' do
      put_issue(custom_fields: [{ id: parent.id, value: 'C' }])
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
    end
  end

  # The baseline is what the issue stores. A field without a saved row has
  # none ([]), also when a tracker or project change makes it available and
  # core fills in its default (Issue#set_custom_field_default?), which
  # value_was then copies. So a parent that gets its default counts as
  # changed, and a child default is a new value, as before WP-09 and as for
  # a copy whose source does not carry the field. A row goes missing when a
  # save runs on a tracker or project without the field.
  describe 'a field that becomes available through a tracker or project change' do
    let(:kit) { d1_kit(:list) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:messages) { { 'en' => 'is invalid', 'de' => 'ist nicht gültig' } }

    before { allow(User).to receive(:current).and_return(user) }

    # Created after the issue: dcf_issue_infra takes Tracker.first.
    def target_tracker
      tracker = dcf_tracker
      [parent, child].each { |f| tracker.custom_fields << f }
      project.trackers << tracker
      tracker
    end

    def put_issue(issue, attributes)
      put "/issues/#{issue.id}.json", params: { issue: attributes }.to_json, headers: json_headers
    end

    # The child stores b1 on a tracker that does not carry the parent.
    def issue_without_parent_row
      issue = kit_issue(project, child => 'b1')
      expect(issue.custom_values.map(&:custom_field_id)).not_to include(parent.id)
      issue
    end

    it 'rejects a tracker change that gives the parent its default, with 422 in en and de' do
      parent.update!(default_value: 'A')
      issues = messages.keys.to_h { |language| [language, issue_without_parent_row] }
      tracker = target_tracker
      messages.each do |language, message|
        user.update_column(:language, language)
        issue = issues[language]
        put_issue(issue, tracker_id: tracker.id)
        expect(response).to have_http_status(422), "#{language}: #{response.body}"
        expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{message}"]), language
        expect(Issue.find(issue.id).tracker_id).to eq(issue.tracker_id)
      end
    end

    it 'rejects a project change that gives the parent its default, with 422' do
      other = dcf_create_project
      dcf_issue_infra(other)
      dcf_add_member(user, other, role)
      parent.update!(default_value: 'A', is_for_all: false)
      parent.projects = [other]
      issue = issue_without_parent_row
      issue.tracker.custom_fields << parent
      expect(Issue.find(issue.id).available_custom_fields).not_to include(parent)

      put_issue(issue, project_id: other.id)
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
      expect(Issue.find(issue.id).project_id).to eq(project.id)
    end

    it 'keeps the child on a tracker change when the parent has no default (it stays blank)' do
      issue = issue_without_parent_row
      tracker = target_tracker
      put_issue(issue, tracker_id: tracker.id)
      expect(response).to have_http_status(204), response.body
      saved = Issue.find(issue.id)
      expect([saved.tracker_id, saved.custom_field_value(parent).presence, saved.custom_field_value(child)])
        .to eq([tracker.id, nil, 'b1'])
    end

    it 'rejects a tracker change that gives the child a default the stored parent does not allow' do
      child.update_column(:default_value, 'b1')
      issue = kit_issue(project, parent => 'A')
      expect(issue.custom_values.map(&:custom_field_id)).not_to include(child.id)
      put_issue(issue, tracker_id: target_tracker.id)
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
    end

    it 'judges a copy into that tracker the same way (the source carries no parent)' do
      parent.update!(default_value: 'A')
      copy = issue_without_parent_row.copy
      copy.tracker = target_tracker
      expect(errors_for(copy, child)).to eq([invalid])
    end
  end

  describe 'bulk update (POST /issues/bulk_update)' do
    let(:kit) { d1_kit(:list) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:other) { dcf_list_field(values: %w[X Y]) }

    before { allow(User).to receive(:current).and_return(user) }

    it 'saves an unrelated change on issues holding legacy combinations' do
      issues = [kit_issue(project, parent => 'A', child => 'b1', other => 'X'),
                kit_issue(project, parent => 'C', child => 'a1', other => 'X')]
      priority = IssuePriority.create!(name: "P-#{SecureRandom.hex(3)}")
      # The bulk form posts '' (no change) for the untouched single-value fields.
      post '/issues/bulk_update', params: {
        ids: issues.map(&:id),
        issue: { priority_id: priority.id,
                 custom_field_values: { other.id.to_s => 'Y', parent.id.to_s => '', child.id.to_s => '' } }
      }
      expect(response).to have_http_status(302)
      issues.each do |issue|
        saved = Issue.find(issue.id)
        expect([saved.priority_id, saved.custom_field_value(other)]).to eq([priority.id, 'Y'])
      end
      expect(issues.map { |i| Issue.find(i.id).custom_field_value(child) }).to eq(%w[b1 a1])
    end
  end

  describe 'mail reply' do
    let(:kit) { d1_kit(:list) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:address) { "#{user.login}@example.net" }
    let(:issue) { kit_issue(project, parent => 'A', child => 'b1') }

    before { EmailAddress.create!(user: user, address: address, is_default: true) }
    after { User.current = nil }

    def reply(body)
      <<~MAIL
        From: #{address}
        To: redmine@example.net
        Subject: Re: S [##{issue.id}]
        Message-ID: <dcf-#{SecureRandom.hex(6)}@example.net>
        Mime-Version: 1.0
        Content-Type: text/plain; charset=utf-8

        #{body}
      MAIL
    end

    it 'adds a reply to an issue holding a legacy combination' do
      journal = MailHandler.receive(reply('A reply by mail'))
      expect(journal).to be_a(Journal)
      expect(journal.notes).to include('A reply by mail')
      expect(Issue.find(issue.id).custom_field_value(child)).to eq('b1')
    end

    it 'rejects a reply that sets a disallowed value by keyword' do
      expect(MailHandler.receive(reply("#{child.name}: b2\n\nA reply by mail"), allow_override: 'all')).to be(false)
      expect(Issue.find(issue.id).journals).to be_empty
    end
  end

  describe 'context menu wizard (POST /depending_custom_fields/save)' do
    let(:kit) { d1_kit(:list) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:other) { dcf_list_field(values: %w[X Y]) }

    before { allow(User).to receive(:current).and_return(user) }

    it 'saves an unrelated value on an issue holding a legacy combination' do
      issue = kit_issue(project, parent => 'A', child => 'b1', other => 'X')
      post '/depending_custom_fields/save',
           params: { issue_ids: issue.id.to_s, issue: { custom_field_values: { other.id.to_s => 'Y' } } }
      expect(response).to have_http_status(200), response.body
      expect([Issue.find(issue.id).custom_field_value(other), Issue.find(issue.id).custom_field_value(child)])
        .to eq(%w[Y b1])
    end

    it 'rejects a disallowed value with 422' do
      issue = kit_issue(project, parent => 'A', child => 'b1')
      post '/depending_custom_fields/save',
           params: { issue_ids: issue.id.to_s, issue: { custom_field_values: { child.id.to_s => 'b2' } } }
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
    end
  end

  # UD-07 (kept as today, no editable_by? rule): a child the user cannot edit
  # gets the same rule as any other child whenever core validates it. Core
  # Issue validates only editable_custom_field_values of the journal user, so
  # on an issue such a child is never checked and the parent change saves (as
  # on e9db18b); a time entry validates every value, so there the change is
  # rejected. Stored: parent A with the allowed a1; the parent becomes B,
  # which does not allow a1.
  describe 'a child the user cannot edit while the parent changes (UD-07)' do
    let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
    let(:messages) { { en: 'is invalid', de: 'ist nicht gültig' } }

    def change_parent(issue, parent)
      assign(Issue.find(issue.id), { parent => 'B' })
    end

    context 'on an issue' do
      let(:kit) { d1_kit(:list) }
      let(:parent) { kit.first }
      let(:child) { kit.last }

      def stored_issue
        kit_issue(project, parent => 'A', child => 'a1')
      end

      it 'rejects the change when the child is editable, with one message in en and de' do
        messages.each do |locale, message|
          I18n.with_locale(locale) do
            issue = change_parent(stored_issue, parent)
            expect(issue.save).to be(false), locale.to_s
            expect(issue.errors[child.name]).to eq([message]), locale.to_s
          end
        end
      end

      it 'saves the change when the child is read-only by workflow (core does not validate it), in en and de' do
        messages.each_key do |locale|
          I18n.with_locale(locale) do
            issue = stored_issue
            WorkflowPermission.find_or_create_by!(tracker_id: issue.tracker_id, old_status_id: issue.status_id,
                                                  role_id: role.id, field_name: child.id.to_s, rule: 'readonly')
            issue = change_parent(issue, parent)
            expect(issue.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
            expect(issue.save).to be(true), issue.errors.full_messages.inspect
            expect([Issue.find(issue.id).custom_field_value(parent), Issue.find(issue.id).custom_field_value(child)])
              .to eq(%w[B a1])
          end
        end
      end

      it 'saves the change when the child is not visible for the user role (core does not validate it), in en and de' do
        child.update!(visible: false, role_ids: [other_role.id])
        messages.each_key do |locale|
          I18n.with_locale(locale) do
            issue = change_parent(stored_issue, parent)
            expect(issue.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
            expect(issue.save).to be(true), issue.errors.full_messages.inspect
            expect(Issue.find(issue.id).custom_field_value(child)).to eq('a1')
          end
        end
      end
    end

    context 'on a time entry' do
      let(:kit) { d1_kit(:list, type: TimeEntryCustomField) }
      let(:parent) { kit.first }
      let(:child) { kit.last }

      def time_entry(values)
        activity = TimeEntryActivity.create!(name: "Act-#{SecureRandom.hex(3)}", active: true)
        entry = TimeEntry.new(project: project, user: user, spent_on: Date.today, hours: 1, activity: activity)
        entry.custom_field_values = values.to_h { |f, names| [f.id.to_s, posted(f, names)] }
        entry.save!(validate: false)
        TimeEntry.find(entry.id)
      end

      it 'rejects the change for a child not visible for the user role, in en and de' do
        child.update!(visible: false, role_ids: [other_role.id])
        messages.each do |locale, message|
          I18n.with_locale(locale) do
            entry = time_entry(parent => 'A', child => 'a1')
            expect(entry.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
            entry.custom_field_values = { parent.id.to_s => 'B' }
            expect(entry.valid?).to be(false)
            expect(entry.errors[child.name]).to eq([message]), locale.to_s
          end
        end
      end
    end
  end
end
