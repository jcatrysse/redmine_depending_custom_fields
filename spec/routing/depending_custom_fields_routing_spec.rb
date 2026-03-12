require_relative '../rails_helper'

RSpec.describe 'depending custom fields routing', type: :routing do
  it 'routes options to context_menu_wizard#options' do
    expect(get: '/depending_custom_fields/options').to route_to(
      controller: 'context_menu_wizard',
      action: 'options'
    )
  end

  it 'routes save to context_menu_wizard#save' do
    expect(post: '/depending_custom_fields/save').to route_to(
      controller: 'context_menu_wizard',
      action: 'save'
    )
  end
end
