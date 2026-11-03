# frozen_string_literal: true

require_relative '../rails_helper'
require 'timeout'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-15: the context menu wizard rendered from
# the selection graph opens and saves. WP-18: the wizard script posts to the
# form action (the named route) and the new runtime filters the fields; every
# field opens on '(no change)' (UD-11), this example picks both values.
# WP-34 (UD-10 changed by the owner on 2026-11-02): a required descendant gets
# no (none) option and stays on '(No change)' when the root is set to (none)
# (screenshots in tmp/capybara/dcf/wp-34/).
RSpec.describe 'Context menu wizard', type: :system do
  fixtures :users

  let(:version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }

  def shot(name)
    dir = Rails.root.join('tmp', 'capybara', 'dcf', 'wp-34')
    FileUtils.mkdir_p(dir)
    path = dir.join("#{name}-#{version}.png").to_s
    page.driver.browser.save_screenshot(path)
    expect(File.size(path)).to be > 0
  end

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

  it 'gives a required descendant no (none) and keeps it on (No change) when the root is set to (none) (WP-34)' do
    project = dcf_create_project(name: 'Wizard required')
    project.enabled_module_names = %w[issue_tracking]
    root = dcf_list_field(name: 'WizRoot', values: %w[A B C])
    middle = dcf_list_field(format: 'depending_list', name: 'WizMiddle', values: %w[a1 b1], parent: root)
    dcf_set_dependencies(middle, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
    leaf = dcf_list_field(format: 'depending_list', name: 'WizLeaf', values: %w[x1], parent: middle)
    dcf_set_dependencies(leaf, value_dependencies: { 'a1' => %w[x1] })
    issue = dcf_real_issue(project.reload, root => 'A', middle => 'a1', leaf => 'x1')
    middle.update!(is_required: true)

    dcf_login
    visit "/projects/#{project.identifier}/issues"
    find("tr#issue-#{issue.id} td.subject").right_click
    find("#context-menu li.cf-parent[data-parent-id='#{root.id}'] > a.submenu").click

    within('#cf-wizard-container') do
      middle_select = "select[name='issue[custom_field_values][#{middle.id}]']"
      leaf_select = "select[name='issue[custom_field_values][#{leaf.id}]']"
      expect(page).to have_css("#{middle_select}[data-dcf-state='unfiltered']", visible: :all)
      # WP-34 review round 1 (tests-r1-10): have_no_css, no wait for a match.
      expect(page).to have_no_css("#{middle_select} option[value='__none__']", visible: :all)
      expect(all("#{leaf_select} option[value='__none__']", visible: :all).size).to eq(1)
      find("select[name='issue[custom_field_values][#{root.id}]'] option[value='__none__']").select_option
      expect(page).to have_css("#{middle_select}[data-dcf-state='none']", visible: :all)
      expect(find(middle_select).value).to eq('')
      expect(page).to have_text('No values are available for the selected WizRoot.')
      expect(page).to have_css("#{leaf_select}[data-dcf-state='unfiltered']", visible: :all)
      expect(find(leaf_select).value).to eq('')
    end
    shot('wizard-required-descendant')
  end
end
