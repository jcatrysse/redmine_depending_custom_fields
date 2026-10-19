# frozen_string_literal: true

require_relative '../rails_helper'

# WP-06: on real fields (the parent lookup now memoizes on the record through
# CustomFieldPatch#dcf_memo, which a Struct cannot answer); the assertions are
# the same as with the former stand-in.
RSpec.describe RedmineDependingCustomFields::DependingEnumerationFormat do
  let(:format) { described_class.instance }

  describe '#before_custom_field_save' do
    let(:parent) { dcf_enum_field(names: %w[P Q]) }
    let(:parent_id) { parent.id.to_s }

    let(:custom_field) do
      field = CustomField.find(dcf_enum_field(format: 'depending_enumeration', names: %w[two]).id)
      field.parent_custom_field_id = parent_id
      field.value_dependencies = { '1' => ['2'] }
      field.default_value_dependencies = { '1' => '2' }
      field.default_value = 'X'
      field
    end

    context 'when a matching parent exists' do
      before do
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies)
          .with(custom_field.value_dependencies).and_return(custom_field.value_dependencies)
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies)
          .with(custom_field.default_value_dependencies).and_return(custom_field.default_value_dependencies)
      end

      it 'sets the parent_custom_field_id to the resolved parent id and clears the default value' do
        format.before_custom_field_save(custom_field)
        expect(custom_field.parent_custom_field_id).to eq(parent.id)
        expect(custom_field.default_value).to be_nil
      end

      it 'sanitizes the dependencies and defaults' do
        format.before_custom_field_save(custom_field)
        expect(RedmineDependingCustomFields::Sanitizer)
          .to have_received(:sanitize_dependencies).with(custom_field.value_dependencies)
        expect(RedmineDependingCustomFields::Sanitizer)
          .to have_received(:sanitize_default_dependencies).with(custom_field.default_value_dependencies)
      end
    end

    context 'when no matching parent exists' do
      let(:parent_id) { (CustomField.maximum(:id).to_i + 1_000).to_s }

      before do
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies).and_return({})
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies).and_return({})
      end

      it 'clears the parent_custom_field_id but leaves the default value intact' do
        format.before_custom_field_save(custom_field)
        expect(custom_field.parent_custom_field_id).to be_nil
        expect(custom_field.default_value).to eq('X')
      end

      it 'sanitizes the value and default dependencies' do
        format.before_custom_field_save(custom_field)
        expect(custom_field.value_dependencies).to eq({})
        expect(custom_field.default_value_dependencies).to eq({})
      end
    end
  end

  # WP-10 compat-ui-r2-2: the filter values read the effective parent, like
  # parent_state, possible_values_options and validation (UD-08, UD-35), so a
  # field in a stored cycle, a self-parent and a stored pointer to another
  # type offer every value; a valid project parent still restricts them.
  describe '#query_filter_values' do
    include DcfStoredCycle

    let(:project) { dcf_create_project }

    def project_field(names, parent: nil)
      dcf_enum_field(format: 'depending_enumeration', names: names, type: ProjectCustomField, parent: parent)
    end

    def with_project_values(values)
      record = Project.find(project.id)
      record.custom_field_values = values.to_h { |f, name| [f.id.to_s, kit_key(f, name)] }
      record.save!(validate: false)
      IssueQuery.new(name: '_', project: Project.find(project.id))
    end

    def all_pairs(field)
      field.enumerations.sort_by(&:position).map { |e| [e.name, e.id.to_s] }
    end

    it 'restricts the values by a valid project parent' do
      root = dcf_enum_field(names: %w[A B], type: ProjectCustomField)
      child = project_field(%w[a1 a2], parent: root)
      child = dcf_set_dependencies(child, value_dependencies: { kit_key(root, 'A') => [kit_key(child, 'a1')] })
      query = with_project_values(root => 'A')

      expect(format.query_filter_values(child, query)).to eq([['a1', kit_key(child, 'a1')]])
    end

    it 'offers every value for a stored self-parent and for the members of a stored cycle' do
      itself = project_field(%w[s1 s2])
      itself = dcf_set_dependencies(itself, value_dependencies: { kit_key(itself, 's1') => [kit_key(itself, 's1')] })
      itself = dcf_store_parent(itself, itself)
      x = project_field(%w[x1 x2])
      y = project_field(%w[y1 y2], parent: x)
      y = dcf_set_dependencies(y, value_dependencies: { kit_key(x, 'x1') => [kit_key(y, 'y1')] })
      x = dcf_set_dependencies(x, value_dependencies: { kit_key(y, 'y1') => [kit_key(x, 'x1')] })
      x = dcf_store_parent(x, y)
      query = with_project_values(itself => 's1', x => 'x1', y => 'y1')

      expect(format.query_filter_values(itself, query)).to eq(all_pairs(itself))
      expect(format.query_filter_values(CustomField.find(x.id), query)).to eq(all_pairs(x))
      expect(format.query_filter_values(CustomField.find(y.id), query)).to eq(all_pairs(y))
    end

    it 'offers every value for an issue field whose stored pointer names a project field' do
      root = dcf_enum_field(names: %w[A B], type: ProjectCustomField)
      child = dcf_enum_field(format: 'depending_enumeration', names: %w[a1 a2])
      child = dcf_set_dependencies(child, value_dependencies: { kit_key(root, 'A') => [kit_key(child, 'a1')] })
      child = dcf_store_parent(child, root)
      query = with_project_values(root => 'A')

      expect(format.query_filter_values(child, query)).to eq(all_pairs(child))
    end
  end
end
