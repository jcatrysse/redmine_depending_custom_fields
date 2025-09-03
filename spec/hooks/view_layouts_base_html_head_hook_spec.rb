require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::Hooks::ViewLayoutsBaseHtmlHeadHook do
  let(:hook) { described_class.send(:new) }
  let(:mapping) { { '1' => { parent_id: '2', map: { 'a' => ['b'] }, defaults: { 'a' => 'b' }, hide_when_disabled: true } } }

  before do
    allow(Rails.cache).to receive(:fetch).and_return(mapping)
    allow(RedmineDependingCustomFields::MappingBuilder).to receive(:build).and_return(mapping)
  end

  it 'includes mapping JSON and asset tags' do
    html = hook.view_layouts_base_html_head
    expect(html).to include(mapping.to_json)
    expect(html).to match(/depending_custom_fields.*\.js/)
    expect(html).to match(/context_menu_wizard.*\.js/)
    expect(html).to match(/depending_custom_fields.*\.css/)
  end

  it 'assigns mapping to the expected global variable' do
    html = hook.view_layouts_base_html_head
    expect(html).to include(
      "window.DependingCustomFieldData = #{mapping.to_json};"
    )
  end

  it 'provides JSON with the expected structure' do
    html = hook.view_layouts_base_html_head
    fragment = Nokogiri::HTML.fragment(html)
    script = fragment.css('script').find { |s| s.text.include?('DependingCustomFieldData') }
    json = script.text[/window\.DependingCustomFieldData\s*=\s*(.*);/, 1]
    data = JSON.parse(json)
    expected = mapping.transform_values do |value|
      {
        'parent_id' => value[:parent_id],
        'map' => value[:map],
        'defaults' => value[:defaults],
        'hide_when_disabled' => value[:hide_when_disabled]
      }
    end
    expect(data).to eq(expected)
  end
end
