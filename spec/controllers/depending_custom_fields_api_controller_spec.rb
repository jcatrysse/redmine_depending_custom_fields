require_relative '../rails_helper'

RSpec.describe DependingCustomFieldsApiController, type: :controller do
  render_views

  describe '#index' do
    before do
      CustomField.delete_all
      @cf1 = CustomField.create!(name: 'Field 1', field_format: 'list', type: 'IssueCustomField', possible_values: ['a'])
      @cf2 = CustomField.create!(name: 'Field 2', field_format: 'list', type: 'IssueCustomField', possible_values: ['b'])
    end

    def count_queries
      queries = 0
      callback = lambda do |*_, payload|
        next if payload[:name] =~ /SCHEMA|CACHE/
        queries += 1
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        yield
      end
      queries
    end

    it 'limits the number of queries when returning multiple fields' do
      query_count = count_queries { get :index }
      expect(query_count).to be <= 7
    end
  end

  describe '#custom_field_class' do
    before do
      stub_const('IssueCustomField', Class.new)
      stub_const('UserCustomField', Class.new)
      stub_const('TimeEntryCustomField', Class.new)
      stub_const(
        'DependingCustomFieldsApiController::CUSTOM_FIELD_CLASS_MAP',
        {
          'IssueCustomField' => IssueCustomField,
          'UserCustomField' => UserCustomField,
          'TimeEntryCustomField' => TimeEntryCustomField
        }
      )
    end

    it 'returns the class when allowed for list format' do
      controller.params = { custom_field: { type: 'UserCustomField', field_format: 'list' } }
      expect(controller.send(:custom_field_class)).to eq(UserCustomField)
    end

    it 'returns the class when allowed for enumeration format' do
      controller.params = { custom_field: { type: 'TimeEntryCustomField', field_format: 'enumeration' } }
      expect(controller.send(:custom_field_class)).to eq(TimeEntryCustomField)
    end

    it 'falls back when type is not allowed for the format' do
      controller.params = { custom_field: { type: 'UserCustomField', field_format: 'enumeration' } }
      expect(controller.send(:custom_field_class)).to eq(CustomField)
    end

    it 'falls back when constant is unknown' do
      controller.params = { custom_field: { type: 'UnknownClass', field_format: 'list' } }
      expect(controller.send(:custom_field_class)).to eq(CustomField)
    end
  end


  describe 'dependency_rules parameter handling' do
    it 'accepts dependency_rules as JSON string' do
      controller.params = ActionController::Parameters.new(
        custom_field: {
          name: 'CF',
          type: 'IssueCustomField',
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          dependency_rules: '[{"operator":"equals","value":"A","child_values":["B"]}]'
        }
      )

      attrs = controller.send(:custom_field_attributes)
      expect(attrs[:dependency_rules]).to be_a(String)
      expect(controller.send(:dependency_rules_errors)).to eq([])
    end

    it 'accepts dependency_rules as nested array' do
      controller.params = ActionController::Parameters.new(
        custom_field: {
          name: 'CF',
          type: 'IssueCustomField',
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          dependency_rules: [
            { operator: 'equals', value: 'A', child_values: ['B'] }
          ]
        }
      )

      attrs = controller.send(:custom_field_attributes)
      expect(attrs[:dependency_rules]).to be_a(Array)
      expect(controller.send(:dependency_rules_errors)).to eq([])
    end

    it 'returns validation error for invalid dependency_rules JSON' do
      controller.params = ActionController::Parameters.new(
        custom_field: {
          name: 'CF',
          type: 'IssueCustomField',
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          dependency_rules: '{invalid json'
        }
      )

      errors = controller.send(:dependency_rules_errors)
      expect(errors).to include(:base)
    end
  end

end
