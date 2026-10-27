# frozen_string_literal: true

require_relative '../rails_helper'
require_relative '../support/dcf_js_fixtures'

# WP-24 (editor design 5.2 and 5.3, limits design 10.4, quality 5.5): the
# shared editor partial rendered in the view context of the controller of
# each page (CustomFieldsController for the admin form,
# ProjectCustomFieldConfigurationController for the project page) as
# generated fixtures test/js/fixtures/editor/<scenario>.html, written with
# DCF_WRITE_JS_FIXTURES=1 and compared otherwise. Records come from the
# fixed id ranges (dcf_fixture_record) and carry fixed names; the column
# limit is stubbed per scenario (nil, or 65,535 in mysql_limit, whose
# storage-base is replaced by {{BYTES}}), so PostgreSQL and MySQL give the
# same files. Redmine 5.1 has no sprite_icon, so its required warning is
# plain text: each scenario has a reviewed .redmine-5.1.html variant.
# The partial is rendered bare; WP-25 and WP-27 add scenarios of their
# pages. Also writes test/js/fixtures/value_options.json from
# DependencyEditorConfig.wire_values and checks endpoint == presenter ==
# fixture (gap 3).
RSpec.describe 'Dependency editor fixtures (WP-24)', type: :request do
  include DcfJsFixtures

  fixtures :users

  let(:group) { 'editor' }
  let(:config) { RedmineDependingCustomFields::DependencyEditorConfig }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:admin) { User.find(1) }

  value_options_list = ['Belgium', '[x]', 'a]', 'say "hi"', '<b>&"', "O'Brien", '</script>',
                        '"><script>alert(1)</script>', '__proto__', 'constructor', '10', "\u00e9", "e\u0301",
                        "\u00dcn\u00efc\u00f8d\u00e9 \u00f1"].freeze

  def self.scenarios
    %w[admin_list admin_enumeration admin_new admin_conflict project_list project_enumeration mysql_limit]
  end

  # ---- records with fixed ids and names -----------------------------------

  def fx_list(name, values, format: 'list', parent: nil, required: false)
    field = dcf_fixture_record(IssueCustomField, { name: name, field_format: format, possible_values: values,
                                                   is_for_all: true, is_required: required }) do |cf|
      cf.parent_custom_field_id = parent.id if parent
    end
    CustomField.find(field.id)
  end

  def fx_enum(name, names, format: 'enumeration', parent: nil, inactive: [], multiple: false, positions: {})
    field = dcf_fixture_record(IssueCustomField, { name: name, field_format: format, is_for_all: true,
                                                   multiple: multiple }) do |cf|
      cf.parent_custom_field_id = parent.id if parent
    end
    names.each_with_index do |label, i|
      entry = dcf_fixture_record(CustomFieldEnumeration, { custom_field_id: field.id, name: label, position: i + 1,
                                                           active: !inactive.include?(label) })
      # Written after creation: acts_as_positioned renumbers on create.
      entry.update_columns(position: positions[label]) if positions.key?(label)
    end
    CustomField.find(field.id)
  end

  def fx_key(field, name)
    return name unless field.field_format.end_with?('enumeration')

    field.enumerations.detect { |e| e.name == name }.id.to_s
  end

  def fx_links(child, parent, links, defaults = {})
    field = CustomField.find(child.id)
    field.value_dependencies = links.to_h { |p, cs| [fx_key(parent, p), cs.map { |c| fx_key(field, c) }] }
    field.default_value_dependencies = defaults.to_h do |p, cs|
      [fx_key(parent, p), cs.is_a?(Array) ? cs.map { |c| fx_key(field, c) } : fx_key(field, cs)]
    end
    field.save!
    CustomField.find(field.id)
  end

  # Country (Belgium, France, Germany) and City; Atlantis is an orphan key.
  def list_pair(required: false)
    parent = fx_list('Country', %w[Belgium France Germany])
    child = fx_list('City', %w[Antwerp Brussels Paris Lyon], format: 'depending_list', parent: parent,
                                                             required: required)
    [parent, fx_links(child, parent, { 'Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris],
                                       'Atlantis' => %w[Gone] }, 'Belgium' => 'Brussels')]
  end

  # Region (North, South, inactive Old) and Product (Alpha, Beta, inactive Retired).
  def enum_pair(multiple: false)
    parent = fx_enum('Region', %w[North South Old], inactive: %w[Old])
    child = fx_enum('Product', %w[Alpha Beta Retired], format: 'depending_enumeration', parent: parent,
                                                       inactive: %w[Retired], multiple: multiple)
    [parent, fx_links(child, parent, { 'North' => %w[Alpha Beta], 'Old' => %w[Retired] }, 'North' => %w[Beta])]
  end

  # ---- rendering -----------------------------------------------------------

  def view_for(controller_class)
    controller = controller_class.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller.view_context
  end

  def column_limit(value)
    allow(limits).to receive(:column_limit).and_return(value)
  end

  def render_admin(field)
    allow(User).to receive(:current).and_return(admin)
    view = view_for(CustomFieldsController)
    I18n.with_locale(:en) do
      view.render(partial: 'depending_custom_fields/dependency_editor', locals: { editor: config.for_admin(field, view) })
    end
  end

  def render_project(field, parent, **options)
    allow(User).to receive(:current).and_return(admin)
    view = view_for(ProjectCustomFieldConfigurationController)
    editor = config.for_project(field: field, parent: parent, view: view, **options)
    I18n.with_locale(:en) do
      view.render(partial: 'depending_custom_fields/dependency_editor', locals: { editor: editor })
    end
  end

  def scenario_admin_list
    column_limit(nil)
    _parent, child = list_pair(required: true)
    render_admin(child)
  end

  def scenario_admin_enumeration
    column_limit(nil)
    _parent, child = enum_pair(multiple: true)
    render_admin(child)
  end

  def scenario_admin_new
    column_limit(nil)
    render_admin(IssueCustomField.new(name: 'New field', field_format: 'depending_list', possible_values: %w[One Two],
                                      is_for_all: true))
  end

  def scenario_admin_conflict
    column_limit(nil)
    _parent, child = list_pair
    field = CustomField.find(child.id)
    field.dependencies_json = JSON.generate('version' => 1, 'source' => 'editor', 'base' => 'f' * 64,
                                            'value_dependencies' => { 'Germany' => %w[Lyon] },
                                            'default_value_dependencies' => { 'Germany' => 'Lyon' })
    raise 'the stale payload must be refused' if field.valid?

    render_admin(field)
  end

  def scenario_project_list
    column_limit(nil)
    parent, child = list_pair
    render_project(child, parent)
  end

  def scenario_project_enumeration
    column_limit(nil)
    parent, child = enum_pair
    north = fx_key(parent, 'North')
    south = fx_key(parent, 'South')
    posted = payload.parse(JSON.generate('value_dependencies' => { north => [fx_key(child, 'Alpha')],
                                                                   south => [fx_key(child, 'Beta')] },
                                         'default_value_dependencies' => { south => fx_key(child, 'Beta') }))
    render_project(child, parent, posted: posted)
  end

  # The storage-base value holds bytes that depend on the parent id digits
  # (limits design 10.4): replaced by {{BYTES}}; its exact value is checked
  # by 'renders the exact storage base before the placeholder'.
  def scenario_mysql_limit
    fragment = dcf_parse_fragment(mysql_limit_html)
    fragment.at_css('[data-dcf-editor-storage-base]')['data-dcf-editor-storage-base'] = '{{BYTES}}'
    dcf_serialize(fragment)
  end

  def mysql_limit_html
    column_limit(65_535)
    _parent, child = list_pair
    render_admin(child)
  end

  def render_scenario(name)
    send("scenario_#{name}")
  end

  # One render inside a savepoint that is rolled back, with the fixed ids
  # starting again at the start of each range.
  def isolated_render(name)
    html = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      dcf_reset_fixture_ids
      html = dcf_js_normalize(render_scenario(name))
      raise ActiveRecord::Rollback
    end
    html
  end

  # ---- checks ----------------------------------------------------------------

  def editor_names(node)
    node.attribute_nodes.map(&:name).grep(/\Adata-/)
  end

  def enumeration_keys(root)
    keys = %w[data-dcf-editor-parent-values data-dcf-editor-child-values].flat_map do |name|
      root[name] ? JSON.parse(root[name]).map { |v| v['key'] } : []
    end
    %w[data-dcf-editor-mapping data-dcf-editor-conflict-mapping].each do |name|
      next unless root[name]

      data = JSON.parse(root[name])
      %w[value_dependencies default_value_dependencies].each do |part|
        data[part].each { |k, v| keys.push(k, *Array(v)) }
      end
    end
    keys
  end

  # Rules of every editor fixture (editor design 5.2 and 5.3).
  def check_editor(name, fragment)
    roots = fragment.css('fieldset[data-dcf-editor]')
    expect(roots.size).to eq(1), name
    root = roots.first
    expect(fragment.css('[name]').map { |n| [n.name, n['type'], n['value']] }).to eq([['input', 'hidden', '']]), name
    expect(fragment.css('script')).to be_empty
    fragment.css('*').each do |node|
      editor_names(node).each { |attr| expect(attr).to match(/\Adata-dcf-editor(-[a-z0-9]+)*\z/), "#{name}: #{attr}" }
    end
    %w[parent-values mapping max-form-bytes i18n].each do |attr|
      expect { JSON.parse(root["data-dcf-editor-#{attr}"]) }.not_to raise_error, "#{name}: #{attr}"
    end
    expect(JSON.parse(root['data-dcf-editor-i18n']).keys).to eq(['storageEstimate']), name
    root
  end

  def scenario_checks
    enumeration_range = dcf_fixture_range(DcfJsFixtures::ENUMERATION)
    {
      'admin_list' => lambda do |root|
        expect(root['data-dcf-editor-mode']).to eq('admin')
        expect(root['data-dcf-editor-kind']).to eq('list')
        expect(root['data-dcf-editor-allow-add-values']).to eq('1')
        expect(root['data-dcf-editor-child-values']).to be_nil
        expect(root['data-dcf-editor-base']).to match(/\A[0-9a-f]{64}\z/)
        expect(root['data-dcf-editor-dirty']).to be_nil
        expect(JSON.parse(root['data-dcf-editor-mapping'])['value_dependencies']).to include('Atlantis' => %w[Gone])
        expect(root.at_css('p[data-dcf-editor-required-warning]')['class']).to eq('dcf-dep-editor__required')
        expect(root.at_css('p[data-dcf-editor-placeholder]')['class']).to include('dcf-hidden')
        expect(editor_names(root)).not_to include('data-dcf-editor-storage-limit')
      end,
      'admin_enumeration' => lambda do |root|
        expect(root['data-dcf-editor-kind']).to eq('enumeration')
        expect(root['data-dcf-editor-multiple']).to eq('1')
        expect(root['data-dcf-editor-allow-add-values']).to be_nil
        expect(root['data-dcf-editor-values-source']).to be_nil
        expect(JSON.parse(root['data-dcf-editor-child-values']).last).to include('label' => 'Retired', 'active' => false)
        expect(root.at_css('p[data-dcf-editor-required-warning]')['class']).to include('dcf-hidden')
        expect(enumeration_keys(root).map(&:to_i)).to all(satisfy { |id| enumeration_range.cover?(id) })
      end,
      'admin_new' => lambda do |root|
        expect(editor_names(root)).not_to include('data-dcf-editor-field-id', 'data-dcf-editor-base',
                                                  'data-dcf-editor-parent-id', 'data-dcf-editor-parent-name',
                                                  'data-dcf-editor-dirty')
        expect(root['data-dcf-editor-parent-values']).to eq('[]')
        expect(root.at_css('p[data-dcf-editor-placeholder]')['class']).to eq('dcf-dep-editor__placeholder')
      end,
      'admin_conflict' => lambda do |root|
        conflict = JSON.parse(root['data-dcf-editor-conflict-mapping'])
        expect(conflict.keys).to eq(%w[value_dependencies default_value_dependencies source import])
        expect(conflict['value_dependencies']).to eq('Germany' => %w[Lyon])
        expect(JSON.parse(root['data-dcf-editor-mapping'])['value_dependencies']).not_to have_key('Germany')
        expect(root['data-dcf-editor-dirty']).to be_nil
        expect(root['data-dcf-editor-base']).to match(/\A[0-9a-f]{64}\z/)
      end,
      'project_list' => lambda do |root|
        expect(root['data-dcf-editor-mode']).to eq('project')
        expect(root['data-dcf-editor-always-submit']).to eq('1')
        expect(editor_names(root)).not_to include('data-dcf-editor-base', 'data-dcf-editor-values-url',
                                                  'data-dcf-editor-parent-source', 'data-dcf-editor-values-source',
                                                  'data-dcf-editor-allow-add-values', 'data-dcf-editor-dirty')
        expect(root.at_css('input')['name']).to eq('dependencies_json')
        expect(JSON.parse(root['data-dcf-editor-child-values']).map { |v| v['key'] }).to eq(%w[Antwerp Brussels Paris Lyon])
      end,
      'project_enumeration' => lambda do |root|
        expect(root['data-dcf-editor-dirty']).to eq('1')
        expect(root['data-dcf-editor-allow-add-values']).to be_nil
        expect(JSON.parse(root['data-dcf-editor-mapping'])['value_dependencies'].size).to eq(2)
        expect(enumeration_keys(root).map(&:to_i)).to all(satisfy { |id| enumeration_range.cover?(id) })
      end,
      'mysql_limit' => lambda do |root|
        expect(root['data-dcf-editor-storage-limit']).to eq('65535')
        expect(root['data-dcf-editor-storage-base']).to eq('{{BYTES}}')
        expect(root['data-dcf-editor-values-limit']).to eq('65535')
        expect(root['data-dcf-editor-storage-warn']).to eq('90')
      end
    }
  end

  # ---- examples --------------------------------------------------------------

  scenarios.each do |name|
    it "renders the #{name} scenario as its committed fixture" do
      html = dcf_js_fixture(group, name, render_scenario(name))
      fragment = dcf_parse_fragment(html)
      root = check_editor(name, fragment)
      instance_exec(root, &scenario_checks.fetch(name))
      expect(html).not_to match(/[\u2013\u2014]/)
      expect(html).not_to include('storage-base="') if name != 'mysql_limit'
    end
  end

  it 'renders the exact storage base before the placeholder (limits design 10.4)' do
    root = dcf_parse_fragment(mysql_limit_html).at_css('fieldset')
    field = CustomField.find(root['data-dcf-editor-field-id'].to_i)

    expect(root['data-dcf-editor-storage-base']).to eq(limits.base_bytes(field).to_s)
  end

  it 'renders every scenario identically after 37 throwaway rows of each kind (sequence-bump self check)' do
    first = self.class.scenarios.index_with { |name| isolated_render(name) }
    dcf_bump_sequences(37)
    second = self.class.scenarios.index_with { |name| isolated_render(name) }

    first.each { |name, html| expect(second[name]).to eq(html), name }
  end

  it 'has one committed fixture per scenario and no other' do
    skip 'compare mode only: the scenario examples are writing the files' if dcf_js_write_fixtures?
    paths = Dir[File.join(dcf_js_fixture_dir, group, '*')]
    files = paths.map { |path| File.basename(path, '.html').sub(/\.redmine-\d+\.\d+\z/, '') }

    expect(paths.map { |path| File.extname(path) }.uniq).to eq(['.html'])
    expect(files.uniq.sort).to eq(self.class.scenarios.sort)
    expect(paths.grep(/\.redmine-/).map { |path| path[/\.redmine-(\d+\.\d+)\.html\z/, 1] }.uniq).to all(eq('5.1'))
  end

  # Redmine 5.1 has no sprite_icon: its variants carry the warning text without the svg, nothing else.
  it 'has 5.1 variants that differ from the base only by the sprite of the required warning' do
    skip 'compare mode only: the scenario examples are writing the files' if dcf_js_write_fixtures?
    Dir[File.join(dcf_js_fixture_dir, group, '*.redmine-*.html')].each do |path|
      base = dcf_parse_fragment(File.read(path.sub(/\.redmine-\d+\.\d+\.html\z/, '.html'), encoding: 'UTF-8'))
      base.css('p[data-dcf-editor-required-warning] svg').each(&:remove)
      label = base.at_css('p[data-dcf-editor-required-warning] span.icon-label')
      label.replace(label.children)

      expect(dcf_serialize(dcf_parse_fragment(File.read(path, encoding: 'UTF-8')))).to eq(dcf_serialize(base)), path
    end
  end

  it 'writes value_options.json from wire_values; endpoint == presenter == fixture (gap 3)' do
    list = fx_list('Values list', value_options_list)
    positions = { 'North' => 1, 'South' => 1, 'Old' => 2, 'Named' => 3 }
    enum = fx_enum('Values enumeration', %w[North South Old Named], inactive: %w[Old], positions: positions)
    named = enum.enumerations.detect { |e| e.name == 'Named' }
    named.update_columns(name: named.id.to_s)
    enum = CustomField.find(enum.id)
    data = { 'list' => config.wire_values(rules.value_options(list)),
             'enumeration' => config.wire_values(rules.value_options(enum)) }
    dcf_js_write_or_compare('', 'value_options', "#{JSON.pretty_generate(data)}\n", 'json')
    committed = JSON.parse(File.read(File.join(dcf_js_fixture_dir, 'value_options.json'), encoding: 'UTF-8'))

    expect(committed).to eq(data)
    expect(data['list'].map { |v| v['key'] }).to eq(value_options_list)
    expect(data['enumeration']).to eq(
      [{ 'key' => fx_key(enum, 'North'), 'label' => 'North' }, { 'key' => fx_key(enum, 'South'), 'label' => 'South' },
       { 'key' => fx_key(enum, 'Old'), 'label' => 'Old', 'active' => false }, { 'key' => named.id.to_s }]
    )
    expect(data['enumeration'].map { |v| v['key'].to_i })
      .to all(satisfy { |id| dcf_fixture_range(DcfJsFixtures::ENUMERATION).cover?(id) })

    parents = { 'list' => [list, 'depending_list'], 'enumeration' => [enum, 'depending_enumeration'] }
    # Both requests run before render_admin stubs User.current: the session authenticates them.
    post '/login', params: { username: 'admin', password: 'admin' }
    expect(session[:user_id]).to eq(admin.id)
    endpoint = parents.to_h do |name, (parent, _format)|
      get '/dcf_dependency_editor/values', params: { custom_field_id: parent.id.to_s, kind: name, type: parent.type }
      expect(response).to have_http_status(200), name
      [name, JSON.parse(response.body)['values']]
    end
    parents.each do |name, (parent, format)|
      child = dcf_fixture_record(IssueCustomField, { name: "Child of #{name}", field_format: format,
                                                     possible_values: %w[c1], is_for_all: true }) do |cf|
        cf.parent_custom_field_id = parent.id
      end
      root = dcf_parse_fragment(render_admin(CustomField.find(child.id))).at_css('fieldset')

      expect(endpoint[name]).to eq(committed[name]), name
      expect(JSON.parse(root['data-dcf-editor-parent-values'])).to eq(committed[name]), name
    end
  end

  describe 'the svg sprite normalizer (WP-24)' do
    it 'drops the asset digest of a sprite use href and keeps the fragment' do
      html = '<p><svg class="s18 icon-svg" aria-hidden="true"><use href="/assets/icons-0476c1d7.svg#icon--warning">' \
             "</use></svg><svg><use href=\"/assets/icons-#{'a' * 64}.svg#icon--warning\"></use></svg></p>"

      expect(dcf_js_normalize(html)).to eq(
        '<p><svg class="s18 icon-svg" aria-hidden="true"><use href="/assets/icons.svg#icon--warning"></use></svg>' \
        '<svg><use href="/assets/icons.svg#icon--warning"></use></svg></p>'
      )
    end

    it 'names a sequence id in an editor id attribute' do
      html = '<fieldset data-dcf-editor="1" data-dcf-editor-field-id="9100001" data-dcf-editor-parent-id="42"></fieldset>'

      expect { dcf_js_guard!(html) }.to raise_error(DcfJsFixtures::LeakedId, /42 at fieldset @data-dcf-editor-parent-id/)
    end
  end
end
