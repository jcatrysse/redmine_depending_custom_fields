# frozen_string_literal: true

require_relative '../rails_helper'
require 'timeout'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-15: the context menu wizard rendered from
# the selection graph opens and saves. WP-18: the wizard script posts to the
# form action (the named route) and the new runtime filters the fields; every
# field opens on '(no change)' (UD-11), this example picks both values.
RSpec.describe 'Context menu wizard', type: :system do
  fixtures :users

  it 'opens from the issue list and saves the chosen values' do
    project = dcf_create_project(name: 'Wizard')
    project.enabled_module_names = %w[issue_tracking]
    parent = dcf_list_field(name: 'WizardParent', values: %w[A B])
    child = dcf_list_field(format: 'depending_list', name: 'WizardChild', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
    issue = dcf_real_issue(project.reload, parent => 'A', child => 'a1')

    dcf_login
    visit "/projects/#{project.identifier}/issues"
    find("tr#issue-#{issue.id} td.subject").right_click
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu").click

    within('#cf-wizard-container') do
      find("select[name='issue[custom_field_values][#{parent.id}]'] option[value='B']").select_option
      find("select[name='issue[custom_field_values][#{child.id}]'] option[value='b1']").select_option
      find('form.cf-wizard-form button[type=submit]').click
    end

    # The script reloads the page after a successful save.
    Timeout.timeout(Capybara.default_max_wait_time * 3) do
      sleep 0.1 until issue.reload.custom_field_value(parent) == 'B'
    end
    expect(page).to have_css("tr#issue-#{issue.id}")
    expect(issue.reload.custom_field_value(child)).to eq('b1')
  end
end
