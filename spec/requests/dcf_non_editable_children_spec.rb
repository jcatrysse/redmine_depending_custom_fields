# frozen_string_literal: true

require_relative '../rails_helper'

# WP-09b (UD-07 confirmed: the rules lead on every object). Core Issue and
# Project validate only editable_custom_field_values, so the plugin applies
# the D1 rule (DependencyRules.parent_state and dependency_check) to the
# depending children the user cannot edit, with core's user and gate. A child
# the user can see (read-only by workflow) gets 'is invalid' under its own
# name. A child the user cannot see (role-invisible) is never named and its
# value never shown: one dedicated message on the changed parent field, or
# on base when the parent is not shown to the user either or its value did
# not change (a stale default core gives on a copy or a move). Time entries
# and versions validate every value in core and are not patched; there core
# names even a hidden child (known exception, UD-07 refinements).
#
# WP-09c (owner, UD-07 refinements): for these children a parent field that
# is not available on the record does not count as changed (nobody changed
# it), so their stored value is tolerated and only new values must be
# allowed. A child the user can edit keeps UD-05 (an unavailable parent
# counts as changed), and an available parent that changed stays strict.
#
# Kit: parent values A, B, C, D; A allows the secret value and a2, B allows
# b1, C allows nothing, D allows the secret value; b2 is linked under no
# parent value. Issues store A with the secret value unless noted.
RSpec.describe 'Depending children the user cannot edit (WP-09b, UD-07)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:hidden_message) { I18n.t('activerecord.errors.messages.dcf_hidden_child_conflict') }
  let(:base_message) { I18n.t('error_dcf_hidden_child_conflict') }
  let(:invalid_texts) { { 'en' => 'is invalid', 'de' => 'ist nicht gültig' } }
  let(:hidden_texts) do
    { 'en' => 'cannot be changed because a dependent field you cannot see has a value that does not match the ' \
              'new value',
      'de' => 'kann nicht geändert werden, weil ein abhängiges Feld, das Sie nicht sehen können, einen Wert hat, ' \
              'der nicht zum neuen Wert passt' }
  end
  let(:base_texts) do
    { 'en' => 'This change cannot be saved because a dependent field you cannot see has a value that the change ' \
              'does not allow.',
      'de' => 'Diese Änderung kann nicht gespeichert werden, weil ein abhängiges Feld, das Sie nicht sehen können, ' \
              'einen Wert hat, den die Änderung nicht zulässt.' }
  end
  let(:secret) { "Qz#{SecureRandom.hex(4)}secret" }
  let(:project) { dcf_create_project }
  let(:role) do
    dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :add_issue_notes, :copy_issues,
                                  :import_issues, :edit_project])
  end
  let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:user) do
    member = dcf_create_user("ne-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:kit) { build_pair }
  let(:parent) { kit.first }
  let(:child) { kit.last }
  let(:other) { dcf_list_field(values: %w[X Y]) }

  def rules_module
    RedmineDependingCustomFields::NonEditableDependencies
  end

  # +kind+ :list (values stored as names) or :enum (enumeration ids, as in
  # the D1 matrix of dcf_issue_flows_spec.rb); kit_issue and kit_key map the
  # names for both.
  def build_pair(kind: :list, type: IssueCustomField, multiple: false, parent: nil)
    hex = SecureRandom.hex(4)
    names = [secret, 'a2', 'b1', 'b2']
    if kind == :list
      parent ||= dcf_list_field(values: %w[A B C D], type: type, name: "Parent#{hex}")
      child = dcf_list_field(format: 'depending_list', values: names, parent: parent, type: type,
                             multiple: multiple, name: "Child#{hex}")
    else
      parent ||= dcf_enum_field(names: %w[A B C D], type: type, name: "Parent#{hex}")
      child = dcf_enum_field(format: 'depending_enumeration', names: names, parent: parent, type: type,
                             name: "Child#{hex}")
      child.update!(multiple: true) if multiple
    end
    links = { kit_key(parent, 'A') => [kit_key(child, secret), kit_key(child, 'a2')],
              kit_key(parent, 'B') => [kit_key(child, 'b1')],
              kit_key(parent, 'D') => [kit_key(child, secret)] }
    [parent, dcf_set_dependencies(child, value_dependencies: links)]
  end

  def hide(field)
    field.update!(visible: false, role_ids: [other_role.id])
    field
  end

  def read_only(issue, field, rule_role: role, status_id: issue.status_id, tracker_id: issue.tracker_id)
    WorkflowPermission.find_or_create_by!(tracker_id: tracker_id, old_status_id: status_id, role_id: rule_role.id,
                                          field_name: field.id.to_s, rule: 'readonly')
  end

  def stored_issue(values = nil)
    kit_issue(project, values || { parent => 'A', child => secret })
  end

  # What the issue paths do: init_journal, then safe_attributes= for +by+.
  def change(issue, values, by: user)
    issue = Issue.find(issue.id)
    issue.init_journal(by)
    issue.send(:safe_attributes=, { 'custom_field_values' => values.to_h { |f, v| [f.id.to_s, v] } }, by)
    issue
  end

  def stored(record, field)
    record.class.find(record.id).custom_field_value(field)
  end

  def json_headers
    { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
  end

  def leaks?(text, field)
    text.include?(field.name) || text.include?(secret)
  end

  # The whole HTML page (FM-20b). WP-18: the head script
  # window.DependingCustomFieldData that carried every mapping is gone
  # (SD-15), so nothing is stripped any more; was the page without it.
  def body_without_mapping
    expect(response.body).not_to include('window.DependingCustomFieldData')
    response.body
  end

  def error_box
    Nokogiri::HTML(response.body).css('#errorExplanation').text
  end

  def put_form(issue, values, notes: nil)
    attributes = { custom_field_values: values.to_h { |f, v| [f.id.to_s, v] } }
    attributes[:notes] = notes if notes
    put "/issues/#{issue.id}", params: { issue: attributes }
  end

  def mail_address
    "#{user.login}@example.net"
  end

  def reply(issue, body)
    <<~MAIL
      From: #{mail_address}
      To: redmine@example.net
      Subject: Re: S [##{issue.id}]
      Message-ID: <dcf-#{SecureRandom.hex(6)}@example.net>
      Mime-Version: 1.0
      Content-Type: text/plain; charset=utf-8

      #{body}
    MAIL
  end

  def bulk(issues, values, notes: nil)
    params = { ids: issues.map(&:id), issue: { custom_field_values: values.to_h { |f, v| [f.id.to_s, v] } } }
    params[:notes] = notes if notes
    post '/issues/bulk_update', params: params
  end

  describe 'patch registration' do
    it 'prepends the check on Issue and Project only, before their own validate_custom_field_values' do
      issue_patch = RedmineDependingCustomFields::Patches::IssueValidationPatch
      project_patch = RedmineDependingCustomFields::Patches::ProjectValidationPatch
      { Issue => issue_patch, Project => project_patch }.each do |klass, patch|
        expect(klass.ancestors.index(patch)).to be < klass.ancestors.index(klass)
        expect(klass.instance_method(:validate_custom_field_values).owner).to eq(patch)
        expect(klass._validate_callbacks.count { |c| c.filter == :validate_custom_field_values }).to eq(1)
      end
      [TimeEntry, Version, User, Group].each do |klass|
        expect(klass.ancestors & [issue_patch, project_patch]).to eq([]), klass.name
      end
    end
  end

  describe 'on an issue (safe_attributes=)' do
    it 'rejects a parent change while a read-only child holds a disallowed value, named, in en and de' do
      invalid_texts.each do |locale, text|
        I18n.with_locale(locale) do
          issue = stored_issue
          read_only(issue, child)
          issue = change(issue, { parent => 'B' })
          expect(issue.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
          expect(issue.save).to be(false), locale
          expect(issue.errors[child.name]).to eq([text]), locale
          expect(issue.errors[parent.name]).to eq([]), locale
          expect([stored(issue, parent), stored(issue, child)]).to eq(['A', secret])
        end
      end
    end

    it 'rejects a parent change while a hidden child holds a disallowed value, on the parent, in en and de' do
      hide(child)
      hidden_texts.each do |locale, text|
        I18n.with_locale(locale) do
          issue = change(stored_issue, { parent => 'B' })
          expect(issue.save).to be(false), locale
          expect(issue.errors[parent.name]).to eq([text]), locale
          expect(issue.errors[child.name]).to eq([]), locale
          expect(issue.errors.full_messages).to eq(["#{parent.name} #{text}"]), locale
          expect(issue.errors.details.values.flatten.map { |d| d[:error].to_s }.join).not_to include(secret)
          expect([stored(issue, parent), stored(issue, child)]).to eq(['A', secret])
          expect(Issue.find(issue.id).journals).to be_empty
        end
      end
    end

    it 'uses the hidden placement for a child that is both read-only and hidden' do
      hide(child)
      issue = stored_issue
      read_only(issue, child)
      issue = change(issue, { parent => 'B' })
      expect(issue.valid?).to be(false)
      expect([issue.errors[parent.name], issue.errors[child.name]]).to eq([[hidden_message], []])
    end

    it 'gives one parent message for several hidden children of the same parent' do
      second = build_pair(parent: parent).last
      [child, second].each { |f| hide(f) }
      issue = change(stored_issue(parent => 'A', child => secret, second => 'a2'), { parent => 'B' })
      expect(issue.valid?).to be(false)
      expect(issue.errors[parent.name]).to eq([hidden_message])
      expect(issue.errors.full_messages).to eq(["#{parent.name} #{hidden_message}"])
    end

    # Three failing non-editable values with three distinct placements: each
    # one must be placed (a check that stops at the first would drop the
    # read-only child's name or the second parent's message). The check is
    # also run alone on a cleared error set, so ActiveRecord's removal of
    # identical errors cannot hide a count change.
    it 'places every failing non-editable value: the read-only child by name, one message per changed parent' do
      sibling = hide(build_pair(parent: parent).last)
      second_parent, second_child = build_pair
      hide(second_child)
      issue = stored_issue(parent => 'A', child => secret, sibling => secret,
                           second_parent => 'A', second_child => secret)
      read_only(issue, child)
      issue = change(issue, { parent => 'B', second_parent => 'B' })
      expected = { child.name => [invalid], parent.name => [hidden_message], second_parent.name => [hidden_message] }
      expect(issue.valid?).to be(false)
      expected.each { |attribute, messages| expect(issue.errors[attribute]).to eq(messages), attribute }
      expect([issue.errors[sibling.name], issue.errors[second_child.name]]).to eq([[], []])
      expect(issue.errors.full_messages.size).to eq(3)
      issue.errors.clear
      rules_module.validate(issue, user)
      expect(issue.errors.full_messages)
        .to match_array(expected.flat_map { |attribute, messages| messages.map { |m| "#{attribute} #{m}" } })
    end

    it 'names each read-only child once and keeps one error for an editable sibling' do
      editable = build_pair(parent: parent).last
      issue = stored_issue(parent => 'A', child => secret, editable => 'a2')
      read_only(issue, child)
      issue = change(issue, { parent => 'B' })
      expect(issue.valid?).to be(false)
      expect([issue.errors[child.name], issue.errors[editable.name]]).to eq([[invalid], [invalid]])
      expect(issue.errors.full_messages.uniq).to eq(issue.errors.full_messages)
      expect(issue.errors.full_messages.size).to eq(2)
    end

    # ActiveRecord drops identical errors after validation (autosave
    # _ensure_no_duplicate_errors), which would hide a second 'is invalid';
    # so the editable filter is pinned on the check itself.
    it 'adds no error of its own for an editable child (core reports it once)' do
      issue = change(stored_issue, { parent => 'B' })
      expect(issue.valid?).to be(false)
      expect(issue.errors[child.name]).to eq([invalid])
      issue.errors.clear
      rules_module.validate(issue, user)
      expect(issue.errors.to_a).to eq([])
    end

    it 'saves a parent change to a value that allows the stored child (A to D)' do
      hide(child)
      hidden_issue = stored_issue
      expect(change(hidden_issue, { parent => 'D' }).save).to be(true)
      expect([stored(hidden_issue, parent), stored(hidden_issue, child)]).to eq(['D', secret])
    end

    it 'saves a parent change to a value that allows a read-only child' do
      issue = stored_issue
      read_only(issue, child)
      expect(change(issue, { parent => 'D' }).save).to be(true)
      expect([stored(issue, parent), stored(issue, child)]).to eq(['D', secret])
    end

    # D1: a stored value is tolerated while the parent is unchanged.
    it 'tolerates a legacy value of a hidden or read-only child while the parent is unchanged' do
      hidden_child = hide(build_pair(parent: parent).last)
      issue = stored_issue(parent => 'A', child => 'b1', hidden_child => 'b1', other => 'X')
      read_only(issue, child)
      changed = change(issue, { other => 'Y', parent => 'A' })
      expect(changed.save).to be(true), changed.errors.full_messages.inspect
      expect([stored(issue, other), stored(issue, child), stored(issue, hidden_child)]).to eq(%w[Y b1 b1])
    end

    # B allows b1, so the required bypass (no options) does not apply: core's
    # own check of the child would add 'cannot be blank' (precondition).
    { 'read-only' => :read_only, 'hidden' => :hide }.each do |label, restriction|
      it "applies no core check to a #{label} child: a blank required child saves when the parent changes" do
        child.update!(is_required: true)
        issue = stored_issue(parent => 'A', child => '')
        restriction == :hide ? hide(child) : read_only(issue, child)
        changed = change(issue, { parent => 'B' })
        expect(changed.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
        value = changed.custom_field_values.detect { |v| v.custom_field_id == child.id }
        expect(child.validate_custom_value(value)).to include(I18n.t('activerecord.errors.messages.blank'))
        expect(changed.save).to be(true), changed.errors.full_messages.inspect
        expect([stored(issue, parent), stored(issue, child).to_s]).to eq(['B', ''])
      end
    end

    # A regression pin only: core's list check tolerates an unchanged value
    # too (it subtracts value_was), so the absence of core checks is pinned
    # by the blank required examples above.
    it 'keeps a removed list value of a non-editable child while the parent is unchanged' do
      hide(child)
      issue = stored_issue(parent => 'A', child => 'gone', other => 'X')
      expect(issue.custom_field_value(child)).to eq('gone')
      changed = change(issue, { other => 'Y' })
      expect(changed.save).to be(true), changed.errors.full_messages.inspect
      expect(stored(issue, child)).to eq('gone')
    end

    it 'leaves a non-editable multiple child untouched: same rows and no journal detail' do
      multi = hide(build_pair(parent: parent, multiple: true).last)
      issue = stored_issue(parent => 'A', multi => [secret, 'a2'], other => 'X')
      rows = CustomValue.where(customized: issue, custom_field: multi).order(:id).pluck(:id, :value)
      changed = change(issue, { other => 'Y' })
      expect(changed.save).to be(true), changed.errors.full_messages.inspect
      expect(CustomValue.where(customized: issue, custom_field: multi).order(:id).pluck(:id, :value)).to eq(rows)
      expect(JournalDetail.where(property: 'cf', prop_key: multi.id.to_s)).to be_empty
    end

    it 'follows a read-only rule of the status the same request moves to' do
      issue = stored_issue
      target = dcf_issue_status
      read_only(issue, child, status_id: target.id)
      issue = Issue.find(issue.id)
      issue.init_journal(user)
      issue.status = target
      issue.send(:safe_attributes=, { 'custom_field_values' => { parent.id.to_s => 'B' } }, user)
      expect(issue.valid?).to be(false)
      expect(issue.errors[child.name]).to eq([invalid])
    end

    describe 'the user core validates with' do
      # The journal user, not User.current (the plugin uses the same user).
      # other_role (edit_issues, no read-only rule) is a workflow role of the
      # administrator, so the child is editable for User.current and only the
      # journal user's classification gives 'is invalid' (precondition).
      it 'classifies by the journal user when User.current differs (read-only for the journal user)' do
        other_role
        allow(User).to receive(:current).and_return(dcf_admin)
        issue = stored_issue
        read_only(issue, child)
        expect(Issue.find(issue.id).editable_custom_field_values(dcf_admin).map(&:custom_field_id)).to include(child.id)
        issue = change(issue, { parent => 'B' })
        expect(issue.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
        expect(issue.valid?).to be(false)
        expect(issue.errors[child.name]).to eq([invalid])
      end

      it 'classifies by the journal user when User.current differs (editable for the journal user)' do
        hide(child)
        allow(User).to receive(:current).and_return(user)
        issue = change(stored_issue, { parent => 'B' }, by: dcf_admin)
        expect(issue.valid?).to be(false)
        expect([issue.errors[child.name], issue.errors[parent.name]]).to eq([[invalid], []])
      end

      it 'falls back to User.current when no journal is started' do
        hide(child)
        { user => [[], [hidden_message]], dcf_admin => [[invalid], []] }.each do |current, expected|
          allow(User).to receive(:current).and_return(current)
          issue = Issue.find(stored_issue.id)
          issue.custom_field_values = { parent.id.to_s => 'B' }
          expect(issue.valid?).to be(false)
          expect([issue.errors[child.name], issue.errors[parent.name]]).to eq(expected), current.login
        end
      end

      it 'classifies a new issue by its author and judges a stale non-editable default strictly' do
        hide(child)
        child.update_column(:default_value, 'b1')
        allow(User).to receive(:current).and_return(dcf_admin)
        issue = kit_new_issue(project, parent => 'C', child => secret)
        issue.author = user
        expect(issue.valid?).to be(false)
        # Core reset the child the author cannot edit to its default (b1),
        # which C does not allow; new issues have no baseline.
        expect(issue.custom_field_value(child)).to eq('b1')
        expect([issue.errors[child.name], issue.errors[parent.name]]).to eq([[], [hidden_message]])
      end

      it 'creates a new issue whose hidden child has no default (core resets it to blank)' do
        hide(child)
        allow(User).to receive(:current).and_return(user)
        issue = kit_new_issue(project, parent => 'B', child => secret)
        issue.author = user
        expect(issue.save).to be(true), issue.errors.full_messages.inspect
        expect(stored(issue, child)).to be_blank
      end
    end

    describe 'administrators' do
      it 'see a role-hidden child, so core names it once and the parent gets no message' do
        hide(child)
        issue = change(stored_issue, { parent => 'B' }, by: dcf_admin)
        expect(issue.valid?).to be(false)
        expect([issue.errors[child.name], issue.errors[parent.name]]).to eq([[invalid], []])
      end

      it 'get is invalid under the child name when a read-only rule applies to every workflow role' do
        issue = stored_issue
        role
        other_role
        Role.all.to_a.select(&:consider_workflow?).each { |r| read_only(issue, child, rule_role: r) }
        issue = change(issue, { parent => 'B' }, by: dcf_admin)
        expect(issue.editable_custom_field_values(dcf_admin).map(&:custom_field_id)).not_to include(child.id)
        expect(issue.valid?).to be(false)
        expect([issue.errors[child.name], issue.errors[parent.name]]).to eq([[invalid], []])
      end
    end
  end

  describe 'REST API (PUT /issues/:id.json)' do
    before { allow(User).to receive(:current).and_return(user) }

    def put_issue(issue, attributes)
      put "/issues/#{issue.id}.json", params: { issue: attributes }.to_json, headers: json_headers
    end

    { 'a list' => :list, 'an enumeration' => :enum }.each do |label, kind|
      context "with #{label} child" do
        let(:kit) { build_pair(kind: kind) }

        def stored_keys(record)
          [stored(record, parent), stored(record, child)]
        end

        it 'answers 422 with is invalid under a read-only child, in en and de' do
          invalid_texts.each do |language, text|
            user.update_column(:language, language)
            issue = stored_issue
            read_only(issue, child)
            put_issue(issue, custom_fields: [{ id: parent.id, value: kit_key(parent, 'B') }])
            expect(response).to have_http_status(422), response.body
            expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{text}"]), language
            expect(stored_keys(issue)).to eq([kit_key(parent, 'A'), kit_key(child, secret)])
            expect(Issue.find(issue.id).journals).to be_empty
          end
        end

        it 'answers 422 with the parent message for a hidden child, without its name or value, in en and de' do
          hide(child)
          hidden_texts.each do |language, text|
            user.update_column(:language, language)
            issue = stored_issue
            put_issue(issue, custom_fields: [{ id: parent.id, value: kit_key(parent, 'B') }])
            expect(response).to have_http_status(422), response.body
            expect(JSON.parse(response.body)['errors']).to eq(["#{parent.name} #{text}"]), language
            expect(leaks?(response.body, child)).to be(false), response.body
            expect(stored_keys(issue)).to eq([kit_key(parent, 'A'), kit_key(child, secret)])
            expect(Issue.find(issue.id).journals).to be_empty
          end
        end

        it 'answers 422 with one parent message for a hidden multiple child holding the secret value and a2' do
          multi = hide(build_pair(kind: kind, parent: parent, multiple: true).last)
          issue = stored_issue(parent => 'A', multi => [secret, 'a2'])
          expect(Array(stored(issue, multi))).to match_array(kit_value(multi, [secret, 'a2']))
          put_issue(issue, custom_fields: [{ id: parent.id, value: kit_key(parent, 'B') }])
          expect(response).to have_http_status(422), response.body
          expect(JSON.parse(response.body)['errors']).to eq(["#{parent.name} #{hidden_message}"])
          expect(leaks?(response.body, multi)).to be(false), response.body
          expect(stored(issue, parent)).to eq(kit_key(parent, 'A'))
        end
      end
    end

    it 'saves a notes-only update while a hidden child holds a legacy value' do
      hide(child)
      issue = stored_issue(parent => 'A', child => 'b1')
      put_issue(issue, notes: 'Only a note')
      expect(response).to have_http_status(204), response.body
      expect(Issue.find(issue.id).journals.last.notes).to eq('Only a note')
    end

    it 'saves a parent change to a value that allows the hidden child' do
      hide(child)
      issue = stored_issue
      put_issue(issue, custom_fields: [{ id: parent.id, value: 'D' }])
      expect(response).to have_http_status(204), response.body
      expect([stored(issue, parent), stored(issue, child)]).to eq(['D', secret])
    end
  end

  # UD-05: for a child the user can edit, a parent that is not available
  # counts as changed, so a non-blank child must be cleared. WP-09c (owner):
  # for a child the user cannot edit nobody changed the parent, so an
  # unavailable parent counts as an unchanged one: the stored value is
  # tolerated and a tracker or project change that drops the parent saves.
  describe 'a tracker change that makes the parent unavailable (UD-05, WP-09c)' do
    before { allow(User).to receive(:current).and_return(user) }

    def child_only_tracker
      tracker = dcf_tracker
      tracker.custom_fields << child
      project.trackers << tracker
      tracker
    end

    def put_tracker(issue, tracker)
      put "/issues/#{issue.id}.json", params: { issue: { tracker_id: tracker.id } }.to_json, headers: json_headers
    end

    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 refusal with the base
    # message.
    it 'saves it for a hidden child and keeps the stored value (Flipped by WP-09c)' do
      hide(child)
      issue = stored_issue
      tracker = child_only_tracker
      put_tracker(issue, tracker)
      expect(response).to have_http_status(204), response.body
      expect(Issue.find(issue.id).tracker_id).to eq(tracker.id)
      expect(stored(issue, child)).to eq(secret)
    end

    # The child stays visible (no hide): read-only by workflow under the new
    # tracker's default status, which the move gives the issue.
    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 refusal with is invalid
    # under the child name.
    it 'saves it for a read-only child the user can see and keeps the stored value (Flipped by WP-09c)' do
      issue = stored_issue
      tracker = child_only_tracker
      read_only(issue, child, tracker_id: tracker.id, status_id: tracker.default_status_id)
      moved = Issue.find(issue.id)
      moved.init_journal(user)
      moved.send(:safe_attributes=, { 'tracker_id' => tracker.id.to_s }, user)
      expect([moved.tracker_id, moved.status_id]).to eq([tracker.id, tracker.default_status_id])
      expect(moved.visible_custom_field_values(user).map(&:custom_field_id)).to include(child.id)
      expect(moved.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
      put_tracker(issue, tracker)
      expect(response).to have_http_status(204), response.body
      expect(Issue.find(issue.id).tracker_id).to eq(tracker.id)
      expect(stored(issue, child)).to eq(secret)
    end

    # A project move where the parent field is not enabled works like a
    # tracker change (core reassign_custom_field_values).
    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 refusal with the base
    # message.
    it 'saves a REST move to a project where the parent field is not enabled (Flipped by WP-09c)' do
      hide(child)
      parent.update!(is_for_all: false, project_ids: [project.id])
      issue = stored_issue
      target = dcf_create_project
      dcf_add_member(user, target, role)
      dcf_issue_infra(target)
      expect(Issue.find(issue.id).allowed_target_projects(user)).to include(target)
      put "/issues/#{issue.id}.json", params: { issue: { project_id: target.id } }.to_json, headers: json_headers
      expect(response).to have_http_status(204), response.body
      expect(Issue.find(issue.id).project_id).to eq(target.id)
      expect(stored(issue, child)).to eq(secret)
    end

    # UD-05 for a child the user can edit (core validates it through the
    # format): the unavailable parent counts as changed, in en and de.
    it 'still refuses it for a child the user can edit, with is invalid under the child name (UD-05)' do
      invalid_texts.each do |language, text|
        user.update_column(:language, language)
        issue = stored_issue
        tracker = child_only_tracker
        moved = Issue.find(issue.id)
        moved.init_journal(user)
        moved.send(:safe_attributes=, { 'tracker_id' => tracker.id.to_s }, user)
        expect(moved.tracker_id).to eq(tracker.id)
        expect(moved.editable_custom_field_values(user).map(&:custom_field_id)).to include(child.id)
        put_tracker(issue, tracker)
        expect(response).to have_http_status(422), response.body
        expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{text}"]), language
        expect(Issue.find(issue.id).tracker_id).to eq(issue.tracker_id)
      end
    end

    # An administrator sees the role-hidden child and may edit it, so core
    # validates it (UD-05).
    it 'refuses it for an administrator with is invalid under the child name' do
      hide(child)
      allow(User).to receive(:current).and_return(dcf_admin)
      issue = stored_issue
      put_tracker(issue, child_only_tracker)
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
    end

    it 'still saves a notes-only update on such an issue' do
      hide(child)
      issue = stored_issue
      issue.tracker.custom_fields.delete(parent)
      put "/issues/#{issue.id}.json", params: { issue: { notes: 'Note' } }.to_json, headers: json_headers
      expect(response).to have_http_status(204), response.body
    end

    # A tracker change that makes the hidden child available too gives it
    # its default (core set_custom_field_default?): no stored row, so nothing
    # is tolerated, and the unavailable parent allows nothing. Nobody changed
    # the parent, so the message goes on base.
    it 'still refuses a move that gives a hidden child a stale default under an unavailable parent' do
      hide(child)
      child.update_column(:default_value, 'b1')
      issue = stored_issue(parent => 'A')
      expect(issue.available_custom_fields).not_to include(child)
      put_tracker(issue, child_only_tracker)
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq([base_message])
      expect(leaks?(response.body, child)).to be(false), response.body
      expect(Issue.find(issue.id).tracker_id).to eq(issue.tracker_id)
    end
  end

  # WP-09c (owner): while the parent field is not available on the issue
  # (here disabled for its tracker), it does not count as changed for a
  # child the user cannot edit, so saves that assign custom values without
  # touching the parent keep the child's stored value and succeed. Before
  # WP-09c (UD-05 steady state) each of them was refused. A child the user
  # can edit keeps UD-05, and a parent that is available again and changes
  # is judged strictly (WP-09b).
  describe 'an issue whose parent field is disabled for its tracker (WP-09c)' do
    before { allow(User).to receive(:current).and_return(user) }

    def blocked_issue(hidden: true)
      hide(child) if hidden
      issue = stored_issue(parent => 'A', child => secret, other => 'X')
      issue.tracker.custom_fields.delete(parent)
      Issue.find(issue.id)
    end

    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 steady-state refusal
    # with the base message.
    it 'saves a form edit that changes only another field (Flipped by WP-09c)' do
      issue = blocked_issue
      put_form(issue, { other => 'Y' })
      expect(response).to have_http_status(302)
      expect([stored(issue, other), stored(issue, child)]).to eq(['Y', secret])
    end

    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 steady-state refusal
    # with the base message.
    it 'saves a form edit with only a note (the form posts the editable custom values unchanged) ' \
       '(Flipped by WP-09c)' do
      issue = blocked_issue
      put_form(issue, { other => 'X' }, notes: 'Only a note')
      expect(response).to have_http_status(302)
      expect(Issue.find(issue.id).journals.map(&:notes)).to eq(['Only a note'])
      expect(stored(issue, child)).to eq(secret)
    end

    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 steady-state refusal
    # with the base message.
    it 'saves a bulk edit with only a note (the bulk form posts blank custom values) (Flipped by WP-09c)' do
      issue = blocked_issue
      bulk([issue], { other => '' }, notes: 'Only a note')
      expect(response).to have_http_status(302)
      expect(Issue.find(issue.id).journals.map(&:notes)).to eq(['Only a note'])
      expect([stored(issue, other), stored(issue, child)]).to eq(['X', secret])
    end

    # The wizard saves without a journal, so core and the check use
    # User.current.
    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 steady-state refusal
    # with the base message.
    it 'saves a wizard save that changes only another field (Flipped by WP-09c)' do
      issue = blocked_issue
      post '/depending_custom_fields/save',
           params: { issue_ids: issue.id.to_s, issue: { custom_field_values: { other.id.to_s => 'Y' } } }
      expect(response).to have_http_status(200), response.body
      expect(leaks?(response.body, child)).to be(false), response.body
      expect([stored(issue, other), stored(issue, child)]).to eq(['Y', secret])
    end

    # MailHandler always assigns custom values.
    # Flipped by WP-09c (owner: unavailable parent does not count as changed
    # for non-editable children). It pinned the UD-05 steady-state refusal
    # (the notes were lost).
    it 'adds a notes-only mail reply (Flipped by WP-09c)' do
      issue = blocked_issue
      EmailAddress.create!(user: user, address: mail_address, is_default: true)
      expect(MailHandler.receive(reply(issue, 'Only a note by mail'))).to be_a(Journal)
      expect(Issue.find(issue.id).journals.map(&:notes)).to eq(['Only a note by mail'])
      expect(stored(issue, child)).to eq(secret)
    ensure
      User.current = nil
    end

    # The same for a read-only child the user can see, on the model: no
    # error at all (before WP-09c: is invalid under the child name).
    it 'saves a change of another field while a read-only child holds a value (WP-09c)' do
      issue = blocked_issue(hidden: false)
      read_only(issue, child)
      changed = change(issue, { other => 'Y' })
      expect(changed.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
      expect(changed.custom_field_values.map(&:custom_field_id)).not_to include(parent.id)
      expect(changed.save).to be(true), changed.errors.full_messages.inspect
      expect([stored(issue, other), stored(issue, child)]).to eq(['Y', secret])
    end

    # UD-05 for a child the user can edit: the form edit is refused with is
    # invalid under the child name, so the child must be cleared.
    it 'still refuses a form edit that changes only another field for a child the user can edit (UD-05)' do
      issue = blocked_issue(hidden: false)
      expect(issue.editable_custom_field_values(user).map(&:custom_field_id)).to include(child.id)
      put_form(issue, { other => 'Y' })
      expect(response).to have_http_status(200)
      expect(error_box).to include("#{child.name} #{invalid}")
      expect([stored(issue, other), stored(issue, child)]).to eq(['X', secret])
      cleared = change(issue, { other => 'Y', child => '' })
      expect(cleared.save).to be(true), cleared.errors.full_messages.inspect
    end

    # WP-09b: once the parent field is available again (its stored row
    # kept) and its value changes, the hidden child is judged strictly.
    it 'still refuses a change of the parent once it is available again (WP-09b)' do
      issue = blocked_issue
      issue.tracker.custom_fields << parent
      put_form(Issue.find(issue.id), { parent => 'B' })
      expect(response).to have_http_status(200)
      expect(error_box).to include("#{parent.name} #{hidden_message}")
      expect(leaks?(body_without_mapping, child)).to be(false)
      expect([stored(issue, parent), stored(issue, child)]).to eq(['A', secret])
    end
  end

  describe 'a parent the user cannot see either' do
    before { allow(User).to receive(:current).and_return(user) }

    # The parent gets its default through a tracker change (core
    # set_custom_field_default?); naming it would show a hidden field.
    it 'puts the message on base' do
      hide(parent)
      hide(child)
      parent.update!(default_value: 'B')
      issue = stored_issue(child => secret)
      tracker = dcf_tracker
      [parent, child].each { |f| tracker.custom_fields << f }
      project.trackers << tracker
      put "/issues/#{issue.id}.json", params: { issue: { tracker_id: tracker.id } }.to_json, headers: json_headers
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq([base_message])
      expect(leaks?(response.body, parent) || leaks?(response.body, child)).to be(false), response.body
    end
  end

  # A tracker change that makes a hidden child available gives it its
  # default (core set_custom_field_default?), which the unchanged, available
  # parent value A does not allow (a stale default: legacy rows or direct DB
  # writes). The user changed no parent value, so the message goes on base,
  # not on the parent.
  describe 'a tracker change that gives a hidden child a stale default under an unchanged parent' do
    before { allow(User).to receive(:current).and_return(user) }

    it 'refuses it with the base message' do
      hide(child)
      child.update_column(:default_value, 'b1')
      issue = stored_issue(parent => 'A')
      expect(issue.available_custom_fields).not_to include(child)
      tracker = dcf_tracker
      [parent, child].each { |f| tracker.custom_fields << f }
      project.trackers << tracker
      put "/issues/#{issue.id}.json", params: { issue: { tracker_id: tracker.id } }.to_json, headers: json_headers
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq([base_message])
      expect(leaks?(response.body, child)).to be(false), response.body
      expect(Issue.find(issue.id).tracker_id).to eq(issue.tracker_id)
    end
  end

  describe 'issue form (PUT /issues/:id)' do
    before { allow(User).to receive(:current).and_return(user) }

    it 're-renders the form with the parent message for a hidden child, never naming it' do
      hide(child)
      issue = stored_issue
      put_form(issue, { parent => 'B' })
      expect(response).to have_http_status(200)
      expect(error_box).to include("#{parent.name} #{hidden_message}")
      expect(response.body).not_to include(child.name)
      expect(leaks?(body_without_mapping, child)).to be(false)
      expect(stored(issue, parent)).to eq('A')
    end

    # The legacy script (0.1.0 (M1) and earlier) cleared an editable
    # dependent field whose stored value its own parent does not allow and
    # posted ''. That changes the parent of a hidden child below it, which
    # is then judged strictly: the save is refused (UD-07). WP-18: the new
    # runtime keeps such a value and posts it unchanged (the notes-only save
    # is shown by spec/system/depending_fields_frontend_spec.rb); the server
    # rule for a post that clears it is unchanged.
    it 'refuses a save that clears an editable dependent field above a hidden child (legacy script post)' do
      grand = dcf_list_field(values: %w[G H], name: "Grand#{SecureRandom.hex(4)}")
      middle = dcf_list_field(format: 'depending_list', values: %w[p1 p2], parent: grand,
                              name: "Middle#{SecureRandom.hex(4)}")
      middle = dcf_set_dependencies(middle, value_dependencies: { 'G' => ['p1'] })
      low = dcf_list_field(format: 'depending_list', values: [secret], parent: middle, name: "Low#{SecureRandom.hex(4)}")
      low = hide(dcf_set_dependencies(low, value_dependencies: { 'p2' => [secret] }))
      issue = kit_issue(project, grand => 'G', middle => 'p2', low => secret)
      put_form(issue, { middle => '' }, notes: 'Only a note')
      expect(response).to have_http_status(200)
      expect(error_box).to include("#{middle.name} #{hidden_message}")
      expect(leaks?(body_without_mapping, low)).to be(false)
      expect([stored(issue, middle), stored(issue, low)]).to eq(['p2', secret])
      expect(Issue.find(issue.id).journals).to be_empty
    end

    it 're-renders the form with is invalid under a read-only child' do
      issue = stored_issue
      read_only(issue, child)
      put_form(issue, { parent => 'B' })
      expect(response).to have_http_status(200)
      expect(error_box).to include("#{child.name} #{invalid}")
      expect(stored(issue, parent)).to eq('A')
    end
  end

  describe 'bulk update (POST /issues/bulk_update)' do
    before { allow(User).to receive(:current).and_return(user) }

    it 'refuses the issues whose hidden child blocks the change and saves the others' do
      hide(child)
      blocked = stored_issue
      free = stored_issue(parent => 'A')
      bulk([blocked, free], { parent => 'B' })
      expect(response).to have_http_status(200)
      expect(response.body).to include(CGI.escapeHTML("#{parent.name} #{hidden_message}: ##{blocked.id}"))
      expect(response.body).not_to include(child.name)
      expect(leaks?(body_without_mapping, child)).to be(false)
      expect([stored(blocked, parent), stored(free, parent)]).to eq(%w[A B])
    end

    it 'lists a read-only child by name' do
      blocked = stored_issue
      read_only(blocked, child)
      bulk([blocked], { parent => 'B' })
      expect(response).to have_http_status(200)
      expect(response.body).to include(CGI.escapeHTML("#{child.name} #{invalid}: ##{blocked.id}"))
      expect(stored(blocked, parent)).to eq('A')
    end
  end

  describe 'context menu wizard (POST /depending_custom_fields/save)' do
    before { allow(User).to receive(:current).and_return(user) }

    def wizard(issue, values)
      post '/depending_custom_fields/save',
           params: { issue_ids: issue.id.to_s,
                     issue: { custom_field_values: values.to_h { |f, v| [f.id.to_s, v] } } }
    end

    it 'answers 422 with the parent message for a hidden child' do
      hide(child)
      issue = stored_issue
      wizard(issue, parent => 'B')
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq(["#{parent.name} #{hidden_message}"])
      expect(leaks?(response.body, child)).to be(false), response.body
      expect(stored(issue, parent)).to eq('A')
    end

    it 'answers 422 with is invalid under a read-only child' do
      issue = stored_issue
      read_only(issue, child)
      wizard(issue, parent => 'B')
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
    end

    it 'saves an unrelated value while the parent is unchanged and a hidden child holds a legacy value' do
      hide(child)
      issue = stored_issue(parent => 'A', child => 'b1', other => 'X')
      wizard(issue, other => 'Y')
      expect(response).to have_http_status(200), response.body
      expect([stored(issue, other), stored(issue, child)]).to eq(%w[Y b1])
    end
  end

  describe 'mail reply' do
    before { EmailAddress.create!(user: user, address: mail_address, is_default: true) }
    after { User.current = nil }

    it 'refuses a reply that changes the parent by keyword while a hidden child blocks it' do
      hide(child)
      issue = stored_issue
      expect(MailHandler.receive(reply(issue, "#{parent.name}: B\n\nA reply"), allow_override: 'all')).to be(false)
      expect(stored(issue, parent)).to eq('A')
      expect(Issue.find(issue.id).journals).to be_empty
    end

    it 'adds a notes-only reply while a hidden child holds a legacy value' do
      hide(child)
      issue = stored_issue(parent => 'A', child => 'b1')
      journal = MailHandler.receive(reply(issue, 'A reply by mail'))
      expect(journal).to be_a(Journal)
      expect(stored(issue, child)).to eq('b1')
    end
  end

  # Copies are new records: core resets every value the author cannot edit
  # to the field default before validation, so a non-editable child never
  # keeps the source value. A stale non-blank default is judged against the
  # source like any copied value (UD-06).
  describe 'issue copies' do
    before { allow(User).to receive(:current).and_return(user) }

    it 'saves a copy with a changed parent; the hidden child is reset to blank by core' do
      hide(child)
      copy = Issue.new.copy_from(stored_issue)
      copy.custom_field_values = { parent.id.to_s => 'B' }
      expect(copy.save).to be(true), copy.errors.full_messages.inspect
      expect([stored(copy, parent), stored(copy, child).to_s]).to eq(['B', ''])
    end

    it 'saves a copy whose read-only child is reset to blank by core' do
      source = stored_issue
      read_only(source, child, status_id: source.tracker.default_status_id)
      copy = Issue.new.copy_from(source)
      copy.custom_field_values = { parent.id.to_s => 'B' }
      expect(copy.save).to be(true), copy.errors.full_messages.inspect
      expect(stored(copy, child)).to be_blank
    end

    it 'judges a stale default of a hidden child against the source (UD-06)' do
      hide(child)
      child.update_column(:default_value, 'b1')
      source = stored_issue(parent => 'A', child => 'b1')
      unchanged = Issue.new.copy_from(source)
      expect(unchanged.save).to be(true), unchanged.errors.full_messages.inspect
      expect(stored(unchanged, child)).to eq('b1')

      changed = Issue.new.copy_from(source)
      changed.custom_field_values = { parent.id.to_s => 'C' }
      expect(changed.save).to be(false)
      expect([changed.errors[parent.name], changed.errors[child.name]]).to eq([[hidden_message], []])
    end

    # The copier leaves the parent A as the source holds it; core resets the
    # hidden child to its stale default b1, which A does not allow and the
    # source never held. Nobody changed the parent, so the message goes on
    # base, not on the parent ('cannot be changed ... the new value').
    it 'puts the message on base when the copy keeps the parent and core gives the hidden child a stale default' do
      hide(child)
      child.update_column(:default_value, 'b1')
      copy = Issue.new.copy_from(stored_issue)
      expect(copy.save).to be(false)
      expect([copy.custom_field_value(parent), copy.custom_field_value(child)]).to eq(%w[A b1])
      expect([copy.errors[parent.name], copy.errors[child.name]]).to eq([[], []])
      expect(copy.errors.full_messages).to eq([base_message])
    end

    # WP-09c: a parent that is not available on the copy (disabled for the
    # tracker) does not count as changed for the hidden child, so the copy is
    # judged against the source like any copy (UD-06): the source value is
    # tolerated, a stale default the source never held is refused, with the
    # base message (the parent is not on the record).
    it 'judges a hidden child against the source under an unavailable parent, with the base message (WP-09c)' do
      hide(child)
      child.update_column(:default_value, 'b1')
      kept = stored_issue(parent => 'A', child => 'b1')
      stale = stored_issue
      kept.tracker.custom_fields.delete(parent)
      allowed, refused = [kept, stale].map { |source| Issue.new.copy_from(Issue.find(source.id)) }
      expect(allowed.custom_field_values.map(&:custom_field_id)).not_to include(parent.id)
      expect(allowed.save).to be(true), allowed.errors.full_messages.inspect
      expect(stored(allowed, child)).to eq('b1')
      expect(refused.save).to be(false)
      # Core reset the hidden child to its default (b1), which the source
      # (secret) never held.
      expect(refused.custom_field_value(child)).to eq('b1')
      expect([refused.errors[parent.name], refused.errors[child.name]]).to eq([[], []])
      expect(refused.errors.full_messages).to eq([base_message])
    end

    describe 'through the controllers (the author is User.current)' do
      def post_issue(attributes, copy_from: nil)
        path = "/projects/#{project.identifier}/issues.json"
        path += "?copy_from=#{copy_from.id}" if copy_from
        post path, params: { issue: { subject: 'New' }.merge(attributes) }.to_json, headers: json_headers
      end

      before do
        hide(child)
        child.update_column(:default_value, 'b1')
      end

      it 'answers 422 to a REST copy whose changed parent does not allow the stale default, without a leak' do
        source = stored_issue
        count = Issue.count
        post_issue({ custom_fields: [{ id: parent.id, value: 'C' }] }, copy_from: source)
        expect(response).to have_http_status(422), response.body
        expect(Issue.count).to eq(count)
        expect(JSON.parse(response.body)['errors']).to eq(["#{parent.name} #{hidden_message}"])
        expect(leaks?(response.body, child)).to be(false), response.body
      end

      it 'answers 422 with the base message to a REST copy that keeps the parent, without a leak' do
        source = stored_issue
        count = Issue.count
        post_issue({}, copy_from: source)
        expect(response).to have_http_status(422), response.body
        expect(Issue.count).to eq(count)
        expect(JSON.parse(response.body)['errors']).to eq([base_message])
        expect(leaks?(response.body, child)).to be(false), response.body
      end

      it 'answers 422 to a REST create whose parent does not allow the stale default, and 201 when it does' do
        tracker, _status, priority = dcf_issue_infra(project)
        [parent, child].each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
        base = { tracker_id: tracker.id, priority_id: priority.id }
        count = Issue.count
        post_issue(base.merge(custom_fields: [{ id: parent.id, value: 'C' }]))
        expect(response).to have_http_status(422), response.body
        expect(Issue.count).to eq(count)
        expect(JSON.parse(response.body)['errors']).to eq(["#{parent.name} #{hidden_message}"])
        expect(leaks?(response.body, child)).to be(false), response.body
        post_issue(base.merge(custom_fields: [{ id: parent.id, value: 'B' }]))
        expect(response).to have_http_status(201), response.body
        expect(stored(Issue.find(JSON.parse(response.body)['issue']['id']), child)).to eq('b1')
      end

      # WP-09c: the unavailable parent (not on the tracker) does not count as
      # changed, but a new issue has no baseline, so the stale default is
      # still refused; nobody changed the parent, so the message goes on base.
      it 'answers 422 with the base message to a REST create whose parent is not available (WP-09c)' do
        tracker = dcf_tracker
        tracker.custom_fields << child
        project.trackers << tracker
        _tracker, _status, priority = dcf_issue_infra(project)
        count = Issue.count
        post_issue({ tracker_id: tracker.id, priority_id: priority.id,
                     custom_fields: [{ id: child.id, value: secret }] })
        expect(response).to have_http_status(422), response.body
        expect(Issue.count).to eq(count)
        expect(JSON.parse(response.body)['errors']).to eq([base_message])
        expect(leaks?(response.body, child)).to be(false), response.body
      end

      # Project#copy_issues copies with the copier as author; core resets the
      # hidden child to its stale default b1, which A does not allow, and
      # copy_issues only logs and skips an issue that fails validation (the
      # UI copy then redirects to the settings without a notice).
      it 'drops from a project copy by a non-administrator the issue whose stale default its parent refuses' do
        stored_issue
        stored_issue(parent => 'B', child => 'b1')
        target = Project.copy_from(project)
        target.name = 'Copy'
        target.identifier = "dcf-copy-#{SecureRandom.hex(3)}"
        # Core's final save sees the invalid issue in the association: false,
        # as for an issue whose tracker is disabled; the project is created.
        expect(target.copy(project, only: %w[issues])).to be(false)
        expect(target).to be_persisted
        copied = Issue.where(project_id: target.id).to_a
        expect(copied.map { |i| [i.custom_field_value(parent), i.custom_field_value(child)] }).to eq([%w[B b1]])
      end
    end
  end

  describe 'CSV import' do
    it 'creates the issue when the importer cannot see the child; core leaves the child blank' do
      hide(child)
      tracker, _status, priority = dcf_issue_infra(project)
      [parent, child].each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      import = IssueImport.new(user: user)
      import.settings = { 'mapping' => { 'project_id' => project.id.to_s, 'tracker' => "value:#{tracker.id}",
                                         'subject' => '0', "cf_#{parent.id}" => '1', "cf_#{child.id}" => '2' } }
      allow(User).to receive(:current).and_return(user)
      issue = import.send(:build_object, ['Imported', 'B', secret], 1)
      issue.priority ||= priority
      expect(issue.save).to be(true), issue.errors.full_messages.inspect
      expect([stored(issue, parent), stored(issue, child).to_s]).to eq(['B', ''])
    end
  end

  # Project custom fields have no workflow: a child a member cannot edit is
  # always role-invisible, so the message always goes on the parent.
  describe 'on a project' do
    let(:project_kit) { build_pair(type: ProjectCustomField) }
    let(:pparent) { project_kit.first }
    let(:pchild) { hide(project_kit.last) }
    let(:pother) { dcf_list_field(values: %w[X Y], type: ProjectCustomField) }

    def stored_project(values)
      record = dcf_create_project
      dcf_add_member(user, record, role)
      record.custom_field_values = values.to_h { |f, v| [f.id.to_s, v] }
      record.save!(validate: false)
      Project.find(record.id)
    end

    def put_project(record, fields)
      put "/projects/#{record.id}.json", params: { project: { custom_fields: fields } }.to_json, headers: json_headers
    end

    it 'refuses a parent change on the parent field, never naming the child, in en and de' do
      allow(User).to receive(:current).and_return(user)
      hidden_texts.each do |locale, text|
        I18n.with_locale(locale) do
          record = stored_project(pparent => 'A', pchild => secret)
          record.safe_attributes = { 'custom_field_values' => { pparent.id.to_s => 'B' } }
          expect(record.save).to be(false), locale
          expect(record.errors[pparent.name]).to eq([text]), locale
          expect(record.errors[pchild.name]).to eq([]), locale
          expect(stored(record, pparent)).to eq('A')
        end
      end
    end

    it 'answers 422 to a REST update without the child name or value' do
      allow(User).to receive(:current).and_return(user)
      record = stored_project(pparent => 'A', pchild => secret)
      put_project(record, [{ id: pparent.id, value: 'B' }])
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq(["#{pparent.name} #{hidden_message}"])
      expect(leaks?(response.body, pchild)).to be(false), response.body
      expect(stored(record, pparent)).to eq('A')
    end

    it 're-renders the settings page with the parent message' do
      allow(User).to receive(:current).and_return(user)
      record = stored_project(pparent => 'A', pchild => secret)
      put "/projects/#{record.id}", params: { project: { custom_field_values: { pparent.id.to_s => 'B' } } }
      expect(response).to have_http_status(200)
      expect(error_box).to include("#{pparent.name} #{hidden_message}")
      expect(response.body).not_to include(pchild.name)
      expect(leaks?(body_without_mapping, pchild)).to be(false)
      expect(stored(record, pparent)).to eq('A')
    end

    it 'names the child for an administrator (core validates it)' do
      allow(User).to receive(:current).and_return(dcf_admin)
      record = stored_project(pparent => 'A', pchild => secret)
      put_project(record, [{ id: pparent.id, value: 'B' }])
      expect(response).to have_http_status(422), response.body
      expect(JSON.parse(response.body)['errors']).to eq(["#{pchild.name} #{invalid}"])
    end

    it 'saves a parent change to a value that allows the child, and a legacy child under an unchanged parent' do
      allow(User).to receive(:current).and_return(user)
      record = stored_project(pparent => 'A', pchild => secret)
      put_project(record, [{ id: pparent.id, value: 'D' }])
      expect(response).to have_http_status(204), response.body
      legacy = stored_project(pparent => 'A', pchild => 'b1', pother => 'X')
      put_project(legacy, [{ id: pother.id, value: 'Y' }])
      expect(response).to have_http_status(204), response.body
      expect([stored(record, pparent), stored(legacy, pother), stored(legacy, pchild)]).to eq(%w[D Y b1])
    end

    # Project.copy_from clones the source's saved custom value rows, so the
    # parent reads as unchanged (A), while the child of a new project has no
    # baseline and is judged strictly. Nobody changed the parent, so the
    # message goes on base.
    it 'judges a programmatic copy strictly (a new project has no baseline), with the base message' do
      allow(User).to receive(:current).and_return(user)
      copies = [secret, 'b1'].map do |value|
        copy = Project.copy_from(stored_project(pparent => 'A', pchild => value))
        copy.name = "Copy #{value}"
        copy.identifier = "dcf-#{SecureRandom.hex(4)}"
        copy
      end
      allowed, legacy = copies
      expect(allowed.save).to be(true), allowed.errors.full_messages.inspect
      expect(legacy.save).to be(false)
      expect(RedmineDependingCustomFields::DependencyRules.parent_state(pchild, legacy).changed?).to be(false)
      expect([legacy.errors[pparent.name], legacy.errors[pchild.name]]).to eq([[], []])
      expect(legacy.errors.full_messages).to eq([base_message])
    end

    # A new project gets the default of a field the user cannot see:
    # safe_attributes= drops the posted value and core's CustomValue gives the
    # default (set_custom_field_default? is new_record?). A new project has no
    # baseline, so a stale default the posted parent value does not allow
    # refuses the create. The UI copy is admin-only (core validates every
    # field for an administrator).
    it 'answers 422 to a REST project create whose parent does not allow the stale hidden default, 201 when it does' do
      allow(User).to receive(:current).and_return(user)
      dcf_add_member(user, dcf_create_project, dcf_create_role(permissions: [:add_project]))
      pchild.update_column(:default_value, 'b1')
      count = Project.count
      create = lambda do |value|
        fields = [{ id: pparent.id, value: value }, { id: pchild.id, value: secret }]
        attributes = { name: "New #{value}", identifier: "dcf-new-#{SecureRandom.hex(4)}", custom_fields: fields }
        post '/projects.json', params: { project: attributes }.to_json, headers: json_headers
      end
      create.call('C')
      expect(response).to have_http_status(422), response.body
      expect(Project.count).to eq(count)
      expect(JSON.parse(response.body)['errors']).to eq(["#{pparent.name} #{hidden_message}"])
      expect(leaks?(response.body, pchild)).to be(false), response.body
      create.call('B')
      expect(response).to have_http_status(201), response.body
      created = Project.find(JSON.parse(response.body)['project']['id'])
      expect([stored(created, pparent), stored(created, pchild)]).to eq(%w[B b1])
    end
  end

  describe 'other customizables (core validates every value)' do
    it 'names a hidden version child once and adds nothing on the parent' do
      vparent, vchild = build_pair(type: VersionCustomField)
      vchild.update!(visible: false)
      allow(User).to receive(:current).and_return(user)
      version = Version.new(project: project, name: "V-#{SecureRandom.hex(3)}")
      version.custom_field_values = { vparent.id.to_s => 'A', vchild.id.to_s => secret }
      version.save!(validate: false)
      version = Version.find(version.id)
      expect(version.editable_custom_field_values(user).map(&:custom_field_id)).not_to include(vchild.id)
      version.custom_field_values = { vparent.id.to_s => 'B' }
      expect(version.valid?).to be(false)
      expect([version.errors[vchild.name], version.errors[vparent.name]]).to eq([[invalid], []])
    end
  end

  describe 'query cost' do
    before { allow(User).to receive(:current).and_return(user) }

    it 'adds no query when every depending child passes' do
      hide(child)
      prepared = Array.new(3) { change(stored_issue(parent => 'A', child => secret, other => 'X'), { other => 'Y' }) }
      expect(prepared[0].valid?).to be(true)
      with = dcf_count_queries { expect(prepared[1].valid?).to be(true) }
      allow(rules_module).to receive(:validate)
      without = dcf_count_queries { expect(prepared[2].valid?).to be(true) }
      expect(with).to eq(without)
    end

    it 'runs the same number of queries for 1 and 5 failing hidden children of one changed parent' do
      # Both worlds carry the same five hidden children; only the number
      # holding a value the new parent value does not allow differs.
      children = [child] + Array.new(4) { build_pair(parent: parent).last }
      children.each { |f| hide(f) }
      blank = children.to_h { |f| [f, ''] }.merge(parent => 'A')
      one = Array.new(2) { change(stored_issue(blank.merge(child => secret)), { parent => 'B' }) }
      five = Array.new(2) { change(stored_issue(blank.merge(children.to_h { |f| [f, secret] })), { parent => 'B' }) }
      [one.first, five.first].each { |issue| expect(issue.valid?).to be(false) }
      counts = [one.last, five.last].map do |issue|
        dcf_count_queries { expect(issue.valid?).to be(false) }
      end
      expect(five.last.errors[parent.name]).to eq([hidden_message])
      expect(counts.first).to eq(counts.last)
    end
  end
end
