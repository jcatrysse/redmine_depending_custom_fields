# frozen_string_literal: true

require_relative '../rails_helper'

# WP-09 (UD-06): issue copies are judged against their source. Core keeps the
# source in @copied_from (Issue#copy_from) and has no reader for it; copy?
# reads it. DependencyRules.baseline_source reads it while the copy is a new
# record, so a combination copied unchanged is accepted and a changed child
# or parent is validated strictly. Covered: Issue#copy, the REST copy, bulk
# copy, Project#copy_issues and subtask copies. Core's own inclusion check
# still applies to copies.
#
# Kit: parent values A, B, C; A allows a1 and a2, B allows b1, C allows
# nothing; b2 is linked under no parent value. Sources store A with b1.
RSpec.describe 'Depending fields on issue copies (UD-06)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:inclusion) { I18n.t('activerecord.errors.messages.inclusion') }
  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :copy_issues]) }
  let(:user) do
    member = dcf_create_user("copy-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:kit) { build_kit(:list, child_names: %w[a1 a2 b1 b2]) }
  let(:parent) { kit.first }
  let(:child) { kit.last }
  let(:source) { kit_issue(project, parent => 'A', child => 'b1') }

  before { allow(User).to receive(:current).and_return(user) }

  def rules
    RedmineDependingCustomFields::DependencyRules
  end

  def value_of(issue, field)
    issue.custom_field_values.detect { |v| v.custom_field_id == field.id }
  end

  def json_headers
    { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
  end

  describe 'core @copied_from (no reader in core; pinned on every supported version)' do
    # The source holds an allowed combination, so the save does not depend
    # on the D1 rule.
    it 'is the source while the copy is new, read by copy? and kept after the save' do
      origin = kit_issue(project, parent => 'A', child => 'a1')
      copy = Issue.new.copy_from(origin)

      expect(copy.copy?).to be(true)
      expect(copy.instance_variable_get(:@copied_from)).to equal(origin)
      expect(rules.baseline_source(copy)).to equal(origin)
      expect([origin.copy?, Issue.new.copy?]).to eq([false, false])
      expect(copy.save).to be(true), copy.errors.full_messages.inspect
      expect(copy.copy?).to be(true)
      expect(rules.baseline_source(copy)).to be_nil
      expect(Issue.find(copy.id).copy?).to be(false)
    end

    it 'gives a copy no stored value: value_was is the field default, never the source value' do
      parent.update!(default_value: 'B')
      copy = Issue.new.copy_from(kit_issue(project, parent => 'A', child => 'b1'))

      expect([value_of(copy, child).value, value_of(copy, child).value_was]).to eq(['b1', nil])
      expect([value_of(copy, parent).value, value_of(copy, parent).value_was]).to eq(%w[A B])
      multi_parent, multi_child = build_kit(:list, multiple: true)
      copy = Issue.new.copy_from(kit_issue(project, multi_parent => 'A', multi_child => %w[b1 a1]))
      expect(value_of(copy, multi_child).value_was).to eq([nil])
    end

    it 'has no baseline source for other records, without raising' do
      project_copy = Project.copy_from(project)
      others = [nil, Object.new, 'text', Issue.new, source, project, project_copy, Project.new, TimeEntry.new,
                Version.new, User.new]

      expect(Project.new).not_to respond_to(:copy?)
      others.each { |other| expect(rules.baseline_source(other)).to be_nil, other.class.name }
    end

    it 'falls back to strict validation when copy? is true but no usable source is kept' do
      [nil, 'not an issue', Object.new].each do |broken|
        issue = kit_new_issue(project, parent => 'A', child => 'b1')
        allow(issue).to receive(:copy?).and_return(true)
        issue.instance_variable_set(:@copied_from, broken)

        expect(rules.baseline_source(issue)).to be_nil, broken.inspect
        expect(errors_for(issue, child)).to eq([invalid]), broken.inspect
      end
      failing = kit_new_issue(project, parent => 'A', child => 'b1')
      allow(failing).to receive(:copy?).and_raise(ArgumentError)
      expect(rules.baseline_source(failing)).to be_nil
      expect(errors_for(failing, child)).to eq([invalid])
    end
  end

  describe 'Issue#copy' do
    it 'accepts and saves a legacy combination copied unchanged' do
      copy = source.copy

      expect(copy.save).to be(true), copy.errors.full_messages.inspect
      expect(Issue.find(copy.id).custom_field_value(child)).to eq('b1')
    end

    it 'rejects a copy whose child gets a new disallowed value' do
      copy = source.copy
      copy.custom_field_values = { child.id.to_s => 'b2' }
      expect(errors_for(copy, child)).to eq([invalid])
    end

    it 'accepts a copy whose child is changed to an allowed value' do
      copy = source.copy
      copy.custom_field_values = { child.id.to_s => 'a1' }
      expect(errors_for(copy, child)).to eq([])
    end

    it 'rejects a copy whose parent changes (strict)' do
      copy = source.copy
      copy.custom_field_values = { parent.id.to_s => 'C' }
      expect(errors_for(copy, child)).to eq([invalid])
    end

    it 'rejects a copy into a tracker where the parent is not available (UD-05)' do
      source
      tracker = dcf_tracker
      tracker.custom_fields << child
      project.trackers << tracker
      copy = source.copy
      copy.tracker = tracker

      expect(copy.custom_field_values.map(&:custom_field_id)).to eq([child.id])
      expect(errors_for(copy, child)).to eq([invalid])
    end

    it 'takes the parent baseline from the source, also when the parent has a default value' do
      parent.update!(default_value: 'B')
      copy = Issue.new.copy_from(kit_issue(project, parent => 'A', child => 'b1'))

      expect(value_of(copy, parent).value_was).to eq('B')
      expect(rules.parent_state(child, copy).baseline).to eq(['A'])
      expect(errors_for(copy, child)).to eq([])
    end

    context 'with a multiple enumeration child' do
      let(:kit) { build_kit(:enumeration, multiple: true, child_names: %w[a1 a2 b1 b2]) }
      let(:source) { kit_issue(project, parent => 'A', child => %w[b1 a1]) }

      it 'accepts the legacy values copied unchanged, one removed or an allowed one added' do
        [%w[b1 a1], %w[b1], %w[b1 a1 a2]].each do |names|
          copy = source.copy
          copy.custom_field_values = { child.id.to_s => kit_value(child, names) }
          expect(errors_for(copy, child)).to eq([]), names.inspect
        end
      end

      it 'rejects a new disallowed value next to the copied ones' do
        copy = source.copy
        copy.custom_field_values = { child.id.to_s => kit_value(child, %w[b1 a1 b2]) }
        expect(errors_for(copy, child)).to eq([invalid])
      end
    end

    # Core's inclusion check is untouched (server design section 8, rule 2):
    # a copy has no stored value, so core rejects a copied inactive id or a
    # copied value removed from the list, also under a parent value without
    # links where the dependency rule itself tolerates the copied value.
    context 'with values core no longer offers' do
      it 'rejects a copied inactive enumeration id with the inclusion message' do
        parent, child = build_kit(:enumeration)
        source = kit_issue(project, parent => 'C', child => 'b1')
        child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false)
        expect(errors_for(Issue.new.copy_from(Issue.find(source.id)), child)).to eq([inclusion])
      end

      it 'rejects a copied list value that was removed from the field with the inclusion message' do
        source = kit_issue(project, parent => 'C', child => 'b1')
        child.update!(possible_values: %w[a1 a2 b2])
        expect(errors_for(Issue.new.copy_from(Issue.find(source.id)), child)).to eq([inclusion])
      end
    end
  end

  describe 'REST copy (POST /projects/:id/issues.json?copy_from=)' do
    def post_copy(attributes = {})
      post "/projects/#{project.identifier}/issues.json?copy_from=#{source.id}",
           params: { issue: { subject: 'Copy' }.merge(attributes) }.to_json, headers: json_headers
    end

    it 'creates a copy holding the legacy combination when no custom field is sent' do
      source
      expect { post_copy }.to change(Issue, :count).by(1)
      expect(response).to have_http_status(201), response.body
      expect(Issue.find(JSON.parse(response.body)['issue']['id']).custom_field_value(child)).to eq('b1')
    end

    it 'rejects a copy that sends a new disallowed value, with 422' do
      source
      expect { post_copy(custom_fields: [{ id: child.id, value: 'b2' }]) }.not_to change(Issue, :count)
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to eq(["#{child.name} #{invalid}"])
    end
  end

  describe 'bulk copy (POST /issues/bulk_update with copy)' do
    def bulk_copy(values)
      post '/issues/bulk_update',
           params: { ids: [source.id], copy: '1', issue: { project_id: project.id, custom_field_values: values } }
    end

    it 'copies a legacy combination when nothing changes' do
      source
      expect { bulk_copy(parent.id.to_s => '', child.id.to_s => '') }.to change(Issue, :count).by(1)
      expect(response).to have_http_status(302)
      expect(Issue.where.not(id: source.id).last.custom_field_value(child)).to eq('b1')
    end

    it 'does not copy it when the bulk values change the parent (strict)' do
      source
      expect { bulk_copy(parent.id.to_s => 'C', child.id.to_s => '') }.not_to change(Issue, :count)
    end
  end

  describe 'Project#copy_issues' do
    let(:kit) { build_kit(:enumeration, multiple: true) }

    before { allow(User).to receive(:current).and_return(dcf_admin) }

    it 'copies every issue, legacy combinations included' do
      kit_issue(project, parent => 'A', child => %w[a1])
      kit_issue(project, parent => 'A', child => %w[b1 a1])
      target = Project.copy_from(project)
      target.name = 'Copy'
      target.identifier = "dcf-copy-#{SecureRandom.hex(3)}"
      expect(target.copy(project, only: %w[issues])).to be(true)

      copied = Issue.where(project_id: target.id).map { |i| Array(i.custom_field_value(child)).sort }
      expect(copied).to contain_exactly(kit_value(child, %w[a1]).sort, kit_value(child, %w[b1 a1]).sort)
    end
  end

  describe 'subtask copies (Issue#after_create_from_copy)' do
    it 'copies a subtask holding a legacy combination' do
      root = kit_issue(project, parent => 'A', child => 'a1')
      subtask = kit_issue(project, parent => 'A', child => 'b1')
      subtask.parent_issue_id = root.id
      subtask.save!(validate: false)
      copy = Issue.find(root.id).copy({}, subtasks: true)

      expect(copy.save).to be(true), copy.errors.full_messages.inspect
      copied = Issue.where(parent_id: copy.id).to_a
      expect(copied.map { |i| i.custom_field_value(child) }).to eq(['b1'])
    end
  end

  describe 'query invariance of copy validation' do
    # Each world has its own tracker and project; every child stores b1
    # under A (a legacy combination).
    def build_world(size)
      tracker = dcf_tracker
      world_project = dcf_create_project
      world_project.trackers << tracker unless world_project.trackers.include?(tracker)
      pairs = Array.new(size) { build_kit(:list) }
      pairs.flatten.each { |f| tracker.custom_fields << f }
      priority = IssuePriority.first || IssuePriority.create!(name: 'Normal')
      issue = Issue.new(project: world_project, tracker: tracker, subject: 'S', author: dcf_admin,
                        status: tracker.default_status, priority: priority)
      issue.custom_field_values = pairs.flat_map { |p, c| [[p.id.to_s, 'A'], [c.id.to_s, 'b1']] }.to_h
      issue.save!(validate: false)
      Issue.find(issue.id)
    end

    # A first copy warms the global caches; the second one is measured.
    def copy_validation_queries(source)
      Issue.new.copy_from(source).valid?
      copy = Issue.new.copy_from(source)
      count = dcf_count_queries { copy.valid? }
      expect(copy.errors.full_messages).to eq([])
      count
    end

    it 'runs the same number of queries for 1 and 5 legacy children' do
      allow(User).to receive(:current).and_return(dcf_admin)
      one = build_world(1)
      five = build_world(5)
      expect(copy_validation_queries(five)).to eq(copy_validation_queries(one))
    end
  end
end
