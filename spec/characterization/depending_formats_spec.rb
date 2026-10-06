# frozen_string_literal: true

require_relative '../rails_helper'

# WP-04 characterization: pins what both depending formats do today (0.0.16),
# including known defects, before the WP-05/WP-06 refactor. A later work
# package may change an expectation here only as a listed flip; every other
# example must stay unchanged. Planned flips:
# - WP-08 (enumeration), done: "rejects a disallowed value on a new issue",
#   "rejects an issue copy holding a legacy combination" and the second row
#   of "validates the members of a stored cycle" (all through the shared
#   parameter, %w[inclusion invalid] became %w[invalid]: two errors became
#   one), and "offers a stored disallowed value twice" (now once).
# - WP-09: "rejects a stored child ... assigned unchanged", "rejects an issue
#   copy holding a legacy combination", "silently skips an issue ... when the
#   project is copied", "rejects adding an allowed value next to the legacy
#   value". Not flipped by owner decision: the unavailable parent (UD-05).
# - WP-10: "validates the members of a stored cycle against their mappings".
# - WP-15 (carries?): "hides every option when a Project is passed for an
#   issue field" (the core list is returned for non-carrying objects).
# Helpers: spec/support/dcf_format_characterization.rb.
RSpec.describe 'Depending formats (characterization)' do
  include DcfFormatCharacterization

  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:blank) { I18n.t('activerecord.errors.messages.blank') }
  let(:hidden) { DcfFormatCharacterization::HIDDEN }

  # Errors for a disallowed value on a new record (value_was is empty): one
  # error for both formats (the enumeration format added core's inclusion
  # error before WP-08).
  shared_examples 'a depending format today' do |kind, new_disallowed|
    let(:new_disallowed_errors) { new_disallowed.map { |key| I18n.t("activerecord.errors.messages.#{key}") } }
    let(:kit) { build_kit(kind) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:project) { kit && dcf_create_project }
    let(:fmt) { child.format }

    describe 'possible_values_options' do
      it 'returns the core list for nil' do
        expect(fmt.possible_values_options(child, nil)).to eq(core_base(child))
      end

      it 'returns the core list, unfiltered, for an Array of records' do
        issues = [kit_issue(project, parent => 'A'), kit_issue(project, parent => 'B')]
        expect(fmt.possible_values_options(child, issues)).to eq(core_base(child))
      end

      it 'keeps every option for a record and hides the disallowed ones as 3-tuples' do
        issue = kit_issue(project, parent => 'A')
        expect(fmt.possible_values_options(child, issue))
          .to eq([pair(child, 'a1'), pair(child, 'a2'), pair(child, 'b1', hidden)])
      end

      it 'hides every option for a record whose parent is blank' do
        issue = kit_issue(project, parent => [], child => [])
        expect(fmt.possible_values_options(child, issue))
          .to eq([pair(child, 'a1', hidden), pair(child, 'a2', hidden), pair(child, 'b1', hidden)])
      end

      it 'hides every option when a Project is passed for an issue field' do
        expect(fmt.possible_values_options(child, project))
          .to eq([pair(child, 'a1', hidden), pair(child, 'a2', hidden), pair(child, 'b1', hidden)])
      end

      it 'returns the core list for a record when the parent field no longer exists' do
        issue = kit_issue(project, parent => 'A')
        CustomField.where(id: parent.id).delete_all
        expect(fmt.possible_values_options(CustomField.find(child.id), issue)).to eq(core_base(child))
      end
    end

    describe 'value_from_keyword' do
      let(:issue) { kit_issue(project, parent => 'A') }

      it 'matches labels case-insensitively and strips spaces' do
        expect(fmt.value_from_keyword(child, ' A1 ', issue)).to eq(kit_key(child, 'a1'))
      end

      it 'returns nil for an unknown keyword' do
        expect(fmt.value_from_keyword(child, 'zz', issue)).to be_nil
      end

      it 'matches a value the parent does not allow (hidden options still match)' do
        expect(fmt.value_from_keyword(child, 'b1', issue)).to eq(kit_key(child, 'b1'))
      end

      it 'matches the full list while the parent is not set yet (import order)' do
        unset = kit_issue(project, parent => [], child => [])
        expect(fmt.value_from_keyword(child, 'a2', unset)).to eq(kit_key(child, 'a2'))
      end

      it 'matches against the core list without a customized object' do
        expect(fmt.value_from_keyword(child, 'b1', nil)).to eq(kit_key(child, 'b1'))
      end

      it 'returns nil for a blank keyword' do
        expect(fmt.value_from_keyword(child, '', issue)).to be_nil
      end

      context 'with a multiple child' do
        let(:kit) { build_kit(kind, multiple: true, child_names: %w[a1 a2 b1 c,d]) }

        it 'splits on ; and , and returns Strings' do
          expect(fmt.value_from_keyword(child, 'a1;b1, a2', issue))
            .to eq([kit_key(child, 'a1'), kit_key(child, 'b1'), kit_key(child, 'a2')])
          expect(fmt.value_from_keyword(child, 'a1', issue)).to all(be_a(String))
        end

        it 'keeps duplicates' do
          expect(fmt.value_from_keyword(child, 'a1,a1', issue)).to eq([kit_key(child, 'a1')] * 2)
        end

        it 'cannot import a value that contains a comma' do
          expect(fmt.value_from_keyword(child, 'c,d', issue)).to be_nil
        end

        it 'returns nil when nothing matches' do
          expect(fmt.value_from_keyword(child, 'zz;yy', issue)).to be_nil
        end
      end

      context 'with a single child whose value contains a comma' do
        let(:kit) { build_kit(kind, child_names: %w[a1 a2 b1 c,d]) }

        it 'imports the value as a whole' do
          expect(fmt.value_from_keyword(child, 'c,d', issue)).to eq(kit_key(child, 'c,d'))
        end
      end
    end

    describe 'validation of issue values' do
      it 'accepts an allowed value on a new issue' do
        expect(errors_for(kit_new_issue(project, parent => 'A', child => 'a1'), child)).to eq([])
      end

      it 'accepts a blank child under a parent value without links' do
        expect(errors_for(kit_new_issue(project, parent => 'C', child => []), child)).to eq([])
      end

      it 'rejects a disallowed value on a new issue' do
        expect(errors_for(kit_new_issue(project, parent => 'B', child => 'a1'), child)).to eq(new_disallowed_errors)
      end

      it 'rejects a non-blank child under a parent value without links with one error' do
        expect(errors_for(kit_new_issue(project, parent => 'C', child => 'a1'), child)).to eq([invalid])
      end

      it 'rejects a stored child that the parent does not allow when values are assigned unchanged' do
        issue = kit_issue(project, parent => 'A', child => 'b1')
        issue.custom_field_values = { child.id.to_s => kit_value(child, 'b1') }
        expect(errors_for(issue, child)).to eq([invalid])
      end

      it 'does not validate a stored legacy combination when no custom value is assigned' do
        issue = kit_issue(project, parent => 'A', child => 'b1')
        issue.notes = 'notes only'
        expect(errors_for(issue, child)).to eq([])
      end

      it 'rejects an issue copy holding a legacy combination like a new disallowed value' do
        source = kit_issue(project, parent => 'A', child => 'b1')
        copy = Issue.new.copy_from(source)
        expect(errors_for(copy, child)).to eq(new_disallowed_errors)
      end

      it 'silently skips an issue holding a legacy combination when the project is copied' do
        kit_issue(project, parent => 'A', child => 'a1')
        kit_issue(project, parent => 'A', child => 'b1')
        User.current = dcf_admin
        target = Project.copy_from(project)
        target.name = 'Copy'
        target.identifier = "dcf-copy-#{SecureRandom.hex(3)}"
        target.copy(project, only: %w[issues])
        copied = Issue.where(project_id: target.id).map { |i| i.custom_field_value(child) }
        expect(copied).to eq([kit_key(child, 'a1')])
      ensure
        User.current = nil
      end

      it 'rejects a stored child when the parent is not available for the tracker' do
        issue = kit_issue(project, parent => 'A', child => 'a1')
        issue.tracker.custom_fields.delete(parent)
        issue = Issue.find(issue.id)
        issue.custom_field_values = { child.id.to_s => kit_value(child, 'a1') }
        expect(errors_for(issue, child)).to eq([invalid])
      end

      it 'validates the members of a stored cycle against their mappings' do
        x, y = build_cycle(kind)
        expect(errors_for(kit_new_issue(project, x => 'x1', y => 'y1'), y)).to eq([])
        expect(errors_for(kit_new_issue(project, x => 'x1', y => 'y2'), y)).to eq(new_disallowed_errors)
      end

      context 'with a multiple child holding a legacy value' do
        let(:kit) { build_kit(kind, multiple: true) }

        it 'rejects adding an allowed value next to the legacy value' do
          issue = kit_issue(project, parent => 'A', child => %w[b1])
          issue.custom_field_values = { child.id.to_s => kit_value(child, %w[b1 a1]) }
          expect(errors_for(issue, child)).to eq([invalid])
        end

        it 'accepts removing the legacy value' do
          issue = kit_issue(project, parent => 'A', child => %w[b1 a1])
          issue.custom_field_values = { child.id.to_s => kit_value(child, %w[a1]) }
          expect(errors_for(issue, child)).to eq([])
        end
      end

      context 'with a required child' do
        before { child.update!(is_required: true) }

        it 'accepts a blank child while the parent value has no links' do
          expect(errors_for(kit_new_issue(project, parent => 'C', child => []), child)).to eq([])
        end

        it 'accepts a blank child while the parent is blank' do
          expect(errors_for(kit_new_issue(project, parent => [], child => []), child)).to eq([])
        end

        it 'requires the child once the parent value has links' do
          expect(errors_for(kit_new_issue(project, parent => 'A', child => []), child)).to eq([blank])
        end
      end
    end

    describe 'before_custom_field_save' do
      it 'stores a valid parent id given as a String as an Integer and clears the core default value' do
        child.parent_custom_field_id = parent.id.to_s
        child.default_value = kit_key(child, 'a1')
        child.save!
        expect(CustomField.find(child.id).parent_custom_field_id).to eq(parent.id)
        expect(CustomField.find(child.id).default_value).to be_nil
      end

      it 'stores a blank parent id as an empty String and keeps the core default value' do
        child.parent_custom_field_id = ''
        child.default_value = kit_key(child, 'a1')
        child.save!
        expect(CustomField.find(child.id).parent_custom_field_id).to eq('')
        expect(CustomField.find(child.id).default_value).to eq(kit_key(child, 'a1'))
      end

      it 'drops a parent id that names no field' do
        child.parent_custom_field_id = 0
        child.save!
        expect(CustomField.find(child.id).parent_custom_field_id).to be_nil
      end

      it 'drops a parent of another custom field type' do
        other = kind == :list ? dcf_list_field(type: ProjectCustomField) : dcf_enum_field(type: ProjectCustomField)
        child.parent_custom_field_id = other.id
        child.save!
        expect(CustomField.find(child.id).parent_custom_field_id).to be_nil
      end

      it 'drops a parent outside the format family' do
        other = kind == :list ? dcf_enum_field : dcf_list_field
        child.parent_custom_field_id = other.id
        child.save!
        expect(CustomField.find(child.id).parent_custom_field_id).to be_nil
      end

      it 'keeps the core default value when no parent is set' do
        child.parent_custom_field_id = nil
        child.default_value = kit_key(child, 'a1')
        child.save!
        expect(CustomField.find(child.id).default_value).to eq(kit_key(child, 'a1'))
      end

      it 'stores sanitized mappings: String keys, blank entries and empty rows removed' do
        a1 = kit_key(child, 'a1')
        child.value_dependencies = { kit_key(parent, 'A') => [a1, '', nil], '' => [a1], 'X' => ['', nil], 7 => a1 }
        child.default_value_dependencies = { kit_key(parent, 'A') => [a1, ''], 'B' => '', '' => a1, 'C' => a1 }
        child.save!
        stored = CustomField.find(child.id)
        expect(stored.value_dependencies).to eq(kit_key(parent, 'A') => [a1], '7' => [a1])
        expect(stored.default_value_dependencies).to eq(kit_key(parent, 'A') => [a1], 'C' => a1)
      end
    end
  end

  describe RedmineDependingCustomFields::DependingListFormat do
    it_behaves_like 'a depending format today', :list, %w[invalid]

    describe 'details specific to the list format' do
      let(:kit) { build_kit(:list) }
      let(:parent) { kit.first }
      let(:child) { kit.last }
      let(:project) { kit && dcf_create_project }

      it 'offers the full core list in the edit form, also a stored disallowed value' do
        issue = kit_issue(project, parent => 'A', child => 'b1')
        value = issue.custom_field_values.detect { |v| v.custom_field_id == child.id }
        expect(child.format.possible_custom_value_options(value)).to eq(%w[a1 a2 b1])
      end

      it 'returns every value from query_filter_values without a query' do
        expect(child.format.query_filter_values(child, nil)).to eq([%w[a1 a1], %w[a2 a2], %w[b1 b1]])
      end

      it 'returns every value from query_filter_values for a project query' do
        query = IssueQuery.new(name: '_', project: project)
        expect(child.format.query_filter_values(child, query)).to eq([%w[a1 a1], %w[a2 a2], %w[b1 b1]])
      end

      it 'does not restrict query_filter_values by the project value of a project field' do
        parent, child = build_kit(:list, type: ProjectCustomField)
        project.custom_field_values = { parent.id.to_s => 'A' }
        project.save!(validate: false)
        query = IssueQuery.new(name: '_', project: Project.find(project.id))
        expect(child.format.query_filter_values(child, query)).to eq([%w[a1 a1], %w[a2 a2], %w[b1 b1]])
      end
    end
  end

  describe RedmineDependingCustomFields::DependingEnumerationFormat do
    # Flipped by WP-08: was %w[inclusion invalid] (new issue, issue copy and
    # stored cycle rows of the shared group).
    it_behaves_like 'a depending format today', :enumeration, %w[invalid]

    describe 'details specific to the enumeration format' do
      let(:kit) { build_kit(:enumeration) }
      let(:parent) { kit.first }
      let(:child) { kit.last }
      let(:project) { kit && dcf_create_project }

      # Flipped by WP-08: was [a1, a2, b1 + hidden, b1] (twice: hidden 3-tuple plus visible pair).
      it 'offers a stored disallowed value once in the edit form, as a plain pair (Flipped by WP-08)' do
        issue = kit_issue(project, parent => 'A', child => 'b1')
        value = issue.custom_field_values.detect { |v| v.custom_field_id == child.id }
        expect(child.format.possible_custom_value_options(value))
          .to eq([pair(child, 'a1'), pair(child, 'a2'), pair(child, 'b1')])
      end

      it 'raises from query_filter_values without a query' do
        expect { child.format.query_filter_values(child, nil) }.to raise_error(NoMethodError)
      end

      it 'returns every value from query_filter_values for an issue field' do
        query = IssueQuery.new(name: '_', project: project)
        expect(child.format.query_filter_values(child, query))
          .to eq([pair(child, 'a1'), pair(child, 'a2'), pair(child, 'b1')])
      end

      it 'restricts query_filter_values by the project value of a project field' do
        parent, child = build_kit(:enumeration, type: ProjectCustomField)
        project.custom_field_values = { parent.id.to_s => kit_key(parent, 'A') }
        project.save!(validate: false)
        query = IssueQuery.new(name: '_', project: Project.find(project.id))
        expect(child.format.query_filter_values(child, query)).to eq([pair(child, 'a1'), pair(child, 'a2')])
      end

      it 'keeps mappings to inactive enumerations when the field is saved (sanitize only)' do
        b1 = child.enumerations.detect { |e| e.name == 'b1' }
        b1.update!(active: false)
        field = CustomField.find(child.id)
        field.name = "#{field.name} renamed"
        field.save!
        expect(CustomField.find(child.id).value_dependencies[kit_key(parent, 'B')]).to eq([b1.id.to_s])
        expect(core_base(field).map(&:first)).to eq(%w[a1 a2])
      end
    end
  end
end
