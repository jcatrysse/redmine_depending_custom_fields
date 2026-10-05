# frozen_string_literal: true

require_relative '../rails_helper'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-03: submitting the core bulk edit form must
# keep an untouched multi-value dependent field (it used to be cleared).
RSpec.describe 'Bulk edit with an untouched multi-value dependent field', type: :system do
  fixtures :users

  it 'keeps the stored child values of every selected issue' do
    project = dcf_create_project(name: 'Bulk')
    project.enabled_module_names = %w[issue_tracking]
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: parent, multiple: true)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1] })
    issues = Array.new(2) { dcf_real_issue(project.reload, parent => 'A', child => %w[a1 a2]) }

    dcf_login
    visit "/issues/bulk_edit?#{issues.map { |issue| "ids[]=#{issue.id}" }.join('&')}"
    find('#bulk_edit_form input[type=submit]').click

    expect(page).to have_css('#flash_notice')
    issues.each do |issue|
      expect(Array(issue.reload.custom_field_value(child)).sort).to eq(%w[a1 a2])
    end
  end
end
