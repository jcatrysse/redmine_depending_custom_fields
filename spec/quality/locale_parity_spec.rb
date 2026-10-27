# frozen_string_literal: true

require_relative '../rails_helper'
require 'yaml'

# Gate G8: the four shipped locales stay at key parity, keep the same
# interpolation variables, are translated, have no duplicate keys, and every
# key the plugin uses exists (in the plugin or in core, English).
RSpec.describe 'Plugin locales' do
  locales = %w[de en fr nl]
  root = File.expand_path('../..', __dir__)

  # Values that are legitimately identical to English (proper nouns, loanwords).
  # Adding an entry needs a reviewer's OK in the work package report; the full
  # list for planned keys is kept in docs/specs/large_lists_i18n_registry.md.
  # WP-18: de and nl text_dcf_live_message ('%{field}: %{message}', only
  # placeholders and a colon; the registry lists both, gap 10).
  identical_allowed = {
    'de' => %w[label_scope_global label_dcf_position text_dcf_live_message],
    'fr' => %w[label_scope_global label_dcf_position label_dcf_audit_action],
    'nl' => %w[label_scope_project text_dcf_live_message]
  }

  def self.flatten(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), out|
      full = [prefix, key].compact.join('.')
      value.is_a?(Hash) ? out.update(flatten(value, full)) : out[full] = value
    end
  end

  path = ->(locale) { File.join(root, 'config/locales', "#{locale}.yml") }
  tables = locales.to_h { |locale| [locale, flatten(YAML.safe_load(File.read(path.call(locale))).fetch(locale))] }

  # Duplicate keys in one mapping (YAML.safe_load silently keeps the last one).
  def self.duplicate_keys(yaml_text)
    duplicates = []
    walk = lambda do |node, trail|
      case node
      when Psych::Nodes::Mapping
        keys = node.children.each_slice(2).map { |key, _| key.respond_to?(:value) ? key.value : key.to_s }
        keys.group_by(&:itself).each { |key, list| duplicates << (trail + [key]).join('.') if list.size > 1 }
        node.children.each_slice(2) { |key, value| walk.call(value, trail + [key.respond_to?(:value) ? key.value : '?']) }
      when Psych::Nodes::Sequence, Psych::Nodes::Document, Psych::Nodes::Stream
        node.children.each { |child| walk.call(child, trail) }
      end
    end
    walk.call(Psych.parse_stream(yaml_text), [])
    duplicates
  end

  it 'has exactly the same keys in every locale' do
    english = tables['en'].keys.sort
    locales.each { |locale| expect(tables[locale].keys.sort).to eq(english), "key mismatch in #{locale}.yml" }
  end

  it 'keeps the same %{variables} per key' do
    variables = ->(text) { text.to_s.scan(/%\{(\w+)\}/).flatten.sort }
    tables['en'].each do |key, english|
      locales.each do |locale|
        expect(variables.call(tables[locale][key])).to eq(variables.call(english)), "#{locale}.#{key}"
      end
    end
  end

  it 'has no blank values and no English leftovers outside the allowlist' do
    (locales - ['en']).each do |locale|
      tables[locale].each do |key, value|
        expect(value.to_s.strip).not_to be_empty, "#{locale}.#{key} is blank"
        next if identical_allowed.fetch(locale, []).include?(key)

        expect(value).not_to eq(tables['en'][key]), "#{locale}.#{key} is still English"
      end
    end
  end

  it 'has no duplicate keys in any locale file' do
    locales.each do |locale|
      expect(self.class.duplicate_keys(File.read(path.call(locale)))).to eq([]), "#{locale}.yml"
    end
  end

  it 'detects a duplicated nested key (negative fixture)' do
    yaml = "en:\n  activerecord:\n    errors:\n      a: one\n      a: two\n"
    expect(self.class.duplicate_keys(yaml)).to eq(['en.activerecord.errors.a'])
  end

  it 'uses the typographic quotes of German and French around placeholders' do
    { 'de' => tables['de'], 'fr' => tables['fr'] }.each do |locale, table|
      table.each do |key, value|
        expect(value.to_s).not_to match(/["']%\{\w+\}|%\{\w+\}["']/), "#{locale}.#{key} uses ASCII quotes"
      end
    end
  end

  it 'defines every key the plugin code uses (plugin or core, English)' do
    sources = Dir[File.join(root, '{app,lib,config}/**/*.{rb,erb}')] + [File.join(root, 'init.rb')]
    used = sources.flat_map do |file|
      File.read(file).scan(/\b(?:l|I18n\.t|t)\(\s*[:'"]([a-z][\w.]*)/).flatten
    end.uniq.sort
    expect(used.reject { |key| I18n.exists?(key, :en) }).to eq([])
  end

  # The keys of the client i18n maps (gap 5) missing from a locale's own
  # table (no fallback: Redmine falls back to en), as "locale.key".
  def self.unresolved_map_keys(tables, locales)
    maps = %w[RedmineDependingCustomFields::ClientConfig::I18N RedmineDependingCustomFields::DependencyEditorConfig::I18N]
           .select { |name| Object.const_defined?(name) }.map { |name| Object.const_get(name) }
    keys = maps.flat_map { |map| map.respond_to?(:values) ? map.values : Array(map) }.map(&:to_s).uniq
    locales.flat_map do |locale|
      missing = keys.reject do |key|
        tables['en'].key?(key) ? tables[locale].key?(key) : core_key?(key, locale)
      end
      missing.map { |key| "#{locale}.#{key}" }
    end
  end

  # A key core defines in +locale+ (the plugin may reuse it).
  def self.core_key?(key, locale)
    I18n.t(key, locale: locale, raise: true, fallback: false)
    true
  rescue I18n::MissingTranslationData
    false
  end

  # WP-24: DependencyEditorConfig::I18N (the editor map) is resolved too.
  it 'resolves every value of the client i18n maps in every locale once they exist' do
    expect(self.class.unresolved_map_keys(tables, locales)).to eq([])
    keys = RedmineDependingCustomFields::ClientConfig::I18N.values +
           RedmineDependingCustomFields::DependencyEditorConfig::I18N.values
    locales.each do |locale|
      keys.each { |key| expect { I18n.t(key, locale: locale, raise: true) }.not_to raise_error, "#{locale}.#{key}" }
    end
  end

  # WP-18 (gap 5): the check iterates RedmineDependingCustomFields::ClientConfig::I18N.
  it 'reports a ClientConfig::I18N entry without a locale entry (negative fixture)' do
    map = RedmineDependingCustomFields::ClientConfig::I18N.merge('missing' => :text_dcf_missing_key).freeze
    stub_const('RedmineDependingCustomFields::ClientConfig::I18N', map)

    expect(self.class.unresolved_map_keys(tables, locales)).to eq(locales.map { |locale| "#{locale}.text_dcf_missing_key" })
    without_de = tables.merge('de' => tables['de'].except('text_dcf_hint_no_options'))
    expect(self.class.unresolved_map_keys(without_de, locales)).to include('de.text_dcf_hint_no_options')
  end

  # WP-24 (gap 5): the check iterates RedmineDependingCustomFields::DependencyEditorConfig::I18N
  # too, a map of its own (never merged with ClientConfig::I18N), loaded at boot.
  it 'reports a DependencyEditorConfig::I18N entry without a locale entry (negative fixture)' do
    name = 'RedmineDependingCustomFields::DependencyEditorConfig::I18N'
    expect(Object.const_defined?(name)).to be(true)
    without_de = tables.merge('de' => tables['de'].except('text_dcf_storage_estimate'))
    expect(self.class.unresolved_map_keys(without_de, locales)).to eq(['de.text_dcf_storage_estimate'])

    stub_const(name, Object.const_get(name).merge('missing' => :text_dcf_missing_key).freeze)
    expect(self.class.unresolved_map_keys(tables, locales)).to eq(locales.map { |locale| "#{locale}.text_dcf_missing_key" })
  end
end
