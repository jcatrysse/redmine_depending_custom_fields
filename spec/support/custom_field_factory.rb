module SpecHelpers
  def build_custom_field(attrs = {})
    defaults = {
      id: 1,
      name: 'Field',
      save: true,
      errors: double('errors', full_messages: []),
      multiple?: false
    }
    instance_double(CustomField, defaults.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
end
