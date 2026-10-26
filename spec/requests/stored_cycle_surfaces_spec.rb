# frozen_string_literal: true

require_relative '../rails_helper'

# WP-18 (Tests item 5, PC-36): every page that renders depending fields
# answers 200 with stored cycles, self-parents and fields below them in the
# data, logs no rescued '[DCF] ...' warning, and gives the cycle
# members and the fields below them no parent attributes (UD-08), so the new
# runtime leaves them unfiltered.
RSpec.describe 'Pages with stored cycles (WP-18)', type: :request do
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }

  before do
    allow(User).to receive(:current).and_return(dcf_admin)
    allow(Rails.logger).to receive(:warn).and_call_original
  end

  def expect_page(label)
    expect(response).to have_http_status(200), label
    expect(response.body).not_to include('SystemStackError'), label
    Nokogiri::HTML(response.body)
  end

  def member_controls(page, world)
    world.depending.filter_map { |field| page.at_css("[data-dcf-field='#{field.id}']") }
  end

  [:list, :enumeration].each do |kind|
    it "renders the issue, bulk, context-menu, admin and project pages of a #{kind} world" do
      world = dcf_stored_cycles(kind)
      values = { world.x => 'x1', world.y => 'y1', world.child => 'c1', world.self_parent => 's1',
                 world.below_self_parent => 'd1', world.a => 'a1', world.b => 'b1', world.c => 'k1' }
      issues = Array.new(2) { kit_issue(project, values) }
      tracker = issues.first.tracker
      seen = []

      get "/issues/#{issues.first.id}/edit"
      seen << member_controls(expect_page('issue edit'), world)
      get "/projects/#{project.identifier}/issues/new", params: { issue: { tracker_id: tracker.id } }
      seen << member_controls(expect_page('issue new'), world)
      get '/issues/bulk_edit', params: { ids: issues.map(&:id) }
      seen << member_controls(expect_page('bulk edit'), world)
      post '/issues/context_menu', params: { ids: issues.map(&:id) }
      seen << member_controls(expect_page('context menu'), world)

      world.depending.each do |field|
        get "/custom_fields/#{field.id}/edit"
        expect_page("admin form #{field.name}")
        get custom_field_configuration_field_path(project, field)
        expect_page("project values #{field.name}")
        get custom_field_configuration_field_dependencies_path(project, field)
        expect_page("project dependencies #{field.name}")
      end
      get settings_project_path(project, tab: 'custom_field_configuration')
      expect_page('project configuration tab')
      get settings_project_path(project)
      expect_page('project settings')

      expect(seen.first(3).map(&:size)).to all(eq(world.depending.size))
      seen.flatten.each do |node|
        expect(node['data-dcf-parent']).to be_nil, node['data-dcf-field']
        expect(node.attribute_nodes.map(&:name).grep(/\Adata-dcf-(map|defaults|parent|stored)/)).to eq([])
      end
      # Any rescued plugin error (failed or skipped) counts.
      expect(Rails.logger).not_to have_received(:warn).with(/\A\[DCF\]/)
    end
  end
end
