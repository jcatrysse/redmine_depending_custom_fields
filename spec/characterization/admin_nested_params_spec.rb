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

  def matrix_boxes(form, parent_value)
    form.css('table.dependencies-matrix input')
        .select { |box| box['name'] == "custom_field[value_dependencies][#{parent_value}][]" }
  end

  def set_ticks(form, parent_value, ticked)
    matrix_boxes(form, parent_value).each do |box|
      if ticked
        box['checked'] = 'checked'
      else
        box.remove_attribute('checked')
      end
    end
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

  def rack3?
    Gem::Version.new(Rack::RELEASE) >= Gem::Version.new('3')
  end

  describe 'what the matrix posts' do
    it 'renders each cell as a bare checkbox named after the raw parent value, with no hidden companion' do
      form = edit_form(child)

      controls = form.css('[name^="custom_field[value_dependencies]"]')
      expect(controls.map { |c| [c.name, c['type'], c['name'], c['value'], c.key?('checked')] }).to eq(
        [
          ['input', 'checkbox', 'custom_field[value_dependencies][A][]', 'a1', true],
          ['input', 'checkbox', 'custom_field[value_dependencies][A][]', 'b1', false],
          ['input', 'checkbox', 'custom_field[value_dependencies][B][]', 'a1', false],
          ['input', 'checkbox', 'custom_field[value_dependencies][B][]', 'b1', true]
        ]
      )
    end
  end

  describe 'saving the form' do
    it 'stores a newly ticked cell and a newly chosen per-parent default' do
      form = edit_form(child)
      matrix_boxes(form, 'A').detect { |box| box['value'] == 'b1' }['checked'] = 'checked'
      default_b = form.at_css('select[name="custom_field[default_value_dependencies][B]"]')
      default_b.at_css('option[value="b1"]')['selected'] = 'selected'

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(stored(child)).to eq([{ 'A' => %w[a1 b1], 'B' => %w[b1] }, { 'A' => 'a1', 'B' => 'b1' }])
    end

    it 'ignores a matrix with every cell unticked: no value_dependencies entry is posted and the mapping is kept' do
      form = edit_form(child)
      set_ticks(form, 'A', false)
      set_ticks(form, 'B', false)
      expect(browser_entries(form).map(&:first).grep(/\Acustom_field\[value_dependencies\]/)).to be_empty

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(stored(child)).to eq([{ 'A' => %w[a1], 'B' => %w[b1] }, { 'A' => 'a1' }])
    end

    it 'drops a fully unticked parent row but keeps its default while another row stays ticked' do
      form = edit_form(child)
      set_ticks(form, 'A', false)

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(stored(child)).to eq([{ 'B' => %w[b1] }, { 'A' => 'a1' }])
    end

    # Rack 3 (and Rails 8 ParamBuilder) keep "D][]" as a key and the last
    # checkbox wins; Rack 2.2 (Redmine 5.1) nests a "D" array. Either way the
    # Sanitizer stringifies the nested pair under the key "C".
    it 'stores a corrupted entry under the text before "]" for a parent value containing "]"' do
      bracket_parent = dcf_list_field(name: 'Bracket', values: ['A', 'C]D'])
      bracket_child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: bracket_parent)
      dcf_set_dependencies(bracket_child, value_dependencies: { 'A' => %w[a1] })
      form = edit_form(bracket_child)
      set_ticks(form, 'C]D', true)

      submit(form)

      expect(response).to redirect_to("/custom_fields/#{bracket_child.id}/edit")
      corrupted = rack3? ? ['["D][]", "b1"]'] : ['["D", ["a1", "b1"]]']
      expect(stored(bracket_child)).to eq([{ 'A' => %w[a1], 'C' => corrupted }, {}])
    end

    # The body cannot be parsed (A is both an array and a hash), so
    # Rack::MethodOverride drops _method=put and the POST matches no route.
    it 'turns the save into an unrouted POST (404) when a "]" value starts with another ticked parent value' do
      bracket_parent = dcf_list_field(name: 'Bracket', values: ['A', 'A]B'])
      bracket_child = dcf_list_field(format: 'depending_list', name: 'Before', values: %w[a1 b1],
                                     parent: bracket_parent)
      dcf_set_dependencies(bracket_child, value_dependencies: { 'A' => %w[a1] })
      form = edit_form(bracket_child)
      set_ticks(form, 'A]B', true)
      form.at_css('input[name="custom_field[name]"]')['value'] = 'After'

      submit(form)

      expect(response).to have_http_status(:not_found)
      expect(bracket_child.reload.name).to eq('Before')
      expect(stored(bracket_child)).to eq([{ 'A' => %w[a1] }, {}])
    end

    it 'drops links to and from inactive enumerations and a default naming an inactive child on an unchanged save' do
      enum_parent = dcf_enum_field(name: 'EnumParent', names: %w[X Y Z])
      enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1 z1], parent: enum_parent)
      x, y, z = enum_parent.enumerations.order(:position).map { |e| e.id.to_s }
      x1, y1, z1 = enum_child.enumerations.order(:position).map { |e| e.id.to_s }
      dcf_set_dependencies(enum_child, value_dependencies: { x => [x1, z1], y => [y1], z => [x1] },
                                       default_value_dependencies: { x => z1, y => y1, z => x1 })
      CustomFieldEnumeration.where(id: [z, z1]).update_all(active: false)

      submit(edit_form(enum_child))

      expect(response).to redirect_to("/custom_fields/#{enum_child.id}/edit")
      expect(stored(enum_child)).to eq([{ x => [x1], y => [y1] }, { y => y1 }])
    end
  end
end
