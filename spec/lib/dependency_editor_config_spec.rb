# frozen_string_literal: true

require_relative '../rails_helper'

# WP-24 (editor design 4.1, 5.2 and 5.3, limits design 4.10, project design
# 2.1): the one presenter of the shared dependency editor partial. Attribute
# names per mode and state exactly as the editor design table, all in the
# data-dcf-editor-* namespace; the compact wire shape of wire_values; the
# mapping, dirty, base and conflict rules of both modes; the storage
# attributes only with a column limit (StorageLimits.column_limit stubbed,
# never Redmine::Database.mysql?); the I18N map in the four locales.
RSpec.describe RedmineDependingCustomFields::DependencyEditorConfig do
  fixtures :users

  let(:config) { described_class }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:admin) { User.find(1) }
  let(:list_parent) { dcf_list_field(name: 'Country', values: %w[Belgium France Germany]) }
  let(:list_child) do
    field = dcf_list_field(format: 'depending_list', name: 'City', values: %w[Antwerp Brussels Paris Lyon],
                           parent: list_parent)
    dcf_set_dependencies(field, value_dependencies: { 'Belgium' => %w[Antwerp Brussels], 'Atlantis' => %w[Gone] },
                                default_value_dependencies: { 'Belgium' => 'Brussels' })
  end
  let(:enum_parent) { enum_field('Region', %w[North South Old], inactive: %w[Old]) }
  let(:enum_child) do
    field = enum_field('Product', %w[Alpha Beta Retired], format: 'depending_enumeration', parent: enum_parent,
                                                          inactive: %w[Retired])
    north = key(enum_parent, 'North')
    dcf_set_dependencies(field, value_dependencies: { north => [key(field, 'Alpha'), key(field, 'Retired')] },
                                default_value_dependencies: { north => key(field, 'Alpha') })
  end

  always = %w[data-dcf-editor data-dcf-editor-mode data-dcf-editor-kind data-dcf-editor-field-type
              data-dcf-editor-field-name data-dcf-editor-parent-values data-dcf-editor-mapping
              data-dcf-editor-multiple data-dcf-editor-required data-dcf-editor-max-payload-bytes
              data-dcf-editor-max-form-bytes data-dcf-editor-csv-separator data-dcf-editor-csv-encoding
              data-dcf-editor-warn-unsaved data-dcf-editor-i18n]
  admin_only = %w[data-dcf-editor-values-url data-dcf-editor-parent-source data-dcf-editor-multiple-source
                  data-dcf-editor-required-source data-dcf-editor-format-source data-dcf-editor-default-value-row]
  admin_list = %w[data-dcf-editor-values-source data-dcf-editor-allow-add-values]
  parent_names = %w[data-dcf-editor-parent-id data-dcf-editor-parent-name]
  storage = %w[data-dcf-editor-storage-limit data-dcf-editor-storage-base data-dcf-editor-storage-warn]
  withdrawn = %w[data-dcf-editor-echo data-dcf-editor-pending data-dcf-editor-submit-gate data-dcf-editor-submit
                 data-dcf-storage-limit data-dcf-storage-base data-dcf-values-limit data-dcf-parent-values]

  before do
    allow(User).to receive(:current).and_return(admin)
    allow(limits).to receive(:column_limit).and_return(nil)
  end

  def enum_field(name, names, format: 'enumeration', parent: nil, inactive: [], multiple: false)
    field = dcf_enum_field(format: format, name: name, names: [], parent: parent)
    names.each_with_index do |label, i|
      CustomFieldEnumeration.create!(custom_field_id: field.id, name: label, position: i + 1,
                                     active: !inactive.include?(label))
    end
    field.update!(multiple: true) if multiple
    CustomField.find(field.id)
  end

  def key(field, name)
    CustomField.find(field.id).enumerations.detect { |e| e.name == name }.id.to_s
  end

  def view_for(controller_class = CustomFieldsController)
    controller = controller_class.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller.view_context
  end

  def root_of(editor, view = view_for)
    html = view.content_tag(:fieldset, '', class: 'dcf-dep-editor', data: editor.data_attributes)
    Nokogiri::HTML5.fragment(html).at_css('fieldset')
  end

  def admin_root(field)
    root_of(config.for_admin(field, view_for))
  end

  def project_root(field, parent, **options)
    view = view_for(ProjectCustomFieldConfigurationController)
    root_of(config.for_project(field: field, parent: parent, view: view, **options), view)
  end

  def names(root)
    root.attribute_nodes.map(&:name).grep(/\Adata-/)
  end

  def json(root, name)
    JSON.parse(root["data-dcf-editor-#{name}"])
  end

  def fresh(field)
    CustomField.find(field.id)
  end

  def stale_json(links = { 'Belgium' => %w[Antwerp] })
    JSON.generate('version' => 1, 'base' => 'f' * 64, 'value_dependencies' => links,
                  'default_value_dependencies' => {})
  end

  describe '.wire_values' do
    it 'keeps the key, adds the label only when it differs and active false only when inactive' do
      options = [['Belgium', 'Belgium', true], %w[11 Red] + [true], %w[12 Old] + [false], [13, '13', true],
                 ['x', '', true], ["e\u0301", "\u00e9", true], ['n', 'n', nil]]

      expect(config.wire_values(options)).to eq(
        [{ 'key' => 'Belgium' }, { 'key' => '11', 'label' => 'Red' },
         { 'key' => '12', 'label' => 'Old', 'active' => false }, { 'key' => '13' }, { 'key' => 'x', 'label' => '' },
         { 'key' => "e\u0301", 'label' => "\u00e9" }, { 'key' => 'n' }]
      )
      key_lists = [%w[key], %w[key label], %w[key label active], %w[key], %w[key label], %w[key label], %w[key]]
      expect(config.wire_values(options).map(&:keys)).to eq(key_lists)
      expect(config.wire_values([])).to eq([])
    end

    it 'does not change the tuples it reads' do
      options = [%w[a b] + [false]].freeze
      expect { config.wire_values(options) }.not_to raise_error
      expect(options).to eq([['a', 'b', false]])
    end

    it 'maps the value_options tuples of a list and of an enumeration (inactive included)' do
      expect(config.wire_values(rules.value_options(list_parent)))
        .to eq([{ 'key' => 'Belgium' }, { 'key' => 'France' }, { 'key' => 'Germany' }])
      expect(config.wire_values(rules.value_options(enum_parent))).to eq(
        [{ 'key' => key(enum_parent, 'North'), 'label' => 'North' },
         { 'key' => key(enum_parent, 'South'), 'label' => 'South' },
         { 'key' => key(enum_parent, 'Old'), 'label' => 'Old', 'active' => false }]
      )
    end
  end

  describe 'constants' do
    it 'has its own frozen I18N map with only the WP-24 key, separate from ClientConfig::I18N' do
      expect(config::I18N).to eq('storageEstimate' => :text_dcf_storage_estimate)
      expect(config::I18N).to be_frozen
      expect(RedmineDependingCustomFields::ClientConfig::I18N.size).to eq(11)
      expect(RedmineDependingCustomFields::ClientConfig::I18N).not_to have_key('storageEstimate')
      expect(config.const_defined?(:I18N_KEYS)).to be(false)
    end

    it 'resolves every I18N value in de, en, fr and nl without a missing translation' do
      %w[de en fr nl].each do |locale|
        config::I18N.each_value do |key|
          expect { I18n.t(key, locale: locale, raise: true) }.not_to raise_error, "#{locale}.#{key}"
        end
      end
    end

    it 'interpolates the registry text of text_dcf_storage_estimate in de, en, fr and nl' do
      values = { label: 'L', size: '1', limit: '2', percent: 50 }
      expected = {
        'en' => 'L: about 1 of the 2 bytes that can be stored for this field (50%). Saving is refused above the limit.',
        'de' => "L: etwa 1 der 2 Bytes, die f\u00fcr dieses Feld gespeichert werden k\u00f6nnen (50 %). " \
                'Oberhalb des Limits wird das Speichern abgelehnt.',
        'fr' => "L : environ 1 des 2 octets pouvant \u00eatre enregistr\u00e9s pour ce champ (50 %). " \
                "Au-del\u00e0 de cette limite, l'enregistrement est refus\u00e9.",
        'nl' => 'L: ongeveer 1 van de 2 bytes die voor dit veld kunnen worden opgeslagen (50%). ' \
                'Boven de limiet wordt opslaan geweigerd.'
      }
      expected.each do |locale, text|
        expect(I18n.t(:text_dcf_storage_estimate, locale: locale, **values)).to eq(text), locale
      end
    end

    it 'has the Rack form limits minus margins' do
      expect(config::MAX_FORM_BYTES).to eq('multipart' => 16_252_928, 'urlencoded' => 4_128_768)
      expect(config::MAX_FORM_BYTES).to be_frozen
    end

    it 'is loaded at boot, so the locale parity spec sees the map' do
      expect(Object.const_defined?('RedmineDependingCustomFields::DependencyEditorConfig::I18N')).to be(true)
      main = File.read(File.expand_path('../../lib/redmine_depending_custom_fields.rb', __dir__))
      expect(main).to include("require_relative 'redmine_depending_custom_fields/dependency_editor_config'")
    end
  end

  describe '.for_admin' do
    it 'renders the admin attributes of a saved list child in the table order' do
      root = admin_root(fresh(list_child))

      expect(names(root)).to eq(
        %w[data-dcf-editor data-dcf-editor-mode data-dcf-editor-kind data-dcf-editor-field-id
           data-dcf-editor-field-type data-dcf-editor-field-name data-dcf-editor-parent-id data-dcf-editor-parent-name
           data-dcf-editor-parent-values data-dcf-editor-mapping data-dcf-editor-base data-dcf-editor-multiple
           data-dcf-editor-required data-dcf-editor-values-url data-dcf-editor-parent-source
           data-dcf-editor-values-source data-dcf-editor-multiple-source data-dcf-editor-required-source
           data-dcf-editor-format-source data-dcf-editor-default-value-row data-dcf-editor-allow-add-values
           data-dcf-editor-max-payload-bytes data-dcf-editor-max-form-bytes data-dcf-editor-csv-separator
           data-dcf-editor-csv-encoding data-dcf-editor-warn-unsaved data-dcf-editor-i18n]
      )
    end

    it 'renders the values of a saved list child' do
      field = fresh(list_child)
      root = admin_root(field)

      expect(root['data-dcf-editor']).to eq('1')
      expect(root['data-dcf-editor-mode']).to eq('admin')
      expect(root['data-dcf-editor-kind']).to eq('list')
      expect(root['data-dcf-editor-field-id']).to eq(field.id.to_s)
      expect(root['data-dcf-editor-field-type']).to eq('IssueCustomField')
      expect(root['data-dcf-editor-field-name']).to eq('City')
      expect(root['data-dcf-editor-parent-id']).to eq(list_parent.id.to_s)
      expect(root['data-dcf-editor-parent-name']).to eq('Country')
      expect(json(root, 'parent-values')).to eq([{ 'key' => 'Belgium' }, { 'key' => 'France' }, { 'key' => 'Germany' }])
      expect(json(root, 'mapping')).to eq(
        'value_dependencies' => { 'Belgium' => %w[Antwerp Brussels], 'Atlantis' => %w[Gone] },
        'default_value_dependencies' => { 'Belgium' => 'Brussels' }
      )
      expect(root['data-dcf-editor-base']).to eq(payload.stored_digest(field))
      expect(root['data-dcf-editor-base']).to match(/\A[0-9a-f]{64}\z/)
      expect(root['data-dcf-editor-multiple']).to eq('0')
      expect(root['data-dcf-editor-required']).to eq('0')
      expect(root['data-dcf-editor-values-url']).to eq('/dcf_dependency_editor/values')
      expect(root['data-dcf-editor-parent-source']).to eq('#custom_field_parent_custom_field_id')
      expect(root['data-dcf-editor-values-source']).to eq('#custom_field_possible_values')
      expect(root['data-dcf-editor-multiple-source']).to eq('#custom_field_multiple')
      expect(root['data-dcf-editor-required-source']).to eq('#custom_field_is_required')
      expect(root['data-dcf-editor-format-source']).to eq('#custom_field_field_format')
      expect(root['data-dcf-editor-default-value-row']).to eq('[data-dcf-default-value-row]')
      expect(root['data-dcf-editor-allow-add-values']).to eq('1')
      expect(root['data-dcf-editor-max-payload-bytes']).to eq('4194304')
      expect(json(root, 'max-form-bytes')).to eq('multipart' => 16_252_928, 'urlencoded' => 4_128_768)
      expect(root['data-dcf-editor-csv-separator']).to eq(',')
      expect(root['data-dcf-editor-csv-encoding']).to eq('ISO-8859-1')
      expect(root['data-dcf-editor-warn-unsaved']).to eq('1')
      expect(json(root, 'i18n')).to eq('storageEstimate' => I18n.t(:text_dcf_storage_estimate))
    end

    it 'renders child-values for an enumeration child and no list-only attribute' do
      field = fresh(enum_child)
      root = admin_root(field)

      expect(names(root)).to match_array(always + admin_only + parent_names +
                                         %w[data-dcf-editor-field-id data-dcf-editor-base data-dcf-editor-child-values])
      expect(root['data-dcf-editor-kind']).to eq('enumeration')
      expect(json(root, 'child-values')).to eq(config.wire_values(rules.value_options(field)))
      expect(json(root, 'child-values').last).to eq('key' => key(field, 'Retired'), 'label' => 'Retired',
                                                    'active' => false)
      expect(json(root, 'parent-values')).to eq(config.wire_values(rules.value_options(enum_parent)))
      expect(json(root, 'mapping')['value_dependencies'])
        .to eq(key(enum_parent, 'North') => [key(field, 'Alpha'), key(field, 'Retired')])
    end

    it 'renders a new list field without field id, base and parent, with empty parent values' do
      field = IssueCustomField.new(name: '', field_format: 'depending_list', possible_values: %w[One Two])
      root = admin_root(field)

      expect(names(root)).to match_array(always + admin_only + admin_list)
      expect(root['data-dcf-editor-field-name']).to eq('')
      expect(root['data-dcf-editor-field-type']).to eq('IssueCustomField')
      expect(json(root, 'parent-values')).to eq([])
      expect(json(root, 'mapping')).to eq('value_dependencies' => {}, 'default_value_dependencies' => {})
    end

    it 'renders a new enumeration field with empty child values' do
      field = IssueCustomField.new(name: 'New enum', field_format: 'depending_enumeration')
      root = admin_root(field)

      expect(names(root)).to match_array(always + admin_only + %w[data-dcf-editor-child-values])
      expect(json(root, 'child-values')).to eq([])
    end

    it 'resolves the parent with DependencyRules.parent_of: nothing for a dangling, self, other type or other family parent' do
      project_list = dcf_list_field(name: 'Project list', values: %w[P], type: ProjectCustomField)
      enum = enum_parent
      field = fresh(list_child)
      [999_999_999, field.id, project_list.id, enum.id, nil].each do |pointer|
        candidate = fresh(field)
        candidate.parent_custom_field_id = pointer
        editor = config.for_admin(candidate, view_for)
        root = root_of(editor)

        expect(editor.parent).to be_nil, pointer.inspect
        expect(names(root)).to match_array(always + admin_only + admin_list +
                                           %w[data-dcf-editor-field-id data-dcf-editor-base]), pointer.inspect
        expect(json(root, 'parent-values')).to eq([]), pointer.inspect
        expect(root.to_html).not_to include('Project list')
      end
    end

    it 'renders a parent that is in a stored cycle (raw lookup, the transport prunes against it too)' do
      a = dcf_list_field(format: 'depending_list', name: 'Cycle A', values: %w[a1])
      b = dcf_list_field(format: 'depending_list', name: 'Cycle B', values: %w[b1], parent: a)
      cycled = fresh(a)
      cycled.parent_custom_field_id = b.id
      cycled.save!(validate: false)
      root = admin_root(fresh(b))

      expect(root['data-dcf-editor-parent-id']).to eq(a.id.to_s)
      expect(json(root, 'parent-values')).to eq([{ 'key' => 'a1' }])
    end

    it 'omits dirty on an untouched saved field, also when a String default equals a list of one' do
      field = fresh(list_child)
      expect(names(admin_root(field))).not_to include('data-dcf-editor-dirty')

      field.default_value_dependencies = { 'Belgium' => %w[Brussels] }
      expect(names(admin_root(field))).not_to include('data-dcf-editor-dirty')
    end

    it 'marks an in-memory mapping that differs from the stored one as dirty, never as "0" or "false"' do
      field = fresh(list_child)
      field.value_dependencies = { 'Belgium' => %w[Antwerp] }
      root = admin_root(field)

      expect(root['data-dcf-editor-dirty']).to eq('1')
      expect(json(root, 'mapping')['value_dependencies']).to eq('Belgium' => %w[Antwerp])
      presenter = File.read(File.expand_path('../../lib/redmine_depending_custom_fields/dependency_editor_config.rb',
                                             __dir__))
      expect(presenter).not_to match(/=> false\b|: false\b/)
    end

    it 'renders the posted mapping as applied by the transport and dirty after a save failed for another reason' do
      field = fresh(list_child)
      field.name = ''
      field.dependencies_json = JSON.generate('base' => payload.stored_digest(field),
                                              'value_dependencies' => { 'France' => %w[Paris Unknown], 'X' => %w[Lyon] },
                                              'default_value_dependencies' => { 'France' => 'Paris' })
      expect(field.valid?).to be(false)
      root = admin_root(field)

      expect(json(root, 'mapping')).to eq('value_dependencies' => { 'France' => %w[Paris] },
                                          'default_value_dependencies' => { 'France' => 'Paris' })
      expect(root['data-dcf-editor-dirty']).to eq('1')
      expect(names(root)).not_to include('data-dcf-editor-conflict-mapping')
    end

    it 'marks a copied mapping on a new record as dirty' do
      copy = IssueCustomField.new(name: 'Copy', field_format: 'depending_list', possible_values: %w[Antwerp])
      copy.parent_custom_field_id = list_parent.id
      copy.value_dependencies = { 'Belgium' => %w[Antwerp] }
      root = admin_root(copy)

      expect(root['data-dcf-editor-dirty']).to eq('1')
      expect(names(root)).not_to include('data-dcf-editor-base')
      expect(names(root)).not_to include('data-dcf-editor-field-id')
    end

    context 'when the last validation refused the payload as stale' do
      it 'renders the conflict mapping, the stored mapping, the fresh base and no dirty flag' do
        field = fresh(list_child)
        field.dependencies_json = stale_json
        expect(field.valid?).to be(false)
        root = admin_root(field)

        expect(json(root, 'conflict-mapping')).to eq(JSON.parse(field.dcf_dependencies_conflict.to_json))
        expect(json(root, 'conflict-mapping')).to eq(
          'value_dependencies' => { 'Belgium' => %w[Antwerp] }, 'default_value_dependencies' => {},
          'source' => 'editor', 'import' => nil
        )
        expect(json(root, 'mapping')['value_dependencies']).to eq('Belgium' => %w[Antwerp Brussels],
                                                                  'Atlantis' => %w[Gone])
        expect(root['data-dcf-editor-base']).to eq(payload.stored_digest(field))
        expect(names(root)).not_to include('data-dcf-editor-dirty')
      end

      it 'takes the mapping from the stored row even when nested params changed the record too' do
        field = fresh(list_child)
        field.value_dependencies = { 'France' => %w[Paris] }
        field.dependencies_json = stale_json
        expect(field.valid?).to be(false)
        root = admin_root(field)

        expect(json(root, 'mapping')['value_dependencies']).to eq('Belgium' => %w[Antwerp Brussels],
                                                                  'Atlantis' => %w[Gone])
        expect(json(root, 'mapping')['default_value_dependencies']).to eq('Belgium' => 'Brussels')
        expect(names(root)).not_to include('data-dcf-editor-dirty')
      end
    end

    it 'reads the stored digest once per render' do
      field = fresh(list_child)
      allow(payload).to receive(:stored_digest).and_call_original
      config.for_admin(field, view_for)

      expect(payload).to have_received(:stored_digest).once
    end

    it 'builds the values url through the view, so a relative url root is kept' do
      controller = CustomFieldsController.new
      request = ActionDispatch::TestRequest.create
      request.routes = Rails.application.routes
      request.script_name = '/redmine'
      controller.request = request
      controller.response = ActionDispatch::TestResponse.new
      root = root_of(config.for_admin(fresh(list_child), controller.view_context))

      expect(root['data-dcf-editor-values-url']).to eq('/redmine/dcf_dependency_editor/values')
    end

    it 'gives the admin input name and id, the parent and the multiple and required flags' do
      field = fresh(list_child)
      field.multiple = true
      field.is_required = true
      editor = config.for_admin(field, view_for)
      root = root_of(editor)

      expect(editor.input_name).to eq('custom_field[dependencies_json]')
      expect(editor.input_id).to eq('custom_field_dependencies_json')
      expect(editor.parent).to eq(list_parent)
      expect(root['data-dcf-editor-multiple']).to eq('1')
      expect(root['data-dcf-editor-required']).to eq('1')
    end

    it 'renders warn-unsaved 0 when the user turned the warning off' do
      admin.pref.warn_on_leaving_unsaved = '0'
      expect(admin_root(fresh(list_child))['data-dcf-editor-warn-unsaved']).to eq('0')
    end

    it 'renders the csv separator and the i18n map in the current locale' do
      I18n.with_locale(:de) do
        root = admin_root(fresh(list_child))
        expect(root['data-dcf-editor-csv-separator']).to eq(';')
        expect(json(root, 'i18n')).to eq('storageEstimate' => I18n.t(:text_dcf_storage_estimate))
        expect(json(root, 'i18n')['storageEstimate']).to include('%{label}', '%{size}', '%{limit}', '%{percent}')
      end
    end
  end

  describe 'the required warning' do
    def editor_for(field)
      config.for_admin(field, view_for)
    end

    it 'is shown for a required child with an active parent value without links' do
      field = fresh(list_child)
      field.is_required = true
      expect(editor_for(field).required_warning?).to be(true)
    end

    it 'is not shown when every active parent value has links, the field is optional or has no parent' do
      field = fresh(list_child)
      field.is_required = true
      field.value_dependencies = { 'Belgium' => %w[Antwerp], 'France' => %w[Paris], 'Germany' => %w[Lyon] }
      expect(editor_for(field).required_warning?).to be(false)

      expect(editor_for(fresh(list_child)).required_warning?).to be(false)
      orphan = fresh(list_child)
      orphan.is_required = true
      orphan.parent_custom_field_id = nil
      expect(editor_for(orphan).required_warning?).to be(false)
    end

    it 'counts only active parent values (an inactive one without links gives no warning)' do
      field = fresh(enum_child)
      field.is_required = true
      field.value_dependencies = { key(enum_parent, 'North') => [key(field, 'Alpha')],
                                   key(enum_parent, 'South') => [key(field, 'Beta')] }
      expect(editor_for(field).required_warning?).to be(false)
    end

    it 'is not shown for a parent in or below a stored cycle (the effective-parent guard)' do
      a = dcf_list_field(format: 'depending_list', name: 'Ring A', values: %w[a1])
      b = dcf_list_field(format: 'depending_list', name: 'Ring B', values: %w[b1], parent: a)
      ring = fresh(a)
      ring.parent_custom_field_id = b.id
      ring.save!(validate: false)
      child = dcf_list_field(format: 'depending_list', name: 'Below ring', values: %w[c1], parent: a)
      child = fresh(child)
      child.is_required = true

      editor = editor_for(child)
      expect(editor.parent).to eq(a)
      expect(editor.required_warning?).to be(false)
    end

    it 'renders the warning text in an icon span, with the sprite only when the view has sprite_icon' do
      view = view_for
      allow(view).to receive(:respond_to?).and_call_original
      allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(false)
      html = config.for_admin(fresh(list_child), view).required_warning_html
      span = Nokogiri::HTML5.fragment(html).at_css('span.icon.icon-warning')

      expect(html).to be_html_safe
      expect(span.text).to eq(I18n.t(:warning_required_child_no_options))
      expect(span.css('svg')).to be_empty
    end
  end

  describe '.for_project' do
    let(:project_always) { always + %w[data-dcf-editor-child-values data-dcf-editor-always-submit] }

    it 'renders the project attributes of a list child and nothing admin-only' do
      field = fresh(list_child)
      editor = config.for_project(field: field, parent: list_parent, view: view_for(ProjectCustomFieldConfigurationController))
      root = root_of(editor)

      expect(names(root)).to match_array(project_always + parent_names + %w[data-dcf-editor-field-id])
      expect(root['data-dcf-editor-mode']).to eq('project')
      expect(root['data-dcf-editor-always-submit']).to eq('1')
      expect(json(root, 'child-values')).to eq(config.wire_values(rules.value_options(field)))
      expect(json(root, 'mapping')).to eq(
        'value_dependencies' => { 'Belgium' => %w[Antwerp Brussels], 'Atlantis' => %w[Gone] },
        'default_value_dependencies' => { 'Belgium' => 'Brussels' }
      )
      expect(editor.input_name).to eq('dependencies_json')
      expect(editor.input_id).to eq('dcf_dependencies_json')
      expect(editor.parent).to eq(list_parent)
    end

    it 'renders an enumeration child with parent and child values' do
      field = fresh(enum_child)
      root = project_root(field, enum_parent)

      expect(names(root)).to match_array(project_always + parent_names + %w[data-dcf-editor-field-id])
      expect(json(root, 'parent-values')).to eq(config.wire_values(rules.value_options(enum_parent)))
      expect(json(root, 'child-values')).to eq(config.wire_values(rules.value_options(field)))
    end

    it 'renders only the given parent: nothing when it is nil, even with a real pointer' do
      root = project_root(fresh(list_child), nil)

      expect(names(root)).not_to include(*parent_names)
      expect(json(root, 'parent-values')).to eq([])
      expect(root.to_html).not_to include('Country')
    end

    it 'renders a posted ok payload as the mapping with dirty 1 (failed-save re-render)' do
      posted = payload.parse(JSON.generate('value_dependencies' => { 'France' => %w[Paris Lyon] },
                                           'default_value_dependencies' => { 'France' => 'Lyon' }))
      root = project_root(fresh(list_child), list_parent, posted: posted)

      expect(json(root, 'mapping')).to eq('value_dependencies' => posted.value_dependencies,
                                          'default_value_dependencies' => posted.default_value_dependencies)
      expect(root['data-dcf-editor-dirty']).to eq('1')
    end

    it 'renders dirty 1 for a posted ok payload equal to the stored mapping (P2, no digest compare)' do
      field = fresh(list_child)
      posted = payload.parse(JSON.generate('value_dependencies' => rules.mapping(field),
                                           'default_value_dependencies' => rules.defaults(field)))
      root = project_root(fresh(list_child), list_parent, posted: posted)

      expect(posted).to be_ok
      expect(json(root, 'mapping')).to eq('value_dependencies' => rules.mapping(field),
                                          'default_value_dependencies' => rules.defaults(field))
      expect(root['data-dcf-editor-dirty']).to eq('1')
    end

    it 'renders the stored mapping, not dirty, for a posted payload that is not ok' do
      posted = payload.parse('{"value_dependencies":')
      root = project_root(fresh(list_child), list_parent, posted: posted)

      expect(json(root, 'mapping')['value_dependencies']).to eq('Belgium' => %w[Antwerp Brussels], 'Atlantis' => %w[Gone])
      expect(names(root)).not_to include('data-dcf-editor-dirty')
    end

    it 'renders a conflict as the conflict mapping next to the stored mapping, not dirty, and wins over posted' do
      conflict = payload.parse(JSON.generate('source' => 'import', 'import' => { 'mode' => 'merge', 'rows' => 4 },
                                             'value_dependencies' => { 'France' => %w[Paris] }))
      root = project_root(fresh(list_child), list_parent, conflict: conflict, posted: conflict)

      expect(json(root, 'conflict-mapping')).to eq('value_dependencies' => { 'France' => %w[Paris] },
                                                   'default_value_dependencies' => {}, 'source' => 'import',
                                                   'import' => { 'mode' => 'merge', 'rows' => 4 })
      expect(json(root, 'mapping')['value_dependencies']).to eq('Belgium' => %w[Antwerp Brussels], 'Atlantis' => %w[Gone])
      expect(names(root)).not_to include('data-dcf-editor-dirty')
      ignored = project_root(fresh(list_child), list_parent, conflict: payload.parse('{"source":"bad"}'))
      expect(names(ignored)).not_to include('data-dcf-editor-conflict-mapping')
    end

    it 'takes exactly the keyword arguments field, parent, view, posted and conflict' do
      view = view_for(ProjectCustomFieldConfigurationController)
      expect { config.for_project(field: fresh(list_child), parent: nil, view: view, input_value: '{}') }
        .to raise_error(ArgumentError)
      expect { config.for_project(field: fresh(list_child), view: view) }.to raise_error(ArgumentError)
      expect(config.method(:for_project).parameters)
        .to eq([[:keyreq, :field], [:keyreq, :parent], [:keyreq, :view], [:key, :posted], [:key, :conflict]])
      expect(config.method(:for_admin).parameters).to eq([[:req, :field], [:req, :view]])
    end
  end

  describe 'storage attributes' do
    def stub_limits(format_store, possible_values)
      allow(limits).to receive(:column_limit).with('format_store').and_return(format_store)
      allow(limits).to receive(:column_limit).with('possible_values').and_return(possible_values)
    end

    it 'renders none of the four without a column limit (PostgreSQL, SQLite)' do
      stub_limits(nil, nil)
      [admin_root(fresh(list_child)), admin_root(fresh(enum_child)), project_root(fresh(list_child), list_parent)]
        .each do |root|
          expect(names(root)).not_to include(*storage, 'data-dcf-editor-values-limit')
        end
    end

    it 'renders all four on an admin list child, the base exactly StorageLimits.base_bytes(field)' do
      stub_limits(65_535, 65_535)
      field = fresh(list_child)
      root = admin_root(field)

      expect(root['data-dcf-editor-storage-limit']).to eq('65535')
      expect(root['data-dcf-editor-storage-base']).to eq(limits.base_bytes(field).to_s)
      expect(root['data-dcf-editor-storage-base'].to_i).to be_positive
      expect(root['data-dcf-editor-values-limit']).to eq('65535')
      expect(root['data-dcf-editor-storage-warn']).to eq('90')
      expect(names(root).last(6)).to eq(%w[data-dcf-editor-storage-limit data-dcf-editor-storage-base
                                           data-dcf-editor-values-limit data-dcf-editor-storage-warn
                                           data-dcf-editor-warn-unsaved data-dcf-editor-i18n])
    end

    it 'renders no values limit for an admin enumeration child and none in project mode' do
      stub_limits(65_535, 65_535)
      enum_root = admin_root(fresh(enum_child))
      project = project_root(fresh(list_child), list_parent)

      [enum_root, project].each do |root|
        expect(names(root)).to include(*storage)
        expect(names(root)).not_to include('data-dcf-editor-values-limit')
      end
      expect(project['data-dcf-editor-storage-limit']).to eq('65535')
    end

    it 'renders the values limit and the warn percent alone when only possible_values has a limit' do
      stub_limits(nil, 65_535)
      root = admin_root(fresh(list_child))

      expect(names(root)).to include('data-dcf-editor-values-limit', 'data-dcf-editor-storage-warn')
      expect(names(root)).not_to include('data-dcf-editor-storage-limit', 'data-dcf-editor-storage-base')
    end
  end

  describe 'the attribute namespace' do
    it 'uses only data-dcf-editor-* names, none of the issue-form or withdrawn names, in every mode' do
      allow(limits).to receive(:column_limit).and_return(65_535)
      stale = fresh(list_child)
      stale.dependencies_json = stale_json
      stale.valid?
      roots = [admin_root(fresh(list_child)), admin_root(fresh(enum_child)), admin_root(stale),
               project_root(fresh(enum_child), enum_parent, posted: payload.parse('{}'))]
      roots.each do |root|
        names(root).each do |name|
          expect(name).to match(/\Adata-dcf-editor(-[a-z0-9]+)*\z/)
          expect(name).not_to match(/\Adata-dcf-parent/)
        end
        expect(names(root)).not_to include(*withdrawn)
      end
    end
  end

  describe 'cost (G6)' do
    it 'runs the same number of queries for 3 and 60 enumerations on parent and child, and reads no index' do
      allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original
      admin.pref
      counts = [3, 60].map do |size|
        parent = enum_field("Parent #{size}", (1..size).map { |i| "P#{i}" })
        child = enum_field("Child #{size}", (1..size).map { |i| "C#{i}" }, format: 'depending_enumeration',
                                                                           parent: parent)
        child = fresh(child)
        child.is_required = true
        view = view_for
        dcf_count_queries { config.for_admin(child, view) }
      end

      expect(counts.first).to eq(counts.last)
      expect(RedmineDependingCustomFields::FieldIndex).not_to have_received(:load)
    end

    it 'runs the same number of queries for 10 and 1,000 links on a list child' do
      admin.pref
      counts = [10, 1_000].map do |size|
        values = (1..size).map { |i| "v#{i}" }
        parent = dcf_list_field(name: "Links parent #{size}", values: values)
        child = dcf_list_field(format: 'depending_list', name: "Links child #{size}", values: values, parent: parent)
        child = dcf_set_dependencies(child, value_dependencies: values.to_h { |v| [v, [v]] })
        view = view_for
        dcf_count_queries { config.for_admin(fresh(child), view) }
      end

      expect(counts.first).to eq(counts.last)
    end

    [[:list, 'S1'], [:enumeration, 'S2']].each do |kind, scenario|
      it "keeps the #{scenario} editor data attributes within the declared budget (27 x 5,570)", :large do
        parent_values = DcfLargeList.names(27, prefix: 'P')
        child_values = DcfLargeList.names(5_570, prefix: 'C')
        if kind == :list
          parent = dcf_list_field(name: "#{scenario} parent", values: parent_values)
          child = dcf_list_field(format: 'depending_list', name: "#{scenario} child", values: child_values,
                                 parent: parent)
          parent_keys = parent_values
          child_keys = child_values
        else
          parent = dcf_enum_field(name: "#{scenario} parent", names: parent_values)
          child = dcf_enum_field(format: 'depending_enumeration', name: "#{scenario} child", names: [], parent: parent)
          CustomFieldEnumeration.insert_all(child_values.each_with_index.map do |name, i|
            { custom_field_id: child.id, name: name, position: i + 1, active: true }
          end)
          parent_keys = parent.enumerations.sort_by(&:position).map { |e| e.id.to_s }
          child_keys = CustomFieldEnumeration.where(custom_field_id: child.id).order(:position).pluck(:id).map(&:to_s)
        end
        mapping = DcfLargeList.partition(parent_keys, child_keys)
        child = dcf_set_dependencies(child, value_dependencies: mapping,
                                            default_value_dependencies: DcfLargeList.first_child_defaults(mapping))
        view = view_for
        html = view.content_tag(:fieldset, '', data: config.for_admin(fresh(child), view).data_attributes)
        bytes = html.bytesize
        budget = { list: 300_000, enumeration: 700_000 }.fetch(kind)
        RSpec.configuration.reporter.message("DCF PERF editor data attributes #{scenario} (#{kind}): #{bytes} bytes")

        expect(JSON.parse(Nokogiri::HTML5.fragment(html).at_css('fieldset')['data-dcf-editor-mapping'])
                 .fetch('value_dependencies').values.flatten.size).to eq(5_570)
        expect(bytes).to be <= budget
      end
    end
  end

  it 'keeps no state on the module' do
    config.for_admin(fresh(list_child), view_for)
    config.for_project(field: fresh(enum_child), parent: enum_parent, view: view_for)
    config.wire_values([%w[a b] + [false]])

    expect(config.instance_variables).to eq([])
    expect(config.class_variables).to eq([])
  end
end
