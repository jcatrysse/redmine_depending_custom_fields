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

  # WP-17: the legacy script was renamed to depending_custom_fields_legacy.js;
  # the new runtime took the old name and no page loads it until WP-18.
  it 'includes the renamed legacy script, resolved by the asset pipeline, and not the new runtime' do
    html = hook.view_layouts_base_html_head
    srcs = Nokogiri::HTML.fragment(html).css('script[src]').pluck('src')
    legacy = srcs.grep(/depending_custom_fields_legacy/)
    expect(legacy.size).to eq(1)
    # A digest (6.x/7.0) or an asset id (5.1) is only added for a file that exists.
    expect(legacy.first).to match(/depending_custom_fields_legacy(-[0-9a-f]{7,}\.js|\.js\?\d+)\z/)
    expect(srcs.grep(%r{/depending_custom_fields(-[0-9a-f]+)?\.js})).to be_empty
    needles = [legacy.first, 'window.DependingCustomFieldData', 'context_menu_wizard', '<link']
    positions = needles.map { |needle| html.index(needle) }
    expect(positions).to eq(positions.sort)
  end
end
