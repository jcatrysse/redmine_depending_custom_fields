# frozen_string_literal: true

require_relative '../rails_helper'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-34 (UD-23 changed by the owner on
# 2026-11-02): Sort A-Z / Z-A on the values page in a real browser on 5.1 and
# 7.0. A field shared with other projects asks no browser question: the
# server confirmation panel appears, and ticking the box and Apply sorts. A
# project-only field asks the browser question once and shows no panel.
# Screenshots go to tmp/capybara/dcf/wp-34/.
RSpec.describe 'Values page sort confirmation in the browser (WP-34)', type: :system do
  fixtures :users

  let(:version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }
  let(:project) { dcf_create_project(name: 'Sort project') }
  let(:other) { dcf_create_project(name: 'Sort other') }

  def shot(name)
    dir = Rails.root.join('tmp', 'capybara', 'dcf', 'wp-34')
    FileUtils.mkdir_p(dir)
    path = dir.join("#{name}-#{version}.png").to_s
    page.driver.browser.save_screenshot(path)
    expect(File.size(path)).to be > 0
  end

  def sort_button(label)
    find("form.dcf-values-sort [type=submit][value='#{label}']")
  end

  def row_values
    all('table.dcf-values tbody tr').map { |tr| tr['data-dcf-value'] }
  end

  it 'shows the server panel for a shared field without a browser dialog, then sorts after the tick and Apply' do
    field = dcf_list_field(name: 'Shared sort', values: %w[c a b], is_for_all: false, projects: [project, other])
    dcf_login
    visit "/projects/#{project.identifier}/custom_field_configuration/fields/#{field.id}"
    expect(page).to have_css('div.flash.warning', text: I18n.t(:text_shared_field_warning))
    expect(sort_button(I18n.t(:label_dcf_sort_az))['data-confirm']).to be_nil

    sort_button(I18n.t(:label_dcf_sort_az)).click
    panel = find('.dcf-confirm-panel')
    expect(panel).to have_text(I18n.t(:text_dcf_sort_confirm, count: 3))
    expect(panel).to have_no_text(I18n.t(:label_usage_this_project))
    expect(field.reload.possible_values).to eq(%w[c a b])
    shot('values-sort-panel')

    panel.find('input[type=checkbox][name=confirm]').check
    panel.find("input[type=submit][value='#{I18n.t(:button_apply)}']").click
    expect(page).to have_css('#flash_notice', text: I18n.t(:notice_values_sorted))
    expect(page).to have_no_css('.dcf-confirm-panel')
    expect(field.reload.possible_values).to eq(%w[a b c])
    expect(row_values).to eq(%w[a b c])
  end

  it 'asks the browser question once for a project-only field and shows no panel' do
    field = dcf_list_field(name: 'Own sort', values: %w[c a b], is_for_all: false, projects: [project])
    dcf_login
    visit "/projects/#{project.identifier}/custom_field_configuration/fields/#{field.id}"
    expect(page).to have_no_css('div.flash.warning')

    dismiss_confirm(I18n.t(:text_dcf_sort_confirm, count: 3)) { sort_button(I18n.t(:label_dcf_sort_za)).click }
    expect(field.reload.possible_values).to eq(%w[c a b])
    accept_confirm(I18n.t(:text_dcf_sort_confirm, count: 3)) { sort_button(I18n.t(:label_dcf_sort_za)).click }
    expect(page).to have_css('#flash_notice', text: I18n.t(:notice_values_sorted))
    expect(page).to have_no_css('.dcf-confirm-panel')
    expect(field.reload.possible_values).to eq(%w[c b a])
    shot('values-sort-project-only')
  end
end
