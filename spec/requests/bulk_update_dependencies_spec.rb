# frozen_string_literal: true

require_relative '../rails_helper'

# WP-19: bulk edit, time-entry bulk edit and the context-menu wizard with
# depending children. A required managed child gets core's (none) option
# marked data-dcf-required-none (UD-10); the server still decides per record:
# a blank required child is accepted only while its parent value allows
# nothing (the CustomFieldPatch bypass), otherwise core's 'cannot be blank'
# refuses that record and nothing is cleared. Core saves each record on its
# own and re-renders bulk edit (HTTP 200, #errorExplanation) listing the
# records it could not save (QA-14, gap 12, FM-02, FM-22).
RSpec.describe 'Bulk updates of depending fields (WP-19)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:project) do
    record = dcf_create_project
    record.enabled_module_names = %w[issue_tracking time_tracking]
    record
  end
  let(:blank) { I18n.t('activerecord.errors.messages.blank') }
  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:activity) { TimeEntryActivity.create!(name: "Act-#{SecureRandom.hex(3)}", active: true) }

  before { as(dcf_admin) }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def message(klass, field, text)
    "#{klass.human_attribute_name(field.name)} #{text}"
  end

  # Parent A, B, C; A allows a1 and a2, B allows b1, C allows nothing.
  def kit(kind = :list, required: true, multiple: false, type: IssueCustomField)
    parent, child = build_kit(kind, multiple: multiple, type: type)
    child.update!(is_required: required)
    [parent, CustomField.find(child.id)]
  end

  # A required list child of +parent+ with the mapping and the multiple
  # setting of +child+ (one parent, so an untouched sibling stays valid).
  def sibling(parent, child)
    field = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: parent, multiple: child.multiple?,
                           type: child.class)
    field = dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1] })
    field.update!(is_required: true)
    CustomField.find(field.id)
  end

  def keys(values)
    values.to_h { |field, value| [field.id.to_s, value] }
  end

  def bulk_update(issues, values, extra = {})
    post '/issues/bulk_update', params: { ids: issues.map(&:id), issue: { custom_field_values: keys(values) }.merge(extra) }
  end

  def value(record, field)
    record.class.find(record.id).custom_field_value(field)
  end

  def failure_text
    doc.at_css('#errorExplanation span')&.text&.squish
  end

  def failure_items
    doc.css('#errorExplanation li').map { |li| li.text.squish }
  end

  def failed_issues(failed, total)
    I18n.t(:notice_failed_to_save_issues, count: failed.size, total: total, ids: failed.map { |i| "##{i.id}" }.join(', '))
  end

  def options_of(select)
    select.css('option').map { |o| [o['value'], o['data-dcf-required-none']] }
  end

  def time_entry(values, target = project)
    entry = TimeEntry.new(project: target, user: dcf_admin, author: dcf_admin, spent_on: Date.new(2026, 1, 1), hours: 1,
                          activity: activity)
    entry.custom_field_values = keys(values)
    entry.save!(validate: false)
    TimeEntry.find(entry.id)
  end

  def tracker_issue(tracker, values)
    _first, status, priority = dcf_issue_infra(project)
    project.trackers << tracker unless project.trackers.include?(tracker)
    values.each_key { |field| tracker.custom_fields << field unless tracker.custom_fields.include?(field) }
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin, status: status, priority: priority)
    issue.custom_field_values = keys(values)
    issue.save!(validate: false)
    Issue.find(issue.id)
  end

  describe 'the marked (none) option on the bulk forms' do
    it 'follows (No change) on a required managed child, plain core (none) on an optional one' do
      parent, required = kit
      _other, optional = kit(required: false)
      issues = [kit_issue(project, parent => 'A', required => 'a1', optional => 'a1'),
                kit_issue(project, parent => 'B', required => 'b1')]
      get '/issues/bulk_edit', params: { ids: issues.map(&:id) }
      expect(response).to have_http_status(200)

      required_select = doc.at_css("select[data-dcf-field='#{required.id}']")
      expect(options_of(required_select).first(3)).to eq([['', nil], ['__none__', '1'], ['a1', nil]])
      expect(required_select.at_css('option[value="__none__"]').text).to eq(I18n.t(:label_none))
      expect(options_of(doc.at_css("select[data-dcf-field='#{optional.id}']")).first(2)).to eq([['', nil], ['__none__', nil]])
      expect(doc.css('[data-dcf-required-none]').size).to eq(1)
      expect(doc.css('[data-dcf-blank]')).to be_empty
    end

    it 'puts the option first on a required managed multi child' do
      parent, child = kit(multiple: true)
      issues = [kit_issue(project, parent => 'A', child => %w[a1])]
      get '/issues/bulk_edit', params: { ids: issues.map(&:id) }

      expect(options_of(doc.at_css("select[data-dcf-field='#{child.id}']")).first(2)).to eq([['__none__', '1'], ['a1', nil]])
    end

    it 'is localized with core label_none in German, without a missing translation' do
      parent, child = kit
      german = dcf_create_user("de-#{SecureRandom.hex(3)}")
      german.update_columns(admin: true, language: 'de')
      as(german)
      get '/issues/bulk_edit', params: { ids: [kit_issue(project, parent => 'A', child => 'a1').id] }
      select = doc.at_css("select[data-dcf-field='#{child.id}']")

      expected = [I18n.t(:label_no_change_option, locale: :de), I18n.t(:label_none, locale: :de)]
      expect(select.css('option').first(2).map(&:text)).to eq(expected)
      expect(response.body).not_to match(/translation.missing/i)
    end

    it 'is absent for a required child whose parent the member cannot see in one selected project' do
      parent, child = kit
      member_role = dcf_create_role(permissions: [:view_issues, :edit_issues])
      other = dcf_create_project
      member = dcf_create_user("bulk-#{SecureRandom.hex(3)}")
      dcf_add_member(member, project, member_role)
      dcf_add_member(member, other, dcf_create_role(permissions: [:view_issues, :edit_issues]))
      parent.update!(visible: false, role_ids: [member_role.id])
      issues = [kit_issue(project, CustomField.find(parent.id) => 'A', child => 'a1'), kit_issue(other, child => 'a1')]
      as(member)
      get '/issues/bulk_edit', params: { ids: issues.map(&:id) }
      select = doc.at_css("select[data-dcf-field='#{child.id}']")

      expect(select['data-dcf-parent']).to be_nil
      expect(options_of(select).map(&:first)).not_to include('__none__')

      get '/issues/bulk_edit', params: { ids: [issues.first.id] }
      expect(options_of(doc.at_css("select[data-dcf-field='#{child.id}']")).map(&:first)).to include('__none__')
    end

    it 'reaches time-entry bulk edit and the context-menu wizard unchanged' do
      te_parent, te_child = kit(type: TimeEntryCustomField)
      entries = [time_entry(te_parent => 'A', te_child => 'a1'), time_entry(te_parent => 'B', te_child => 'b1')]
      get '/time_entries/bulk_edit', params: { ids: entries.map(&:id) }
      expect(response).to have_http_status(200)
      expect(options_of(doc.at_css("select[data-dcf-field='#{te_child.id}']")).first(2)).to eq([['', nil], ['__none__', '1']])

      root = dcf_list_field(values: %w[A B C])
      middle = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: root)
      middle = dcf_set_dependencies(middle, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1] })
      middle.update!(is_required: true)
      leaf = dcf_list_field(format: 'depending_list', values: %w[x1], parent: middle)
      dcf_set_dependencies(leaf, value_dependencies: { 'a1' => %w[x1] })
      issue = kit_issue(project, root => 'A', CustomField.find(middle.id) => 'a1', leaf => 'x1')
      post '/issues/context_menu', params: { ids: [issue.id] }
      expect(response).to have_http_status(200)
      template = doc.at_css("template#cf-wizard-#{root.id}")
      select = template.at_css("select[name='issue[custom_field_values][#{middle.id}]']")

      expect(options_of(select).first(2)).to eq([['', nil], ['__none__', '1']])
      expect(template.css('option[selected]')).to be_empty
      expect(template.css('[data-dcf-required-none]').size).to eq(1)
    end
  end

  describe 'POST /issues/bulk_update' do
    [:list, :enumeration].each do |kind|
      context "with a required #{kind} child" do
        it 'clears it when the parent is set to (none) in the same request' do
          parent, child = kit(kind)
          issues = [kit_issue(project, parent => 'A', child => 'a1'), kit_issue(project, parent => 'B', child => 'b1')]
          bulk_update(issues, parent => '__none__', child => '__none__')

          expect(response).to have_http_status(302)
          expect(flash[:notice]).to eq(I18n.t(:notice_successful_update))
          issues.each { |issue| expect([value(issue, parent), value(issue, child)]).to eq(['', '']) }
        end

        it 'clears it while the stored parent value allows nothing (parent (No change))' do
          parent, child = kit(kind)
          issues = [kit_issue(project, parent => 'C', child => 'a1'), kit_issue(project, parent => 'C', child => 'b1')]
          bulk_update(issues, parent => '', child => '__none__')

          expect(response).to have_http_status(302)
          issues.each { |issue| expect(value(issue, child)).to eq('') }
        end

        it 'refuses each issue whose parent value allows options with cannot be blank, clearing nothing' do
          parent, child = kit(kind)
          issues = [kit_issue(project, parent => 'A', child => 'a1'), kit_issue(project, parent => 'B', child => 'b1')]
          bulk_update(issues, parent => '', child => '__none__')

          expect(response).to have_http_status(200)
          expect(failure_text).to eq(failed_issues(issues, 2))
          expect(failure_items).to eq(["#{message(Issue, child, blank)}: #{issues.map { |i| "##{i.id}" }.join(', ')}"])
          expect(issues.map { |issue| value(issue, child) }).to eq([kit_key(child, 'a1'), kit_key(child, 'b1')])
          # The re-render selects the posted (none) (the runtime puts it back
          # on (No change) while the parent is unchanged).
          selected = doc.css("select[data-dcf-field='#{child.id}'] option[selected]")
          expect(selected.map { |o| [o['value'], o['data-dcf-required-none']] }).to eq([%w[__none__ 1]])
        end
      end

      # The marked (none) of a required multi child posts ['__none__'].
      it "clears a required #{kind} multi child posted as (none) only where the parent value allows nothing" do
        parent, child = kit(kind, multiple: true)
        cleared = kit_issue(project, parent => 'C', child => %w[a1])
        refused = kit_issue(project, parent => 'A', child => %w[a1 a2])
        bulk_update([cleared, refused], parent => '', child => ['__none__'])

        expect(response).to have_http_status(200)
        expect(failure_text).to eq(failed_issues([refused], 2))
        expect(failure_items).to eq(["#{message(Issue, child, blank)}: ##{refused.id}"])
        expect(Array(value(cleared, child)).reject(&:blank?)).to eq([])
        expect(value(refused, child)).to match_array([kit_key(child, 'a1'), kit_key(child, 'a2')])
        selected = doc.css("select[data-dcf-field='#{child.id}'] option[selected]")
        expect(selected.map { |o| [o['value'], o['data-dcf-required-none']] }).to eq([%w[__none__ 1]])
      end
    end

    it 'keeps untouched multi children, required or not, on every issue (FM-02)' do
      parent, optional = kit(required: false, multiple: true)
      required = sibling(parent, optional)
      issues = [kit_issue(project, parent => 'A', optional => %w[a1 a2], required => %w[a1 a2]),
                kit_issue(project, parent => 'B', optional => %w[b1], required => %w[b1])]
      priority = IssuePriority.create!(name: "P-#{SecureRandom.hex(3)}")
      bulk_update(issues, { parent => '' }, priority_id: priority.id)

      expect(response).to have_http_status(302)
      expect(issues.map { |issue| [value(issue, optional), value(issue, required)] }).to eq([[%w[a1 a2], %w[a1 a2]], [%w[b1], %w[b1]]])
      expect(issues.map { |issue| Issue.find(issue.id).priority_id }).to eq([priority.id, priority.id])
    end

    # QA-14, gap 12: the parent stays (No change) and the child value is
    # allowed under only one issue's parent value.
    it 'saves the issues whose parent allows the value and lists the others' do
      parent, child = kit(required: false)
      allowed = kit_issue(project, parent => 'A', child => 'a2')
      refused = kit_issue(project, parent => 'B', child => 'b1')
      bulk_update([allowed, refused], parent => '', child => 'a1')

      expect(response).to have_http_status(200)
      expect(failure_text).to eq(failed_issues([refused], 2))
      expect(failure_items).to eq(["#{message(Issue, child, invalid)}: ##{refused.id}"])
      expect(failure_text).not_to include("##{allowed.id}")
      expect([value(allowed, child), value(refused, child)]).to eq(%w[a1 b1])
      expect(doc.css('input[name="ids[]"]').map { |input| input['value'] }).to eq([refused.id.to_s])
    end

    # Gap 12: the parent is not available on the second issue's tracker, so
    # bulk edit shows no parent control; each issue is judged against its own
    # parent (an unavailable parent allows nothing and counts as changed).
    it 'judges a mixed-tracker selection per issue' do
      parent, child = kit
      with_parent = kit_issue(project, parent => 'A', child => 'a2')
      lacking = tracker_issue(dcf_tracker, child => 'b1')
      expect(lacking.available_custom_fields).not_to include(parent)
      get '/issues/bulk_edit', params: { ids: [with_parent.id, lacking.id] }

      expect(response).to have_http_status(200)
      expect(doc.css("[name='issue[custom_field_values][#{parent.id}]']")).to be_empty
      select = doc.at_css("select[data-dcf-field='#{child.id}']")
      expect(select['data-dcf-parent']).to eq(parent.id.to_s)
      expect(options_of(select).first(2)).to eq([['', nil], ['__none__', '1']])

      bulk_update([with_parent, lacking], child => 'a1')
      expect(response).to have_http_status(200)
      expect(failure_items).to eq(["#{message(Issue, child, invalid)}: ##{lacking.id}"])
      expect([value(with_parent, child), value(lacking, child)]).to eq(%w[a1 b1])

      bulk_update([with_parent, lacking], child => '__none__')
      expect(response).to have_http_status(200)
      expect(failure_items).to eq(["#{message(Issue, child, blank)}: ##{with_parent.id}"])
      expect([value(with_parent, child), value(lacking, child)]).to eq(['a1', ''])
    end

    # Gap 12: core turns every '__none__' into '' (a multi child's into
    # ['']) before the issues are saved.
    it 'clears a chain and a multi child through the parent (none) cascade' do
      root = dcf_list_field(values: %w[A B C])
      middle = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: root)
      middle = dcf_set_dependencies(middle, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1] })
      middle.update!(is_required: true)
      leaf = dcf_list_field(format: 'depending_list', values: %w[x1 y1], parent: middle)
      leaf = dcf_set_dependencies(leaf, value_dependencies: { 'a1' => %w[x1], 'b1' => %w[y1] })
      multi = dcf_list_field(format: 'depending_list', values: %w[m1 m2], parent: root, multiple: true)
      multi = dcf_set_dependencies(multi, value_dependencies: { 'A' => %w[m1 m2], 'B' => %w[m2] })
      middle = CustomField.find(middle.id)
      issues = [kit_issue(project, root => 'A', middle => 'a1', leaf => 'x1', multi => %w[m1 m2]),
                kit_issue(project, root => 'B', middle => 'b1', leaf => 'y1', multi => %w[m2])]
      post '/issues/bulk_update', params: {
        ids: issues.map(&:id),
        issue: { custom_field_values: keys(root => '__none__', middle => '__none__', leaf => '__none__', multi => ['__none__']) }
      }

      expect(response).to have_http_status(302)
      expect(flash[:notice]).to eq(I18n.t(:notice_successful_update))
      issues.each do |issue|
        expect([root, middle, leaf].map { |field| value(issue, field) }).to eq(['', '', ''])
        expect(Array(value(issue, multi)).reject(&:blank?)).to eq([])
        cleared = Issue.find(issue.id).journals.last.details.map(&:prop_key)
        expect(cleared).to include(root.id.to_s, middle.id.to_s, leaf.id.to_s, multi.id.to_s)
      end
    end

    it 'refuses a child left on (No change) under the parent (none) while it holds a value' do
      parent, child = kit(required: false)
      issues = [kit_issue(project, parent => 'A', child => 'a1'), kit_issue(project, parent => 'C', child => [])]
      bulk_update(issues, parent => '__none__', child => '')

      expect(response).to have_http_status(200)
      expect(failure_items).to eq(["#{message(Issue, child, invalid)}: ##{issues.first.id}"])
      expect([value(issues.first, parent), value(issues.first, child)]).to eq(%w[A a1])
      expect(value(issues.last, parent)).to eq('')
    end

    # Each copy is a new record judged against its own (copied) parent value.
    it 'creates the copies whose parent value allows nothing and lists the others (bulk copy)' do
      parent, child = kit
      allows_nothing = kit_issue(project, parent => 'C', child => 'a1')
      allows_options = kit_issue(project, parent => 'A', child => 'a1')

      expect do
        post '/issues/bulk_update', params: { ids: [allows_nothing.id, allows_options.id], copy: '1',
                                              issue: { custom_field_values: keys(child => '__none__') } }
      end.to change(Issue, :count).by(1)
      expect(response).to have_http_status(200)
      expect(failure_text).to eq(failed_issues([allows_options], 2))
      copy = Issue.order(:id).last
      expect([value(copy, parent), value(copy, child)]).to eq(['C', ''])
      expect([value(allows_nothing, child), value(allows_options, child)]).to eq(%w[a1 a1])
    end
  end

  describe 'POST /time_entries/bulk_update' do
    def bulk_update_entries(entries, values, extra = {})
      post '/time_entries/bulk_update',
           params: { ids: entries.map(&:id), time_entry: { custom_field_values: keys(values) }.merge(extra) }
    end

    def failed_entries(failed, total)
      I18n.t(:notice_failed_to_save_time_entries, count: failed.size, total: total,
                                                  ids: failed.map { |e| "##{e.id}" }.join(', '))
    end

    it 'keeps untouched multi children, required or not (FM-02)' do
      parent, optional = kit(required: false, multiple: true, type: TimeEntryCustomField)
      required = sibling(parent, optional)
      entries = [time_entry(parent => 'A', optional => %w[a1 a2], required => %w[a1 a2]),
                 time_entry(parent => 'B', optional => %w[b1], required => %w[b1])]
      bulk_update_entries(entries, { parent => '' }, comments: 'bulk')

      expect(response).to have_http_status(302)
      expect(entries.map { |entry| [value(entry, optional), value(entry, required)] }).to eq([[%w[a1 a2], %w[a1 a2]], [%w[b1], %w[b1]]])
      expect(entries.map { |entry| TimeEntry.find(entry.id).comments }).to eq(%w[bulk bulk])
    end

    it 'saves the entries whose parent allows the value and lists the others (QA-14)' do
      parent, child = kit(required: false, type: TimeEntryCustomField)
      allowed = time_entry(parent => 'A', child => 'a2')
      refused = time_entry(parent => 'B', child => 'b1')
      bulk_update_entries([allowed, refused], parent => '', child => 'a1')

      expect(response).to have_http_status(200)
      expect(failure_text).to eq(failed_entries([refused], 2))
      expect(failure_items).to eq(["#{message(TimeEntry, child, invalid)}: ##{refused.id}"])
      expect([value(allowed, child), value(refused, child)]).to eq(%w[a1 b1])
    end

    it 'clears a required child through (none) only where the parent value allows nothing' do
      parent, child = kit(type: TimeEntryCustomField)
      cleared = time_entry(parent => 'C', child => 'a1')
      refused = time_entry(parent => 'A', child => 'a1')
      bulk_update_entries([cleared, refused], parent => '', child => '__none__')

      expect(response).to have_http_status(200)
      expect(failure_items).to eq(["#{message(TimeEntry, child, blank)}: ##{refused.id}"])
      expect([value(cleared, child), value(refused, child)]).to eq(['', 'a1'])

      bulk_update_entries([refused], parent => '__none__', child => '__none__')
      expect(response).to have_http_status(302)
      expect([value(refused, parent), value(refused, child)]).to eq(['', ''])
    end
  end

  describe 'POST /depending_custom_fields/save (wizard)' do
    def wizard_save(issues, values)
      post '/depending_custom_fields/save', params: { ids: issues.map(&:id), issue: { custom_field_values: keys(values) } }
    end

    it 'clears a required child posted as (none) while the root allows nothing, and reports cannot be blank otherwise' do
      parent, child = kit
      issue = kit_issue(project, parent => 'A', child => 'a1')
      wizard_save([issue], parent => '__none__', child => '__none__')
      expect(response).to have_http_status(200)
      expect([value(issue, parent), value(issue, child)]).to eq(['', ''])

      other = kit_issue(project, parent => 'A', child => 'a1')
      wizard_save([other], parent => 'B', child => '__none__')
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq([message(Issue, child, blank)])
      expect([value(other, parent), value(other, child)]).to eq(%w[A a1])
    end

    # Pre-existing (WP-18): the wizard saves issue by issue, not in one
    # transaction.
    it 'saves the issues that pass before it answers 422 for the others' do
      parent, child = kit
      cleared = kit_issue(project, parent => 'C', child => 'a1')
      refused = kit_issue(project, parent => 'A', child => 'a1')
      wizard_save([cleared, refused], child => '__none__')

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq([message(Issue, child, blank)])
      expect([value(cleared, child), value(refused, child)]).to eq(['', 'a1'])
    end
  end

  describe 'security' do
    # A child the member cannot see blocks the parent (none): the message
    # names only the parent (WP-09b), never the hidden child or its value.
    it 'never names a role-invisible child or shows its value in a bulk or wizard failure' do
      secret = "Zq#{SecureRandom.hex(4)}"
      member_role = dcf_create_role(permissions: [:view_issues, :edit_issues])
      member = dcf_create_user("sec-#{SecureRandom.hex(3)}")
      dcf_add_member(member, project, member_role)
      parent = dcf_list_field(values: %w[A B], name: "#{secret}P")
      hidden = dcf_list_field(format: 'depending_list', values: ["#{secret}v"], parent: parent, name: "#{secret}H")
      hidden = dcf_set_dependencies(hidden, value_dependencies: { 'A' => ["#{secret}v"] })
      hidden.update!(visible: false, role_ids: [dcf_create_role(permissions: [:view_issues]).id])
      issue = kit_issue(project, parent => 'A', CustomField.find(hidden.id) => "#{secret}v")
      as(member)
      bulk_update([issue], parent => '__none__')

      expect(response).to have_http_status(200)
      expect(failure_items.size).to eq(1)
      expect(failure_items.first).to start_with(Issue.human_attribute_name(parent.name))
      expect(response.body).not_to include("#{secret}H")
      expect(response.body).not_to include("#{secret}v")
      expect(value(issue, parent)).to eq('A')

      post '/depending_custom_fields/save', params: { ids: [issue.id], issue: { custom_field_values: keys(parent => '__none__') } }
      expect(response).to have_http_status(422)
      errors = JSON.parse(response.body)['errors']
      expect(errors.size).to eq(1)
      expect(errors.first).to start_with(Issue.human_attribute_name(parent.name))
      expect(response.body).not_to include("#{secret}H")
      expect(response.body).not_to include("#{secret}v")
      expect(value(issue, parent)).to eq('A')
    end

    it 'escapes field names in the failure list exactly once' do
      parent = dcf_list_field(values: %w[A B C], name: %(<b>&" O'Brien))
      child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, name: '"><script>alert(1)</script>')
      child = dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      child.update!(is_required: true)
      issue = kit_issue(project, parent => 'A', CustomField.find(child.id) => 'a1')
      bulk_update([issue], parent => '', child => '__none__')

      expect(response).to have_http_status(200)
      expect(failure_items).to eq(["#{message(Issue, child, blank)}: ##{issue.id}"])
      expect(response.body).not_to include('<script>alert(1)')
      expect(response.body).not_to include('<b>&')
      expect(response.body).not_to include('&amp;lt;')
      expect(response.body).not_to include('&amp;quot;')
    end
  end
end
