# frozen_string_literal: true

require_relative '../../rails_helper'

# WP-24 (editor design 5.2, compat section 3 gap 1, quality G3 and G5): the
# shared editor partial. Exactly one named control, the hidden input, always
# blank; every data attribute escaped exactly once (tricky names and values
# round-trip through JSON.parse); the help, noscript, placeholder and required
# warning paragraphs; the sprite_icon guard on and off; no inline script.
RSpec.describe 'depending_custom_fields/_dependency_editor', type: :view do
  fixtures :users

  let(:config) { RedmineDependingCustomFields::DependencyEditorConfig }
  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:parent) { dcf_list_field(name: 'Country', values: %w[Belgium France]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: 'City', values: %w[Antwerp Brussels Paris], parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'Belgium' => %w[Antwerp] })
  end
  let(:tricky) do
    ['"><script>alert(1)</script>', '</script>', '</fieldset>', '[x]', 'a]', '&amp;', '&quot;', "O'Brien",
     'say "hi"', '__proto__', 'constructor', "e\u0301", "\u00dcn\u00efc\u00f8d\u00e9", '<img src=x onerror=alert(1)>']
  end

  before do
    allow(User).to receive(:current).and_return(User.find(1))
    allow(RedmineDependingCustomFields::StorageLimits).to receive(:column_limit).and_return(nil)
  end

  def stub_sprite_icon(available)
    allow(view).to receive(:respond_to?).and_call_original
    allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(available)
    return unless available

    allow(view).to receive(:sprite_icon).with('warning', instance_of(String)) do |_name, label|
      '<svg class="warning-svg"></svg>'.html_safe + view.content_tag(:span, label, class: 'icon-label')
    end
  end

  # The output of this render (rendered collects every render of an example on Rails 6.1).
  def render_editor(editor)
    Nokogiri::HTML5.fragment(render(partial: 'depending_custom_fields/dependency_editor', locals: { editor: editor }))
  end

  def admin_editor(field = CustomField.find(child.id))
    config.for_admin(field, view)
  end

  def root(fragment)
    fragment.at_css('fieldset')
  end

  it 'renders one fieldset with the legend, the hidden input, help, noscript, placeholder, warning and app, in order' do
    stub_sprite_icon(false)
    fragment = render_editor(admin_editor)
    fieldset = root(fragment)

    expect(fragment.element_children.map(&:name)).to eq(['fieldset'])
    expect(fieldset['class']).to eq('dcf-dep-editor')
    expect(fieldset['data-dcf-editor']).to eq('1')
    expect(fieldset.element_children.map { |n| [n.name, n['class']] }).to eq(
      [['legend', nil], ['input', nil], ['p', 'dcf-dep-editor__help'], ['noscript', nil],
       ['p', 'dcf-dep-editor__placeholder dcf-hidden'], ['p', 'dcf-dep-editor__required dcf-hidden'],
       ['div', 'dcf-dep-editor__app']]
    )
    expect(fieldset.at_css('> legend').text).to eq(I18n.t(:field_value_dependencies))
    expect(fieldset.at_css('> p.dcf-dep-editor__help > em.info').text).to eq(I18n.t(:text_dcf_editor_help))
    expect(fieldset.at_css('> noscript > p.warning').text).to eq(I18n.t(:text_dcf_editor_noscript))
    placeholder = fieldset.at_css('> p[data-dcf-editor-placeholder]')
    expect(placeholder.at_css('> em.info').text).to eq(I18n.t(:text_dcf_editor_select_parent))
    expect(fieldset.at_css('> p[data-dcf-editor-required-warning]')).not_to be_nil
    app = fieldset.at_css('> div[data-dcf-editor-app]')
    expect(app).to have_attribute('hidden')
    expect(app.children).to be_empty
  end

  it 'has exactly one named control, the blank hidden input with the admin name and id' do
    stub_sprite_icon(false)
    fragment = render_editor(admin_editor)

    expect(fragment.css('[name]').map { |n| [n.name, n['type'], n['name'], n['value']] })
      .to eq([['input', 'hidden', 'custom_field[dependencies_json]', '']])
    input = fragment.at_css('input')
    expect(input['id']).to eq('custom_field_dependencies_json')
    expect(input['autocomplete']).to eq('off')
    expect(input['data-dcf-editor-input']).to eq('1')
    expect(fragment.css('[id]').map { |n| n['id'] }).to eq(['custom_field_dependencies_json'])
  end

  it 'keeps the hidden input blank after a failed save with a posted payload and with request params' do
    stub_sprite_icon(false)
    field = CustomField.find(child.id)
    posted = JSON.generate('base' => payload.stored_digest(field), 'value_dependencies' => { 'France' => %w[Paris] })
    field.name = ''
    field.dependencies_json = posted
    expect(field.valid?).to be(false)
    controller.params[:custom_field] = { dependencies_json: posted }
    fragment = render_editor(admin_editor(field))

    expect(fragment.css('[name]').map { |n| n['value'] }).to eq([''])
    expect(rendered).not_to include(ERB::Util.html_escape(posted))
    expect(rendered).not_to include(posted)
    expect(fragment.at_css('fieldset')['data-dcf-editor-dirty']).to eq('1')
    expect(JSON.parse(fragment.at_css('fieldset')['data-dcf-editor-mapping'])['value_dependencies'])
      .to eq('France' => %w[Paris])
    expect(fragment.at_css('fieldset').attribute_nodes.map(&:name)).not_to include('data-dcf-editor-echo')
  end

  it 'keeps the hidden input blank on a conflict re-render' do
    stub_sprite_icon(false)
    field = CustomField.find(child.id)
    field.dependencies_json = JSON.generate('base' => 'a' * 64, 'value_dependencies' => { 'France' => %w[Paris] })
    expect(field.valid?).to be(false)
    fragment = render_editor(admin_editor(field))

    expect(fragment.css('[name]').map { |n| n['value'] }).to eq([''])
    expect(fragment.at_css('fieldset')['data-dcf-editor-conflict-mapping']).to be_present
  end

  it 'uses the project name and id in project mode' do
    stub_sprite_icon(false)
    editor = config.for_project(field: CustomField.find(child.id), parent: parent, view: view)
    fragment = render_editor(editor)

    expect(fragment.css('[name]').map { |n| [n['name'], n['value']] }).to eq([['dependencies_json', '']])
    expect(fragment.css('[id]').map { |n| n['id'] }).to eq(['dcf_dependencies_json'])
    expect(fragment.at_css('fieldset')['data-dcf-editor-mode']).to eq('project')
  end

  it 'shows the placeholder without a parent and hides it with one' do
    stub_sprite_icon(false)
    field = CustomField.find(child.id)
    with_parent = render_editor(admin_editor(field)).at_css('p[data-dcf-editor-placeholder]')
    expect(with_parent['class'].split).to include('dcf-hidden')

    field.parent_custom_field_id = 999_999_999
    without = render_editor(admin_editor(field)).at_css('p[data-dcf-editor-placeholder]')
    expect(without['class'].split).to eq(['dcf-dep-editor__placeholder'])
  end

  context 'when sprite_icon is not available (Redmine 5.1)' do
    before { stub_sprite_icon(false) }

    it 'renders the required warning as the plain text in span.icon.icon-warning, shown when required' do
      field = CustomField.find(child.id)
      field.is_required = true
      warning = render_editor(admin_editor(field)).at_css('p[data-dcf-editor-required-warning]')

      expect(warning['class'].split).to eq(['dcf-dep-editor__required'])
      span = warning.at_css('> span.icon.icon-warning')
      expect(span.text).to eq(I18n.t(:warning_required_child_no_options))
      expect(span.css('svg')).to be_empty
      expect(rendered).not_to include('&lt;span')
    end
  end

  context 'when sprite_icon is available (Redmine 6.0 and later)' do
    before { stub_sprite_icon(true) }

    it 'renders the warning sprite with the text as its label' do
      field = CustomField.find(child.id)
      field.is_required = true
      span = render_editor(admin_editor(field)).at_css('p[data-dcf-editor-required-warning] > span.icon.icon-warning')

      expect(span.at_css('svg.warning-svg')).not_to be_nil
      expect(span.at_css('span.icon-label').text).to eq(I18n.t(:warning_required_child_no_options))
    end
  end

  it 'escapes tricky names, keys and values exactly once, so each attribute decodes to the Ruby data' do
    stub_sprite_icon(false)
    tricky_parent = dcf_list_field(name: '<img src=x onerror=alert(1)>', values: tricky)
    tricky_child = dcf_list_field(format: 'depending_list', name: '"><script>x</script> & \'q\'',
                                  values: tricky, parent: tricky_parent)
    links = tricky.each_with_index.to_h { |value, i| [value, [value, tricky[(i + 1) % tricky.size]]] }
    tricky_child = dcf_set_dependencies(tricky_child, value_dependencies: links,
                                                      default_value_dependencies: { tricky.first => tricky.last })
    fragment = render_editor(config.for_admin(CustomField.find(tricky_child.id), view))
    fieldset = fragment.at_css('fieldset')

    expect(fieldset['data-dcf-editor-field-name']).to eq('"><script>x</script> & \'q\'')
    expect(fieldset['data-dcf-editor-parent-name']).to eq('<img src=x onerror=alert(1)>')
    expect(JSON.parse(fieldset['data-dcf-editor-parent-values'])).to eq(tricky.map { |v| { 'key' => v } })
    expect(JSON.parse(fieldset['data-dcf-editor-mapping'])).to eq(
      'value_dependencies' => links, 'default_value_dependencies' => { tricky.first => tricky.last }
    )
    expect(rendered).not_to include('"><script>')
    expect(rendered).not_to include('<img')
    expect(fragment.css('script')).to be_empty
    expect(fragment.css('img')).to be_empty
    expect(fragment.css('*').flat_map { |n| n.attribute_nodes.map(&:name) }.grep(/\Aon|\Astyle\z/)).to eq([])
  end

  %w[en de fr nl].each do |locale|
    it "renders in #{locale} without a missing translation" do
      stub_sprite_icon(false)
      I18n.with_locale(locale) do
        field = CustomField.find(child.id)
        field.is_required = true
        fragment = render_editor(admin_editor(field))

        expect(rendered).not_to match(/translation missing|translation_missing/i)
        expect(fragment.at_css('p.dcf-dep-editor__help').text).to eq(I18n.t(:text_dcf_editor_help))
        expect(fragment.at_css('noscript p').text).to eq(I18n.t(:text_dcf_editor_noscript))
        expect(fragment.at_css('p[data-dcf-editor-placeholder]').text).to eq(I18n.t(:text_dcf_editor_select_parent))
        expect(fragment.at_css('p[data-dcf-editor-required-warning]').text)
          .to eq(I18n.t(:warning_required_child_no_options))
      end
    end
  end

  it 'has no inline script, no html_safe and no raw in the partial source' do
    source = File.read(File.expand_path('../../../app/views/depending_custom_fields/_dependency_editor.html.erb',
                                        __dir__))
    expect(source).not_to match(/<script|javascript_tag|html_safe|raw\(|content_for|_include_tag|stylesheet_link_tag/)
    expect(source).not_to include('input_value')
  end
end
