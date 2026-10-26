# frozen_string_literal: true

require_relative '../rails_helper'
require_relative '../support/dcf_js_fixtures'

# WP-18: the head hook output in en, de, fr and nl as generated fixtures
# (quality 5.5, group 'head'): test/js/fixtures/head/<locale>.html, read by
# test/js/head_fixtures.test.js in the page order (meta, runtime, wizard
# script, stylesheet). Asset URLs are normalized (Propshaft digest, 5.1
# asset id and plugin path), so one file serves every version; the meta
# content stays byte-exact.
RSpec.describe 'Head hook fixtures (WP-18)' do
  include DcfJsFixtures

  let(:group) { 'head' }
  let(:client) { RedmineDependingCustomFields::ClientConfig }

  def render_head(locale)
    listener = RedmineDependingCustomFields::Hooks::ViewLayoutsBaseHtmlHeadHook.instance
    I18n.with_locale(locale) { listener.view_layouts_base_html_head({}) }
  end

  %w[de en fr nl].each do |locale|
    it "renders the #{locale} head as its committed fixture" do
      html = dcf_js_fixture(group, locale, render_head(locale))
      fragment = dcf_parse_fragment(html)
      payload = JSON.parse(fragment.at_css("meta[name='dcf-i18n']")['content'])

      expect(payload.keys).to eq(client::I18N.keys)
      expect(payload).to eq(I18n.with_locale(locale) { client.payload })
      expect(fragment.element_children.map(&:name)).to eq(%w[meta script script link])
      expect(fragment.css('script').pluck('src')).to eq(
        %w[/plugin_assets/redmine_depending_custom_fields/depending_custom_fields.js
           /plugin_assets/redmine_depending_custom_fields/context_menu_wizard.js]
      )
      expect(fragment.at_css('link')['href']).to eq('/plugin_assets/redmine_depending_custom_fields/depending_custom_fields.css')
      expect(html).not_to match(/[\u2013\u2014]/)
    end
  end

  it 'has one committed fixture per locale and no other' do
    skip 'compare mode only: the locale examples are writing the files' if dcf_js_write_fixtures?
    files = Dir[File.join(dcf_js_fixture_dir, group, '*')].map { |path| File.basename(path) }.sort

    expect(files).to eq(%w[de.html en.html fr.html nl.html])
  end
end
