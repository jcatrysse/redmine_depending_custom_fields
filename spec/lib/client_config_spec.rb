# frozen_string_literal: true

require_relative '../rails_helper'
require 'yaml'

# WP-18: the i18n map of the head meta tag (server design 2.4, gap 5). The
# frontend owns the key list (frontend design 3.6); UD-37 adds the warning
# for a parent change the server will refuse because of a visible read-only
# dependent field (the data-dcf-locked-* carrier of WP-16) as the 11th key.
RSpec.describe RedmineDependingCustomFields::ClientConfig do
  let(:locales) { %w[de en fr nl] }
  let(:root) { File.expand_path('../..', __dir__) }

  def raw_table(locale)
    YAML.safe_load(File.read(File.join(root, 'config/locales', "#{locale}.yml"))).fetch(locale)
  end

  it 'names the meta tag dcf-i18n' do
    expect(described_class::META_NAME).to eq('dcf-i18n')
    expect(described_class::META_NAME).to be_frozen
  end

  it 'maps the runtime keys to locale keys in a fixed order, frozen' do
    expect(described_class::I18N).to eq(
      'selectParent' => :text_dcf_hint_select_parent,
      'noOptions' => :text_dcf_hint_no_options,
      'noOptionsGeneric' => :text_dcf_hint_no_options_generic,
      'legacy' => :text_dcf_hint_legacy,
      'legacyLocked' => :text_dcf_hint_legacy_locked,
      'legacyGeneric' => :text_dcf_hint_legacy_generic,
      'bulkDefault' => :text_dcf_hint_bulk_default,
      'bulkCleared' => :text_dcf_hint_bulk_cleared,
      'liveMessage' => :text_dcf_live_message,
      'saveFailed' => :error_save_failed,
      'lockedRefused' => :text_dcf_hint_locked_refused
    )
    expect(described_class::I18N.keys.last).to eq('lockedRefused')
    expect(described_class::I18N).to be_frozen
  end

  it 'builds a flat payload of own strings per call in the current locale, from each locale table' do
    payloads = locales.to_h { |locale| [locale, I18n.with_locale(locale) { described_class.payload }] }

    locales.each do |locale|
      payload = payloads[locale]
      table = raw_table(locale)
      expect(payload.keys).to eq(described_class::I18N.keys), locale
      described_class::I18N.each do |js_key, locale_key|
        expect(payload[js_key]).to be_a(String), "#{locale}.#{js_key}"
        expect(payload[js_key]).not_to match(/translation missing/i), "#{locale}.#{js_key}"
        # The locale's own text, not an English fallback (I18n fallbacks are on).
        expect(payload[js_key]).to eq(table.fetch(locale_key.to_s)), "#{locale}.#{locale_key}"
      end
    end
    expect(payloads['de']['saveFailed']).not_to eq(payloads['fr']['saveFailed'])
    expect(described_class.payload).not_to equal(described_class.payload)
  end

  it 'keeps no state on the module and defines no I18N_KEYS' do
    I18n.with_locale(:de) { described_class.payload }

    expect(described_class.instance_variables).to eq([])
    expect(described_class.constants.map(&:to_s)).not_to include('I18N_KEYS')
    expect(defined?(RedmineDependingCustomFields::Hooks::ViewLayoutsBaseHtmlHeadHook::I18N_KEYS)).to be_nil
  end

  it 'is loaded under the eager loader with the constant its name gives' do
    lib = File.expand_path('../../lib', __dir__)
    path = File.join(lib, 'redmine_depending_custom_fields', 'client_config.rb')

    expect(Rails.autoloaders.main.cpath_expected_at(path)).to eq('RedmineDependingCustomFields::ClientConfig')
    expect { Rails.autoloaders.main.eager_load_dir(lib) }.not_to raise_error
  end

  # UD-37: the warning names no field, value or label (the carrier holds
  # none) and has no interpolation.
  it 'has a carrier warning without variables in every locale' do
    locales.each do |locale|
      text = raw_table(locale).fetch('text_dcf_hint_locked_refused')
      expect(text).not_to include('%{'), locale
    end
  end

  # WP-25 (editor design 5.1, quality H3): the editor assets come only from
  # the head hook, on the two editor controllers, compared by class name.
  describe 'editor pages' do
    it 'names the two editor controllers as frozen Strings' do
      expect(described_class::EDITOR_CONTROLLERS).to eq(%w[CustomFieldsController ProjectCustomFieldConfigurationController])
      expect(described_class::EDITOR_CONTROLLERS).to be_frozen
      expect(described_class::EDITOR_CONTROLLERS).to all(be_frozen)
    end

    it 'is an editor page for those two controllers only, by class name, and never for nil' do
      expect(described_class.editor_page?(CustomFieldsController.new)).to be(true)
      expect(described_class.editor_page?(ProjectCustomFieldConfigurationController.new)).to be(true)
      expect(described_class.editor_page?(IssuesController.new)).to be(false)
      expect(described_class.editor_page?(Class.new(CustomFieldsController).new)).to be(false)
      expect(described_class.editor_page?(nil)).to be(false)
    end

    it 'returns the model script, the editor script and the editor stylesheet, in this order' do
      view = RedmineDependingCustomFields::Hooks::ViewLayoutsBaseHtmlHeadHook.send(:new)
      tags = described_class.editor_asset_tags(view)
      fragment = Nokogiri::HTML5.fragment(tags.join)
      asset = ->(name, ext) { /#{name}(-[0-9a-f]{7,}\.#{ext}|\.#{ext}\?\d+)\z/ }

      expect(tags.size).to eq(3)
      expect(fragment.element_children.map(&:name)).to eq(%w[script script link])
      srcs = fragment.css('script').map { |s| s['src'] }
      expect(srcs[0]).to match(asset.call('dcf_dependency_editor_model', 'js'))
      expect(srcs[1]).to match(asset.call('dcf_dependency_editor', 'js'))
      expect(fragment.at_css('link')['href']).to match(asset.call('dcf_dependency_editor', 'css'))
      expect(described_class.instance_variables).to eq([])
      expect(described_class::I18N.size).to eq(11)
    end
  end
end
