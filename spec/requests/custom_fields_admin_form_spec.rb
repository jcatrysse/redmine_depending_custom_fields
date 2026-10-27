# frozen_string_literal: true

require_relative '../rails_helper'

# WP-10 (PC-10, PC-11, PC-12, UD-08, UD-35, UD-36): the parent select of the
# admin custom field form offers DependencyRules.parent_candidates (same type
# and family, minus the field itself and its descendants, keeping the current
# parent), the form warns about a stored cycle the field is a member of, and
# a parent change that would close a cycle is refused (form error, 422 for
# the drag-and-drop reorder).
RSpec.describe 'Admin custom field form parent select and cycle warning', type: :request do
  include DcfStoredCycle

  fixtures :users

  let(:admin) { dcf_admin }
  let(:circular_message) do
    'Depends on refers to this field or to one of its dependent fields, which would create a circular dependency'
  end

  before { allow(User).to receive(:current).and_return(admin) }

  def edit_page(field)
    get "/custom_fields/#{field.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('translation missing')
    Nokogiri::HTML(response.body)
  end

  def parent_select(page)
    page.at_css('select#custom_field_parent_custom_field_id')
  end

  # Offered parent ids, without the blank option, in page order.
  def offered(page)
    parent_select(page).css('option').map { |o| o['value'] }.reject(&:empty?).map(&:to_i)
  end

  def selected(page)
    parent_select(page).css('option[selected]').map { |o| o['value'] }
  end

  def cycle_warnings(page, locale = :en)
    lead = I18n.t(:warning_dcf_parent_cycle, fields: '|', locale: locale).split('|').first
    page.css('p.icon.icon-warning').select { |p| p.text.include?(lead) }
  end

  def warning_texts(page, locale = :en)
    cycle_warnings(page, locale).map { |p| p.text.strip }
  end

  def cycle_text(names, locale = :en)
    I18n.t(:warning_dcf_parent_cycle, fields: names.join(', '), locale: locale)
  end

  # Changed by WP-25: the editor partial always renders the warning
  # paragraph and hides it with dcf-hidden; shown means without that class.
  def required_warnings(page)
    page.css('p[data-dcf-editor-required-warning]').reject { |p| p['class'].to_s.split.include?('dcf-hidden') }
        .select { |p| p.text.include?(I18n.t(:warning_required_child_no_options)) }
  end

  def make_required(field)
    CustomField.where(id: field.id).update_all(is_required: true)
    CustomField.find(field.id)
  end

  def same_family_ids(field, without)
    formats = RedmineDependingCustomFields::DependencyRules.parent_formats_for(field)
    CustomField.where(type: field.type, field_format: formats).sorted.order(:id).pluck(:id) - without.map(&:id)
  end

  # The [name, value] entries a browser submits for +form+ as rendered.
  def browser_entries(form)
    form.css('input, select, textarea').each_with_object([]) do |control, entries|
      next if control['name'].to_s.empty? || control.key?('disabled')

      entries.concat(control_entries(control))
    end
  end

  def control_entries(control)
    name = control['name']
    case control.name
    when 'select'
      options = control.css('option').reject { |o| o.key?('disabled') }
      chosen = options.select { |o| o.key?('selected') }
      chosen = options.first(1) if chosen.empty? && !control.key?('multiple')
      chosen.map { |o| [name, o['value'] || o.text] }
    when 'textarea' then [[name, control.text.sub(/\A\r?\n/, '')]]
    else input_entries(control)
    end
  end

  def input_entries(input)
    type = (input['type'] || 'text').downcase
    return [] if %w[submit button image file reset].include?(type)
    return [] if %w[checkbox radio].include?(type) && !input.key?('checked')

    [[input['name'], input['value'] || (%w[checkbox radio].include?(type) ? 'on' : '')]]
  end

  def submit_as_rendered(page)
    form = page.at_css('form#custom_field_form')
    post form['action'], params: URI.encode_www_form(browser_entries(form)),
                         headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
  end

  describe 'parent select' do
    it 'offers the same type and family by position, without the field itself and its descendants' do
      root = dcf_list_field(name: 'Root')
      other_root = dcf_list_field(name: 'Other root')
      a = dcf_list_field(format: 'depending_list', name: 'A', parent: root)
      b = dcf_list_field(format: 'depending_list', name: 'B', parent: a)
      c = dcf_list_field(format: 'depending_list', name: 'C', parent: b)
      dcf_enum_field(name: 'Other family')
      dcf_list_field(name: 'Other type', type: ProjectCustomField)

      page = edit_page(b)

      expect(offered(page)).to eq(same_family_ids(b, [b, c]))
      expect(offered(page)).to include(root.id, other_root.id, a.id)
      expect(selected(page)).to eq([a.id.to_s])
      expect(parent_select(page).at_css('option')['value']).to eq('')
      expect(cycle_warnings(page)).to eq([])
    end

    [:list, :enumeration].each do |kind|
      it "keeps the stored partner of a #{kind} cycle member selected and warns, names from the field itself" do
        world = dcf_stored_cycles(kind)

        page = edit_page(world.x)
        expect(offered(page)).to include(world.y.id)
        expect(offered(page)).not_to include(world.x.id, world.child.id)
        expect(selected(page)).to eq([world.y.id.to_s])
        expect(warning_texts(page)).to eq([cycle_text([world.x.name, world.y.name])])

        page = edit_page(world.y)
        expect(warning_texts(page)).to eq([cycle_text([world.y.name, world.x.name])])
        page = edit_page(world.b)
        expect(warning_texts(page))
          .to eq([cycle_text([world.b.name, world.c.name, world.a.name])])
      end
    end

    it 'never offers a stored self-parent, warns with its own name, and the form as rendered clears it (UD-36)' do
      world = dcf_stored_cycles(:list)

      page = edit_page(world.self_parent)
      expect(offered(page)).not_to include(world.self_parent.id)
      expect(selected(page)).to eq([])
      expect(warning_texts(page)).to eq([cycle_text([world.self_parent.name])])

      submit_as_rendered(page)
      expect(response).to have_http_status(302)
      stored = CustomField.find(world.self_parent.id)
      expect(stored.parent_custom_field_id).to eq('')
      expect(stored.value_dependencies).to eq('s1' => %w[s1])
    end

    it 'shows no warning on a field below a cycle and keeps its parent selected' do
      world = dcf_stored_cycles(:list)

      page = edit_page(world.child)
      expect(selected(page)).to eq([world.x.id.to_s])
      expect(cycle_warnings(page)).to eq([])
      expect(response.body).not_to include(cycle_text([world.x.name, world.y.name]))
    end

    it 'does not offer a dangling parent, and the form as rendered stores a blank parent (QA-23)' do
      root = dcf_list_field(values: %w[A])
      field = dcf_list_field(format: 'depending_list', values: %w[a1], parent: root)
      dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1] })
      dangling = CustomField.maximum(:id).to_i + 1_000
      dcf_store_parent(field, dangling)

      page = edit_page(field)
      expect(offered(page)).not_to include(dangling)
      expect(selected(page)).to eq([])

      submit_as_rendered(page)
      expect(response).to have_http_status(302)
      stored = CustomField.find(field.id)
      expect(stored.parent_custom_field_id).to eq('')
      expect(stored.value_dependencies).to eq('A' => %w[a1])
    end

    it 'offers every same-type, same-family field on the new form, without a warning or a topology load' do
      roots = [dcf_list_field, dcf_list_field]
      dcf_list_field(format: 'depending_list', parent: roots.first)
      dcf_stored_cycles(:list)
      allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original

      get '/custom_fields/new', params: { type: 'IssueCustomField', custom_field: { field_format: 'depending_list' } }

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(offered(page)).to eq(same_family_ids(IssueCustomField.new(field_format: 'depending_list'), []))
      expect(cycle_warnings(page)).to eq([])
      expect(RedmineDependingCustomFields::FieldIndex).not_to have_received(:load)
    end

    it 'keeps the parent select on the new enumeration form' do
      dcf_enum_field(name: 'Enum root')
      get '/custom_fields/new', params: { type: 'IssueCustomField', custom_field: { field_format: 'depending_enumeration' } }

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(offered(page)).to eq(same_family_ids(IssueCustomField.new(field_format: 'depending_enumeration'), []))
    end

    it 'loads the topology once per render, with the same number of queries for 2 and 12 other depending fields' do
      root = dcf_list_field
      field = dcf_list_field(format: 'depending_list', parent: root)
      allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original
      edit_page(field)
      expect(RedmineDependingCustomFields::FieldIndex).to have_received(:load).once

      2.times { dcf_list_field(format: 'depending_list', parent: root) }
      edit_page(field)
      few = dcf_count_queries { edit_page(field) }
      10.times { dcf_list_field(format: 'depending_list', parent: root) }
      edit_page(field)
      many = dcf_count_queries { edit_page(field) }
      expect(many).to eq(few)
    end
  end

  # The required warning says that the required check is not enforced
  # while the parent value allows nothing. That is DependencyRules.no_options?,
  # which reads only the effective parent since WP-18 (the 0.0.16 parent read
  # for fields without one went with the legacy script), so the warning is
  # gated on the effective parent read from the partial's own FieldIndex.load.
  describe 'required warning (warning_required_child_no_options)' do
    [:list, :enumeration].each do |kind|
      it "is shown for a required #{kind} field whose effective parent has an unmapped value" do
        root = kind == :list ? dcf_list_field(values: %w[r1 r2]) : dcf_enum_field(names: %w[r1 r2])
        field = dcf_cycle_field(kind, %w[a1 a2], parent: root)
        field = make_required(dcf_cycle_links(field, root, 'r1' => %w[a1]))

        page = edit_page(field)
        expect(required_warnings(page).size).to eq(1)
        expect(cycle_warnings(page)).to eq([])
      end

      # A new record has no index (dcf_index nil); its effective parent comes
      # from DependencyRules.effective_parent_id, so the new form and a failed
      # create re-render show the warning for an acyclic parent.
      it "is shown on the new #{kind} form and its failed create re-render for a required field with a parent" do
        root = kind == :list ? dcf_list_field(values: %w[r1 r2]) : dcf_enum_field(names: %w[r1 r2])
        format = kind == :list ? 'depending_list' : 'depending_enumeration'
        attributes = { field_format: format, is_required: '1', parent_custom_field_id: root.id.to_s }

        get '/custom_fields/new', params: { type: 'IssueCustomField', custom_field: attributes }
        expect(response).to have_http_status(:ok)
        expect(required_warnings(Nokogiri::HTML(response.body)).size).to eq(1)

        expect do
          post '/custom_fields', params: { type: 'IssueCustomField', custom_field: attributes.merge(name: '') }
        end.not_to change(CustomField, :count)
        expect(response).to have_http_status(:ok)
        expect(required_warnings(Nokogiri::HTML(response.body)).size).to eq(1)
      end

      # Review round 2 (semantics-r2-1): a new field may pick a parent in or
      # below a stored cycle (parent_candidates offers it, parent_errors skips
      # new records); it has no effective parent, so core's required check
      # applies after the create and the form does not claim otherwise.
      it "is not shown on the new #{kind} form and its failed create re-render " \
         'for a parent in or below a stored cycle' do
        world = dcf_stored_cycles(kind)
        format = kind == :list ? 'depending_list' : 'depending_enumeration'
        [world.x, world.self_parent, world.child].each do |parent|
          attributes = { field_format: format, is_required: '1', parent_custom_field_id: parent.id.to_s }

          get '/custom_fields/new', params: { type: 'IssueCustomField', custom_field: attributes }
          expect(response).to have_http_status(:ok)
          page = Nokogiri::HTML(response.body)
          expect(selected(page)).to eq([parent.id.to_s]), parent.name
          expect(required_warnings(page)).to eq([]), parent.name

          expect do
            post '/custom_fields', params: { type: 'IssueCustomField', custom_field: attributes.merge(name: '') }
          end.not_to change(CustomField, :count)
          expect(response).to have_http_status(:ok)
          page = Nokogiri::HTML(response.body)
          expect(selected(page)).to eq([parent.id.to_s]), parent.name
          expect(required_warnings(page)).to eq([]), parent.name
        end
      end

      # Flipped back by WP-18 (WP-10 open input): "is not shown for a
      # required #{kind} stored-cycle member, self-parent or field below a
      # cycle", as compat-ui-r1-1 had it; semantics-r2-1 showed it while the
      # required bypass kept the 0.0.16 parent read for the legacy script.
      it "is not shown for a required #{kind} stored-cycle member, self-parent or field below a cycle" do
        world = dcf_stored_cycles(kind)
        x = make_required(world.x)
        self_parent = make_required(world.self_parent)
        child = make_required(world.child)
        below_self_parent = make_required(world.below_self_parent)

        page = edit_page(x)
        expect(required_warnings(page)).to eq([])
        expect(warning_texts(page)).to eq([cycle_text([x.name, world.y.name])])

        page = edit_page(self_parent)
        expect(required_warnings(page)).to eq([])
        expect(warning_texts(page)).to eq([cycle_text([self_parent.name])])

        [child, below_self_parent].each do |below|
          page = edit_page(below)
          expect(required_warnings(page)).to eq([]), below.name
          expect(cycle_warnings(page)).to eq([]), below.name
        end
      end
    end

    # contracts-r2-1, compat-ui-r2-1: the edit page of a required field costs
    # the same queries whatever the depth of its parent's stored chain (one
    # FieldIndex.load per render). WP-18: the warning reads the effective
    # parent from that index, which knows every depending field, so the
    # chain walk adds no query.
    it 'renders a required field with the same number of queries for a parent chain of one and two depending levels' do
      root = dcf_list_field(values: %w[r1 r2])
      upper = dcf_list_field(format: 'depending_list', values: %w[u1 u2], parent: root)
      middle = dcf_list_field(format: 'depending_list', values: %w[m1 m2], parent: root)
      field = dcf_list_field(format: 'depending_list', values: %w[a1 a2], parent: middle)
      field = make_required(dcf_cycle_links(field, middle, 'm1' => %w[a1]))
      allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original

      edit_page(field)
      shallow = dcf_count_queries { expect(required_warnings(edit_page(field)).size).to eq(1) }
      dcf_store_parent(middle, upper)
      edit_page(field)
      deep = dcf_count_queries { expect(required_warnings(edit_page(field)).size).to eq(1) }

      expect(deep).to eq(shallow)
      expect(RedmineDependingCustomFields::FieldIndex).to have_received(:load).exactly(4).times
    end
  end

  describe 'cycle warning markup (UX-10)' do
    it 'renders the sprite icon on Redmine 6 and later and the classic icon class on 5.1, with escaped names' do
      world = dcf_stored_cycles(:list)
      CustomField.where(id: world.x.id).update_all(name: '<b>X&</b>')

      page = edit_page(world.y)
      warning = cycle_warnings(page).first
      expect(warning).not_to be_nil
      expect(warning.text.strip).to eq(cycle_text([world.y.name, '<b>X&</b>']))
      expect(warning.css('b')).to be_empty
      if Redmine::VERSION::MAJOR >= 6
        expect(warning.css('svg')).not_to be_empty
        expect(warning.at_css('span.icon-label').text).to eq(cycle_text([world.y.name, '<b>X&</b>']))
      else
        expect(warning.css('svg')).to be_empty
      end
    end

    it 'renders the warning in German without a missing translation' do
      world = dcf_stored_cycles(:enumeration)
      admin.language = 'de'

      page = edit_page(world.x)
      expect(warning_texts(page, :de)).to eq([cycle_text([world.x.name, world.y.name], :de)])
      expect(response.body).not_to include('translation_missing')
    end
  end

  describe 'saving a parent that would close a cycle' do
    it 're-renders the form with the full message for the field itself and stores nothing' do
      root = dcf_list_field
      field = dcf_list_field(format: 'depending_list', parent: root)

      put "/custom_fields/#{field.id}", params: { custom_field: { parent_custom_field_id: field.id.to_s } }

      expect(response).to have_http_status(200)
      expect(Nokogiri::HTML(response.body).css('#errorExplanation').text).to include(circular_message)
      expect(CustomField.find(field.id).parent_custom_field_id).to eq(root.id)
    end

    it 're-renders the form for a change that closes a <-> b' do
      a = dcf_list_field(format: 'depending_list')
      b = dcf_list_field(format: 'depending_list', parent: a)

      put "/custom_fields/#{a.id}", params: { custom_field: { parent_custom_field_id: b.id.to_s } }

      expect(response).to have_http_status(200)
      expect(Nokogiri::HTML(response.body).css('#errorExplanation').text).to include(circular_message)
      expect(CustomField.find(a.id).parent_custom_field_id).to be_nil
    end

    # tests-r1-3: after a refused change the select keeps the in-memory
    # pointer as the current parent (parent_candidates, WP-05 contract), so
    # it offers the rejected value unless that is the field itself; a stored
    # partner that is a descendant is then not offered. The warning reads the
    # stored topology.
    it 're-renders a refused stored-cycle change with the rejected value selected and the stored partner not offered' do
      world = dcf_stored_cycles(:list)

      put "/custom_fields/#{world.x.id}", params: { custom_field: { parent_custom_field_id: world.child.id.to_s } }

      expect(response).to have_http_status(200)
      page = Nokogiri::HTML(response.body)
      expect(page.css('#errorExplanation').text).to include(circular_message)
      expect(selected(page)).to eq([world.child.id.to_s])
      expect(offered(page)).to include(world.child.id)
      expect(offered(page)).not_to include(world.y.id, world.x.id)
      expect(warning_texts(page)).to eq([cycle_text([world.x.name, world.y.name])])
      expect(CustomField.find(world.x.id).parent_custom_field_id).to eq(world.y.id)
    end

    it 're-renders a refused self-parent with no option selected and the field itself not offered' do
      root = dcf_list_field
      field = dcf_list_field(format: 'depending_list', parent: root)

      put "/custom_fields/#{field.id}", params: { custom_field: { parent_custom_field_id: field.id.to_s } }

      expect(response).to have_http_status(200)
      page = Nokogiri::HTML(response.body)
      expect(page.css('#errorExplanation').text).to include(circular_message)
      expect(selected(page)).to eq([])
      expect(offered(page)).to include(root.id)
      expect(offered(page)).not_to include(field.id)
      expect(cycle_warnings(page)).to eq([])
    end

    it 'keeps the drag-and-drop reorder of a stored-cycle member and answers 422 only for a real parent change' do
      world = dcf_stored_cycles(:list)
      position = CustomField.find(world.x.id).position

      put "/custom_fields/#{world.x.id}.js", params: { custom_field: { position: position + 3 } }, xhr: true
      expect(response).to have_http_status(200)
      expect(CustomField.find(world.x.id).position).not_to eq(position)

      put "/custom_fields/#{world.x.id}.js", params: { custom_field: { parent_custom_field_id: world.child.id.to_s } },
                                              xhr: true
      expect(response).to have_http_status(422)
      expect(CustomField.find(world.x.id).parent_custom_field_id).to eq(world.y.id)
    end
  end
end
