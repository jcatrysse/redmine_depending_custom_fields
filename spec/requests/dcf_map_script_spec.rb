# frozen_string_literal: true

require_relative '../rails_helper'

# WP-39 (R1, owner 2026-11-05): the mapping of a managed depending field is
# the JSON text of one <script type="application/json"> element right after
# its control (after core's own markup), and the control names it in
# data-dcf-map-ref; the data-dcf-map attribute is gone. The JSON is the text
# the attribute held (to_json of the encoded sanitized mapping) escaped for a
# script context, on every form that renders a managed field.
RSpec.describe 'Mapping as a JSON script element (WP-39)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:client) { RedmineDependingCustomFields::ClientData }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:project) { dcf_create_project }
  let(:tag) { "M#{SecureRandom.hex(3)}" }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  # Parent P1 P2 P3, child c1 c2 c3; P1 allows c1 and c2, P2 allows c3.
  def pair(type: IssueCustomField, multiple: false, style: nil, parent: nil)
    parent ||= dcf_list_field(values: %W[#{tag}P1 #{tag}P2 #{tag}P3], type: type, name: "#{tag}Parent#{type.name[0, 4]}")
    child = dcf_list_field(format: 'depending_list', values: %W[#{tag}c1 #{tag}c2 #{tag}c3], parent: parent,
                           type: type, multiple: multiple, name: "#{tag}Child#{SecureRandom.hex(2)}")
    child.update!(edit_tag_style: style) if style
    child = dcf_set_dependencies(child, value_dependencies: { "#{tag}P1" => %W[#{tag}c1 #{tag}c2],
                                                              "#{tag}P2" => %W[#{tag}c3] },
                                        default_value_dependencies: { "#{tag}P1" => "#{tag}c2" })
    [parent, child]
  end

  # The text the former data-dcf-map attribute held (Rails to_json of the
  # encoded mapping), escaped for a script context.
  def former_json(field)
    client.send(:encode, field, rules.mapping(field)).to_json
  end

  # Every managed control of +page+ names exactly one JSON script that
  # follows its markup, holds the former attribute JSON and carries nothing
  # else; no control carries data-dcf-map; the script keys occur once and
  # the script has no id (core derives label for= from the tag's only id).
  def expect_map_markup(page, fields, label)
    expect(page.css('[data-dcf-map]')).to be_empty, label
    controls = dcf_mapped(page)
    expect(controls.map { |control| control['data-dcf-field'].to_i }.sort).to eq(fields.map(&:id).sort), label
    expect(dcf_managed_count(page)).to eq(fields.size), label
    keys = page.css('script[data-dcf-map-id]').map { |node| node['data-dcf-map-id'] }
    controls.each do |control|
      field = CustomField.find(control['data-dcf-field'].to_i)
      script = dcf_map_script(control)
      expect(script.attribute_nodes.map(&:name)).to eq(%w[type data-dcf-map-id]), label
      expect(script.text).to eq(ERB::Util.json_escape(former_json(field))), label
      expect(JSON.parse(script.text)).to eq(rules.mapping(field)), label
      after = control.xpath('following-sibling::*').reject { |node| node.name == 'input' && node['type'] == 'hidden' }
      expect(after.first).to eq(script), label
      expect(control.css('script')).to be_empty, label
      expect(keys.count(script['data-dcf-map-id'])).to eq(1), label
    end
  end

  describe 'contexts' do
    it 'renders one script per managed field on the issue new, edit and copy forms and in bulk edit' do
      parent, child = pair
      issue = kit_issue(project, parent => "#{tag}P1", child => "#{tag}c1")
      as(dcf_admin)
      { 'edit' => "/issues/#{issue.id}/edit", 'new' => "/projects/#{project.identifier}/issues/new",
        'copy' => "/projects/#{project.identifier}/issues/#{issue.id}/copy" }.each do |label, path|
        get path
        expect(response).to have_http_status(200), label
        expect_map_markup(doc, [child], label)
        expect(dcf_mapped(doc).first['data-dcf-context']).to eq('form')
      end
      get '/issues/bulk_edit', params: { ids: [issue.id] }
      expect_map_markup(doc, [child], 'bulk edit')
      expect(dcf_mapped(doc).first['data-dcf-context']).to eq('bulk')
    end

    it 'renders the script after the radio or check box group and after the WP-19 blank sentinel' do
      parent, radio = pair(style: 'check_box')
      _, boxes = pair(style: 'check_box', multiple: true, parent: parent)
      issue = kit_issue(project, parent => "#{tag}P1", radio => "#{tag}c1", boxes => ["#{tag}c2"])
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"

      expect_map_markup(doc, [radio, boxes], 'check box styles')
      group = dcf_mapped(doc).find { |node| node['data-dcf-field'] == radio.id.to_s }
      expect(group.name).to eq('span')
      expect(group.previous_element['data-dcf-blank']).to eq('1')
      expect(group.css('input').map { |input| input['type'] }.uniq).to eq(%w[radio])
    end

    it 'renders one script per field on a multiple select, after core\'s hidden blank input' do
      parent, child = pair(multiple: true)
      issue = kit_issue(project, parent => "#{tag}P1", child => ["#{tag}c1"])
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"

      expect_map_markup(doc, [child], 'multiple')
      select = dcf_mapped(doc).first
      expect(select.next_element.name).to eq('input')
      expect(select.next_element.next_element).to eq(dcf_map_script(select))
    end

    it 'renders the script inside the wizard label, with ids that differ from the edit form on the issue page' do
      parent, child = pair
      issue = kit_issue(project, parent => "#{tag}P1", child => "#{tag}c1")
      as(dcf_admin)
      get "/issues/#{issue.id}"
      expect(response).to have_http_status(200)
      show_keys = doc.css('script[data-dcf-map-id]').map { |node| node['data-dcf-map-id'] }
      form_script = dcf_map_script(dcf_mapped(doc).first)
      post '/issues/context_menu', params: { ids: [issue.id] }
      form = dcf_wizard_form(doc, parent)

      expect_map_markup(form, [child], 'wizard')
      wizard_script = dcf_map_script(dcf_mapped(form).first)
      expect(wizard_script.ancestors('label.cf-wizard-label').size).to eq(1)
      expect(wizard_script['data-dcf-map-id']).not_to eq(form_script['data-dcf-map-id'])
      expect(show_keys).to eq([form_script['data-dcf-map-id']])
      expect(show_keys).not_to include(wizard_script['data-dcf-map-id'])
      expect(form.css('script').size).to eq(1)
    end

    it 'renders the script on time entry, user, version and project forms' do
      as(dcf_admin)
      t_parent, t_child = pair(type: TimeEntryCustomField)
      activity = TimeEntryActivity.create!(name: "Dev-#{SecureRandom.hex(3)}", active: true)
      entry = TimeEntry.new(project: project, user: dcf_admin, author: dcf_admin, spent_on: Date.new(2026, 1, 1),
                            hours: 1, activity: activity)
      entry.custom_field_values = { t_parent.id.to_s => "#{tag}P1", t_child.id.to_s => "#{tag}c1" }
      entry.save!(validate: false)
      { 'time entry new' => "/projects/#{project.identifier}/time_entries/new",
        'time entry edit' => "/time_entries/#{entry.id}/edit" }.each do |label, path|
        get path
        expect(response).to have_http_status(200), label
        expect_map_markup(doc, [t_child], label)
      end
      get '/time_entries/bulk_edit', params: { ids: [entry.id] }
      expect_map_markup(doc, [t_child], 'time entry bulk edit')

      _, u_child = pair(type: UserCustomField)
      get "/users/#{dcf_admin.id}/edit"
      expect_map_markup(doc, [u_child], 'admin user form')
      get '/my/account'
      expect_map_markup(doc, [u_child], 'my account')

      _, v_child = pair(type: VersionCustomField)
      version = Version.create!(project: project, name: "V-#{SecureRandom.hex(3)}")
      get "/versions/#{version.id}/edit"
      expect_map_markup(doc, [v_child], 'version form')

      _, p_child = pair(type: ProjectCustomField)
      get "/projects/#{project.identifier}/settings"
      expect_map_markup(doc, [p_child], 'project settings')
    end

    it 'keeps every other script of the form out of the field markup (no executable script added)' do
      parent, child = pair
      issue = kit_issue(project, parent => "#{tag}P1", child => "#{tag}c1")
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"
      form = doc.at_css('form#issue-form')
      plugin_scripts = form.css('script').select { |script| script['data-dcf-map-id'].to_s.start_with?('dcf-map-') }

      expect(plugin_scripts.map { |script| script['type'] }).to eq(%w[application/json])
      expect(form.css('[data-dcf-map-ref]').size).to eq(1)
      expect(plugin_scripts.first.text).not_to match(/[<>&  ]/)
    end
  end

  describe 'escaping' do
    let(:values) do
      ['</script><script>x</script>', '<!--', '<script', '&amp;', 'q"q', "s'q", 'b\\s', "l s", "p s",
       'Ünï€ ñ', '-->']
    end
    let(:key) { "</script><!--&\"'  " }

    it 'round-trips values and keys that could end or open a script data block' do
      parent = dcf_list_field(values: ["#{tag}P1", key], name: "#{tag}Parent")
      child = dcf_list_field(format: 'depending_list', values: values, parent: parent, name: "#{tag}Child")
      child = dcf_set_dependencies(child, value_dependencies: { key => values, "#{tag}P1" => values.first(2) })
      issue = kit_issue(project, parent => key, child => '<!--')
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"
      expect(response).to have_http_status(200)
      body = response.body
      control = dcf_mapped(doc).first
      ref = control['data-dcf-map-ref']
      raw = body[%r{<script type="application/json" data-dcf-map-id="#{Regexp.escape(ref)}">(.*?)</script>}m, 1]

      expect(raw).not_to be_nil
      expect(raw).not_to match(/[<>&  ]/)
      expect(body.scan(/<script\b/i).size).to eq(body.scan(%r{</script}i).size)
      expect(JSON.parse(raw)).to eq(key => values, "#{tag}P1" => values.first(2))
      expect(dcf_map_of(control)).to eq(rules.mapping(child))
      if defined?(Nokogiri::HTML5)
        html5 = Nokogiri::HTML5(body)
        script = html5.css('script').find { |node| node['data-dcf-map-id'] == ref }
        expect(JSON.parse(script.text)).to eq(rules.mapping(child))
      end
      expect(control.css('option').map { |option| option['value'] }).to include(*values)
    end
  end

  # contract-12: the mapping of a field shaped like the WP-37 S2 field (500
  # parent values, 25,000 child values of 8 characters) costs at least 40
  # percent fewer bytes as a script plus reference than as the former
  # attribute (the same JSON HTML-escaped into data-dcf-map="...").
  describe 'size' do
    it 'writes the S2-shaped mapping at least 40 percent smaller than the attribute form', :large do
      assemblies = (1..500).map { |i| format('A%03d', i) }
      mapping = assemblies.to_h { |a| [a, (1..50).map { |k| format('%s-P%02d', a, k) }] }
      storage = RedmineDependingCustomFields::StorageLimits
      needed = DcfLargeList.yaml_list_bytes(mapping.values.flatten)
      limit = %w[possible_values format_store].filter_map { |c| storage.column_limit(c) }.min
      skip "UD-38: the field needs #{needed} bytes, the column limit is #{limit} bytes" if limit && limit < needed
      parent = dcf_list_field(values: assemblies)
      child = dcf_list_field(format: 'depending_list', values: mapping.values.flatten, parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: mapping)
      issue = kit_issue(project, parent => 'A001', child => [])
      as(dcf_admin)
      get "/issues/#{issue.id}/edit"
      expect(response).to have_http_status(200)
      control = dcf_mapped(doc).first
      ref = control['data-dcf-map-ref']
      script = response.body[%r{<script type="application/json" data-dcf-map-id="#{Regexp.escape(ref)}">.*?</script>}m]
      new_bytes = script.bytesize + " data-dcf-map-ref=\"#{ref}\"".bytesize
      old_bytes = " data-dcf-map=\"#{ERB::Util.html_escape(former_json(child))}\"".bytesize

      expect(dcf_map_of(control).values.flatten.size).to eq(25_000)
      expect(new_bytes).to be <= (0.6 * old_bytes)
      puts "DCF SIZE S2-shaped map: script #{new_bytes} bytes, attribute form #{old_bytes} bytes"
    end
  end
end
