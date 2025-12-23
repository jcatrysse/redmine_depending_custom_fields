module SpecHelpers
  def build_custom_field(attrs = {})
    defaults = {
      id: 1,
      name: 'Field',
      parent_custom_field_id: nil,
      parent_field_type: nil,
      parent_field_key: nil,
      dependency_rules: [],
      save: true,
      errors: double('errors', full_messages: []),
      multiple?: false,
      field_format: 'list',
      type: 'IssueCustomField'
    }
    instance_double(CustomField, defaults.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
end
