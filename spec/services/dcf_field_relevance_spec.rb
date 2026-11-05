require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::FieldRelevance do
  let(:project) { dcf_create_project }

  describe '.supported_format? / .standard_enabled?' do
    it 'supports the four value formats by default' do
      expect(described_class.supported_format?(dcf_list_field(format: 'list'))).to be true
      expect(described_class.supported_format?(dcf_enum_field(format: 'enumeration'))).to be true
      expect(described_class.supported_format?(dcf_list_field(format: 'depending_list'))).to be true
      expect(described_class.supported_format?(dcf_enum_field(format: 'depending_enumeration'))).to be true
    end

    it 'does not support unrelated formats' do
      bool = IssueCustomField.create!(name: 'B', field_format: 'bool')
      expect(described_class.supported_format?(bool)).to be false
    end

    it 'excludes standard formats when the kill-switch is off (depending stay supported)' do
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('manage_standard_custom_fields' => '0')
      expect(described_class.supported_format?(dcf_list_field(format: 'list'))).to be false
      expect(described_class.supported_format?(dcf_enum_field(format: 'enumeration'))).to be false
      expect(described_class.supported_format?(dcf_list_field(format: 'depending_list'))).to be true
    end

    it 'treats a missing setting key as enabled' do
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields).and_return({})
      expect(described_class.standard_enabled?).to be true
    end

    it 'treats string "0" as disabled (not the != false bug)' do
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('manage_standard_custom_fields' => '0')
      expect(described_class.standard_enabled?).to be false
    end
  end

  describe '.relevant? / .in_project?' do
    it 'is relevant for an is_for_all issue field' do
      field = dcf_list_field(is_for_all: true)
      expect(described_class.relevant?(field, project)).to be true
    end

    it 'is not relevant for an issue field scoped to a different project' do
      other = dcf_create_project(name: 'Other')
      field = dcf_list_field(is_for_all: false, projects: [other])
      expect(described_class.relevant?(field, project)).to be false
    end

    it 'is always relevant for a project custom field (treated Global)' do
      field = dcf_list_field(type: ProjectCustomField, is_for_all: false)
      expect(described_class.relevant?(field, project)).to be true
    end
  end

  describe '.relevant_fields' do
    it 'returns supported issue and project custom fields without raising (GitHub #13)' do
      issue_field   = dcf_list_field(format: 'list', name: 'IssueList', is_for_all: true)
      project_field = dcf_list_field(format: 'list', name: 'ProjectList', type: ProjectCustomField)

      result = nil
      expect { result = described_class.relevant_fields(project) }.not_to raise_error

      ids = result.map(&:id)
      expect(ids).to include(issue_field.id, project_field.id)
    end

    # Changed by the full review of 2026-11-05 (project-pages-3): nothing is
    # preloaded; the overview counts in three grouped queries whatever the
    # number of fields (was: :projects preloaded, no query per field).
    it 'counts the overview rows in a fixed number of queries, issue and project fields mixed' do
      other = dcf_create_project(name: 'Other')
      shared = dcf_list_field(format: 'list', name: 'Shared', is_for_all: false, projects: [project, other])
      dcf_list_field(format: 'list', name: 'ProjectList', type: ProjectCustomField)
      enum = dcf_enum_field(names: %w[X Y Z])

      fields = described_class.relevant_fields(project)
      counts = nil
      few = dcf_count_queries { counts = described_class.overview_counts(fields, project) }
      expect(counts.value_counts[enum.id]).to eq(3)
      expect(counts.project_counts[shared.id]).to eq(2)
      expect(counts.shared).to include(shared.id)
      expect(described_class.scope(shared, project, shared_ids: counts.shared)).to eq(:shared)
      expect(described_class.scope(shared, project)).to eq(:shared)
      3.times { |i| dcf_enum_field(names: %W[A#{i} B#{i}]) }
      2.times { |i| dcf_list_field(format: 'list', name: "More#{i}", is_for_all: false, projects: [project, other]) }
      many_fields = described_class.relevant_fields(project)
      expect(dcf_count_queries { described_class.overview_counts(many_fields, project) }).to eq(few)
    end

    it 'excludes standard formats when the kill-switch is off' do
      dcf_list_field(format: 'list', name: 'IssueList', is_for_all: true)
      depending = dcf_list_field(format: 'depending_list', name: 'Dep', is_for_all: true)
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('manage_standard_custom_fields' => '0')

      ids = described_class.relevant_fields(project).map(&:id)
      expect(ids).to eq([depending.id])
    end
  end

  describe '.dependency_capable?' do
    it 'is true only for a depending format with a parent' do
      parent = dcf_list_field(name: 'Parent')
      child = dcf_list_field(format: 'depending_list', name: 'Child', parent: parent)
      expect(described_class.dependency_capable?(child)).to be true
      expect(described_class.dependency_capable?(dcf_list_field(format: 'list'))).to be false
      orphan = dcf_list_field(format: 'depending_list', name: 'Orphan')
      expect(described_class.dependency_capable?(orphan)).to be false
    end
  end

  describe '.children_of' do
    it 'returns depending children naming the field as parent' do
      parent = dcf_list_field(name: 'Parent')
      child = dcf_list_field(format: 'depending_list', name: 'Child', parent: parent)
      expect(described_class.children_of(parent).map(&:id)).to include(child.id)
    end
  end
end
