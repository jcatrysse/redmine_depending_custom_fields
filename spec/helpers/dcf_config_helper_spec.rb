require_relative '../rails_helper'

RSpec.describe ProjectCustomFieldConfigurationHelper, type: :helper do
  let(:project) { dcf_create_project(name: 'A') }

  describe '#dcf_field_scope' do
    it 'is :global for an is_for_all field' do
      expect(helper.dcf_field_scope(dcf_list_field(is_for_all: true), project)).to eq(:global)
    end

    it 'is :global for a project custom field' do
      expect(helper.dcf_field_scope(dcf_list_field(type: ProjectCustomField, is_for_all: false), project)).to eq(:global)
    end

    it 'is :project when scoped to this project only' do
      field = dcf_list_field(is_for_all: false, projects: [project])
      expect(helper.dcf_field_scope(field, project)).to eq(:project)
    end

    it 'is :shared when scoped to another project too' do
      other = dcf_create_project(name: 'B')
      field = dcf_list_field(is_for_all: false, projects: [project, other])
      expect(helper.dcf_field_scope(field, project)).to eq(:shared)
    end
  end

  describe '#dcf_format_label' do
    it 'derives a non-blank label from the field-format registry (T-UI-6/#14)' do
      label = helper.dcf_format_label(dcf_list_field(format: 'depending_list'))
      expect(label).to be_present
      expect(label).not_to include('translation missing')
    end

    it 'translates the standard list/enumeration string label keys (not raw keys)' do
      expect(helper.dcf_format_label(dcf_list_field(format: 'list'))).to eq(I18n.t(:label_list))
      expect(helper.dcf_format_label(dcf_enum_field(format: 'enumeration')))
        .not_to start_with('label_')
    end
  end

  describe '#dcf_value_count' do
    it 'counts list possible values' do
      expect(helper.dcf_value_count(dcf_list_field(values: %w[A B C]))).to eq(3)
    end

    it 'counts enumeration rows' do
      expect(helper.dcf_value_count(dcf_enum_field(names: %w[X Y]))).to eq(2)
    end
  end

  describe '#dcf_visible_project_names' do
    it 'summarises invisible projects without leaking names (T-USE-3)' do
      other = dcf_create_project(name: 'Secret')
      field = dcf_list_field(is_for_all: false, projects: [project, other])
      allow(project).to receive(:visible?).and_return(true)
      allow(other).to receive(:visible?).and_return(false)
      allow(field).to receive(:projects).and_return([project, other])
      names = helper.dcf_visible_project_names(field, dcf_admin)
      expect(names).to include('A')
      expect(names).not_to include('Secret')
      expect(names.join).to match(/other project/)
    end
  end
end
