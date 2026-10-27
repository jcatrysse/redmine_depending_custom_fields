# frozen_string_literal: true

require_relative '../rails_helper'

# WP-04 characterization: pins what the admin custom field form (core
# CustomFieldsController#update) stores today (0.0.16) from the nested params
# the plugin's dependency matrix posts, including known defects. Only WP-22
# (admin JSON transport) and WP-25 (editor replaces the matrix) may change an
# expectation here, and only as a listed flip.
RSpec.describe 'Admin custom field form dependency params (characterization)', type: :request do
  fixtures :users

  let(:parent) { dcf_list_field(name: 'Parent', values: %w[A B]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] },
                                default_value_dependencies: { 'A' => 'a1' })
  end

  before { allow(User).to receive(:current).and_return(dcf_admin) }

  def edit_form(field)
    get "/custom_fields/#{field.id}/edit"
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css('form#custom_field_form')
  end

  # Flipped by WP-25: the matrix is gone; the editor posts the mapping as
  # one JSON field with the base of the rendered page. Nokogiri runs no JS,
  # so the payload is written here as the editor serializes it.
  def editor_payload(form, links, defaults = {})
    root = form.at_css('fieldset[data-dcf-editor]')
    payload = { 'version' => 1, 'source' => 'editor', 'base' => root['data-dcf-editor-base'],
                'value_dependencies' => links, 'default_value_dependencies' => defaults }
    form.at_css('input[name="custom_field[dependencies_json]"]')['value'] = JSON.generate(payload)
  end

  def rendered_mapping(form)
    JSON.parse(form.at_css('fieldset[data-dcf-editor]')['data-dcf-editor-mapping'])
  end

  # The [name, value] entries a browser submits for +form+ as rendered: named,
  # enabled controls only; checkboxes and radios only when checked; a single
  # select falls back to its first option.
  def browser_entries(form)
    form.css('input, select, textarea').each_with_object([]) do |control, entries|
      next if control['name'].to_s.empty? || control.key?('disabled')

      entries.concat(control_entries(control))
    end
  end

  def control_entries(control)
    name = control['name']
    case control.name
    when 'select' then select_entries(control).map { |value| [name, value] }
    when 'textarea' then [[name, control.text.sub(/\A\r?\n/, '')]]
    else input_entries(control)
    end
  end

  def select_entries(select)
    options = select.css('option').reject { |o| o.key?('disabled') }
    chosen = options.select { |o| o.key?('selected') }
    chosen = options.first(1) if chosen.empty? && !select.key?('multiple')
    chosen.map { |o| o['value'] || o.text }
  end

  def input_entries(input)
    type = (input['type'] || 'text').downcase
    return [] if %w[submit button image file reset].include?(type)

    checkable = %w[checkbox radio].include?(type)
    return [] if checkable && !input.key?('checked')

    [[input['name'], input['value'] || (checkable ? 'on' : '')]]
  end

  def submit(form)
    post form['action'], params: URI.encode_www_form(browser_entries(form)),
                         headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
  end

  def stored(field)
    field.reload
    [field.value_dependencies, field.default_value_dependencies]
  end

  # Flipped by WP-25 (was: 'renders each cell as a bare checkbox named
  # after the raw parent value, with no hidden companion'): the editor
  # replaces the matrix (editor design 5.2).
  describe 'what the editor posts' do
    it 'renders one blank hidden dependencies_json input and no nested dependency control' do
      form = edit_form(child)

      expect(form.css('[name^="custom_field[value_dependencies]"], [name^="custom_field[default_value_dependencies]"]'))
        .to be_empty
      controls = form.css('[name="custom_field[dependencies_json]"]')
      expect(controls.map { |c| [c.name, c['type'], c['value']] }).to eq([['input', 'hidden', '']])
      expect(rendered_mapping(form)).to eq('value_dependencies' => { 'A' => %w[a1], 'B' => %w[b1] },
                                           'default_value_dependencies' => { 'A' => 'a1' })
    end
  end

  describe 'saving the form' do
    # Flipped by WP-25: sent through the editor payload instead of a matrix
    # cell and a per-parent default select; same stored result.
    it 'stores a newly ticked cell and a newly chosen per-parent default' do
      form = edit_form(child)
      editor_payload(form, { 'A' => %w[a1 b1], 'B' => %w[b1] }, { 'A' => 'a1', 'B' => 'b1' })

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(stored(child)).to eq([{ 'A' => %w[a1 b1], 'B' => %w[b1] }, { 'A' => 'a1', 'B' => 'b1' }])
    end

    # Flipped by WP-25 (was: 'ignores a matrix with every cell unticked: no
    # value_dependencies entry is posted and the mapping is kept'): the
    # editor posts the empty mapping, which clears it.
    it 'clears the mapping when every link is unticked' do
      form = edit_form(child)
      editor_payload(form, {})

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(stored(child)).to eq([{}, {}])
    end

    # Flipped by WP-25 (was: 'drops a fully unticked parent row but keeps
    # its default while another row stays ticked'): unlinking a child drops
    # it from that parent's defaults in the editor, so the default goes too.
    it 'drops a fully unticked parent row and its default while another row stays ticked' do
      form = edit_form(child)
      editor_payload(form, { 'B' => %w[b1] })

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(stored(child)).to eq([{ 'B' => %w[b1] }, {}])
    end

    # Flipped by WP-25 (was: 'stores a corrupted entry under the text before
    # "]" for a parent value containing "]"'): the JSON field carries the
    # key as it is.
    it 'stores a parent value containing "]" byte for byte' do
      bracket_parent = dcf_list_field(name: 'Bracket', values: ['A', 'C]D'])
      bracket_child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: bracket_parent)
      dcf_set_dependencies(bracket_child, value_dependencies: { 'A' => %w[a1] })
      form = edit_form(bracket_child)
      editor_payload(form, { 'A' => %w[a1], 'C]D' => %w[a1 b1] })

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{bracket_child.id}/edit")
      expect(stored(bracket_child)).to eq([{ 'A' => %w[a1], 'C]D' => %w[a1 b1] }, {}])
    end

    # Flipped by WP-25 (was: 'turns the save into an unrouted POST (404)
    # when a "]" value starts with another ticked parent value'): the body
    # parses, the name change and the link are saved.
    it 'saves a "]" value that starts with another ticked parent value, and the name change' do
      bracket_parent = dcf_list_field(name: 'Bracket', values: ['A', 'A]B'])
      bracket_child = dcf_list_field(format: 'depending_list', name: 'Before', values: %w[a1 b1],
                                     parent: bracket_parent)
      dcf_set_dependencies(bracket_child, value_dependencies: { 'A' => %w[a1] })
      form = edit_form(bracket_child)
      editor_payload(form, { 'A' => %w[a1], 'A]B' => %w[b1] })
      form.at_css('input[name="custom_field[name]"]')['value'] = 'After'

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{bracket_child.id}/edit")
      expect(bracket_child.reload.name).to eq('After')
      expect(stored(bracket_child)).to eq([{ 'A' => %w[a1], 'A]B' => %w[b1] }, {}])
    end

    # Flipped by WP-25 (was: 'drops links to and from inactive enumerations
    # and a default naming an inactive child on an unchanged save'): the
    # editor renders and posts them (inactive values are in its lists).
    it 'keeps links to and from inactive enumerations and a default naming an inactive child on an unchanged save' do
      enum_parent = dcf_enum_field(name: 'EnumParent', names: %w[X Y Z])
      enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1 z1], parent: enum_parent)
      x, y, z = enum_parent.enumerations.order(:position).map { |e| e.id.to_s }
      x1, y1, z1 = enum_child.enumerations.order(:position).map { |e| e.id.to_s }
      dcf_set_dependencies(enum_child, value_dependencies: { x => [x1, z1], y => [y1], z => [x1] },
                                       default_value_dependencies: { x => z1, y => y1, z => x1 })
      CustomFieldEnumeration.where(id: [z, z1]).update_all(active: false)
      mapping = [{ x => [x1, z1], y => [y1], z => [x1] }, { x => z1, y => y1, z => x1 }]

      submit(edit_form(enum_child))

      expect(response).to redirect_to("/custom_fields/#{enum_child.id}/edit")
      expect(stored(enum_child)).to eq(mapping)

      form = edit_form(enum_child)
      rendered = rendered_mapping(form)
      expect([rendered['value_dependencies'], rendered['default_value_dependencies']]).to eq(mapping)
      editor_payload(form, rendered['value_dependencies'], rendered['default_value_dependencies'])

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{enum_child.id}/edit")
      expect(stored(enum_child)).to eq(mapping)
    end
  end
end
