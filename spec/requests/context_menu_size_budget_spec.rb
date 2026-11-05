# frozen_string_literal: true

require_relative '../rails_helper'

# WP-18 (UD-13, server design 7.7, quality G6), changed by WP-36 (UD-13
# changed by the owner on 2026-11-02): the budget moves from the menu to the
# fetched wizard body. With S1 data (a root of 27 values, one depending child
# of 5,570 values with the partition mapping and defaults) the menu
# (/issues/context_menu) holds the entry only: the plugin part is at most
# 1 KiB and the menu is no larger than the same menu of a 1-value child plus
# that bound. The body (GET /depending_custom_fields/wizard) is at most 512
# KiB (524,288 bytes) and at most the rendered wizard selects
# (data-dcf-defaults included) plus their JSON mapping scripts plus 16 KiB.
# Bytes, not characters: the tricky values are multibyte. Was: the whole
# menu within 512 KiB with the inline template. Changed by WP-39 (R1): the
# mapping is a JSON script next to its select (was data-dcf-map inside the
# select), so the bound adds the scripts.
RSpec.describe 'Context menu size budget (WP-18, WP-36)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:entry_bound) { 1024 }

  def s1_world
    parent_values = DcfLargeList.names(27, prefix: 'P')
    child_values = DcfLargeList.names(5570, tricky_every: 97)
    needed = DcfLargeList.yaml_list_bytes(child_values)
    limit = %w[possible_values format_store].filter_map do |column|
      RedmineDependingCustomFields::StorageLimits.column_limit(column)
    end.min
    skip "UD-38: S1 needs #{needed} bytes, the column limit is #{limit} bytes" if limit && limit < needed

    parent = dcf_list_field(values: parent_values, name: 'Budget root')
    child = dcf_list_field(format: 'depending_list', values: child_values, parent: parent, name: 'Budget child')
    mapping = DcfLargeList.partition(parent_values, child_values)
    field = CustomField.find(child.id)
    field.value_dependencies = mapping
    field.default_value_dependencies = DcfLargeList.first_child_defaults(mapping)
    field.save!
    [parent, CustomField.find(child.id), parent_values.first]
  end

  # An issue of its own tracker, so the two chains never share a menu.
  def issue_with(values)
    tracker = dcf_tracker
    project.trackers << tracker unless project.reload.trackers.include?(tracker)
    values.each_key { |field| tracker.custom_fields << field }
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: tracker.default_status, priority: IssuePriority.first || IssuePriority.create!(name: 'Normal'))
    issue.custom_field_values = values.transform_keys(&:id)
    issue.save!
    issue
  end

  # The plugin part of a menu: from the first wizard entry to the end of the
  # last one.
  def plugin_part(body)
    start = body.index('<li class="folder cf-parent"')
    finish = body.rindex('</li>')
    expect([start, finish]).to all(be_an(Integer))
    body[start...(finish + '</li>'.size)]
  end

  it 'keeps the S1 menu entry small and the fetched wizard within 512 KiB and its selects plus 16 KiB', :large do
    parent, child, first = s1_world
    issue = issue_with(parent => first, child => '')
    small_root = dcf_list_field(values: %w[A], name: 'Budget small root')
    small_child = dcf_list_field(format: 'depending_list', values: %w[a], parent: small_root, name: 'Budget small child')
    small_issue = issue_with(small_root => 'A', small_child => '')
    allow(User).to receive(:current).and_return(dcf_admin)
    allow(Rails.logger).to receive(:warn).and_call_original

    post '/issues/context_menu', params: { ids: [small_issue.id] }
    small_menu = response.body
    post '/issues/context_menu', params: { ids: [issue.id] }
    expect(response).to have_http_status(200)
    menu_body = response.body
    menu = Nokogiri::HTML(menu_body)
    entry = plugin_part(menu_body)
    expect(menu.css('li.folder.cf-parent').map { |li| li['data-parent-id'] }).to eq([parent.id.to_s])
    expect(menu.css('template, form, select, script')).to be_empty
    expect(menu.at_css("li.folder.cf_#{child.id}")).to be_nil
    expect(entry.bytesize).to be <= entry_bound
    expect(plugin_part(small_menu).bytesize).to be <= entry_bound
    expect(menu_body.bytesize).to be <= small_menu.bytesize + entry_bound

    form = dcf_wizard_form(menu, parent)
    body = response.body
    expect(response).to have_http_status(200)
    expect(Rails.logger).not_to have_received(:warn).with(/context menu wizard failed/)
    selects = body.scan(%r{<select\b.*?</select>}m)
    scripts = body.scan(%r{<script type="application/json" data-dcf-map-id="[^"]*">.*?</script>}m)
    child_select = form.at_css("select[name='issue[custom_field_values][#{child.id}]']")

    expect(selects.size).to eq(2)
    expect(child_select.css('option').count { |o| !['', '__none__'].include?(o['value']) }).to eq(5570)
    expect(child_select['data-dcf-map']).to be_nil
    expect(child_select['data-dcf-map-ref']).to be_present
    expect(dcf_map_of(child_select).values.flatten.size).to eq(5570)
    expect(child_select['data-dcf-defaults']).to be_present
    expect(scripts.size).to eq(1)
    expect(form.css('script').size).to eq(1)
    expect(body.bytesize).to be <= 512 * 1024
    expect(body.bytesize).to be <= selects.sum(&:bytesize) + scripts.sum(&:bytesize) + (16 * 1024)
    RSpec.configuration.reporter.message(
      format('DCF BUDGET context menu S1: %<menu>d bytes, entry %<entry>d bytes; wizard body %<body>d bytes, ' \
             'selects %<selects>d bytes, scripts %<scripts>d bytes',
             menu: menu_body.bytesize, entry: entry.bytesize, body: body.bytesize, selects: selects.sum(&:bytesize),
             scripts: scripts.sum(&:bytesize))
    )
  end
end
