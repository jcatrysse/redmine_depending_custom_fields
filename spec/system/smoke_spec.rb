# frozen_string_literal: true

require_relative '../rails_helper'

# Opt-in (DCF_SYSTEM_SPECS=1): proves the browser stack works on this Redmine
# version, so later system specs fail for real reasons only.
RSpec.describe 'Browser smoke test', type: :system do
  fixtures :users

  it 'logs in and opens the new issue form with a depending field' do
    project = dcf_create_project(name: 'Smoke')
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
    tracker, = dcf_issue_infra(project)
    [parent, child].each { |field| tracker.custom_fields << field unless tracker.custom_fields.include?(field) }
    project.enabled_module_names = %w[issue_tracking]

    dcf_login
    visit "/projects/#{project.identifier}/issues/new"

    expect(page).to have_css("#issue_custom_field_values_#{parent.id}")
    expect(page).to have_css("#issue_custom_field_values_#{child.id}", visible: :all)
  end
end
