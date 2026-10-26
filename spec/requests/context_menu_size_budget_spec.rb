# frozen_string_literal: true

require_relative '../rails_helper'

# WP-18 (UD-13, server design 7.7, quality G6): the wizard template stays
# inline in the context menu. With S1 data (a root of 27 values, one
# depending child of 5,570 values with the partition mapping and defaults)
# the whole /issues/context_menu response is at most 512 KiB (524,288
# bytes), and the part the plugin adds (the wizard entry and its template)
# is at most the rendered wizard selects (data-dcf-map and data-dcf-defaults
# included) plus 16 KiB. Bytes, not characters: the tricky values are
# multibyte.
RSpec.describe 'Context menu size budget (WP-18)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }

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

  it 'keeps the S1 context menu within 512 KiB and the wizard within its selects plus 16 KiB', :large do
    parent, child, first = s1_world
    issue = dcf_real_issue(project.reload, parent => first, child => '')
    allow(User).to receive(:current).and_return(dcf_admin)
    allow(Rails.logger).to receive(:warn).and_call_original

    post '/issues/context_menu', params: { ids: [issue.id] }
    expect(response).to have_http_status(200)
    body = response.body
    expect(Rails.logger).not_to have_received(:warn).with(/context menu wizard failed/)

    start = body.index('<li class="folder cf-parent"')
    finish = body.index('</template>', start.to_i)
    expect([start, finish]).to all(be_an(Integer))
    plugin_part = body[start...(finish + '</template>'.size)]
    selects = plugin_part.scan(%r{<select\b.*?</select>}m)
    menu = Nokogiri::HTML(body)
    template = menu.at_css("template#cf-wizard-#{parent.id}")
    child_select = template.at_css("select[name='issue[custom_field_values][#{child.id}]']")

    expect(selects.size).to eq(2)
    expect(child_select.css('option').count { |o| !['', '__none__'].include?(o['value']) }).to eq(5570)
    expect(child_select['data-dcf-map']).to be_present
    expect(menu.at_css("li.folder.cf_#{child.id}")).to be_nil
    expect(body.bytesize).to be <= 512 * 1024
    expect(plugin_part.bytesize).to be <= selects.sum(&:bytesize) + (16 * 1024)
    RSpec.configuration.reporter.message(
      format('DCF BUDGET context menu S1: %<body>d bytes, wizard %<wizard>d bytes, selects %<selects>d bytes',
             body: body.bytesize, wizard: plugin_part.bytesize, selects: selects.sum(&:bytesize))
    )
  end
end
