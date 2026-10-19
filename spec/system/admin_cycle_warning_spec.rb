# frozen_string_literal: true

require_relative '../rails_helper'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-10 (UX-10, G4): the cycle warning of the
# admin custom field form shows the warning icon on 5.1 (classic icon class)
# and on 6.0 and later (sprite icon). The screenshot is the G4 evidence.
RSpec.describe 'Admin custom field form cycle warning', type: :system do
  include DcfStoredCycle

  fixtures :users

  it 'shows the warning with its icon under the parent select of a stored-cycle member' do
    world = dcf_stored_cycles(:list)

    dcf_login
    visit "/custom_fields/#{world.x.id}/edit"

    text = I18n.t(:warning_dcf_parent_cycle, fields: [world.x.name, world.y.name].join(', '))
    warning = find('p.icon.icon-warning', text: text)
    if Redmine::VERSION::MAJOR >= 6
      expect(warning).to have_css('svg.icon-svg', visible: :all)
    else
      expect(page.evaluate_script(
               "getComputedStyle(document.querySelector('p.icon.icon-warning')).backgroundImage"
             )).to include('url(')
    end
    expect(page).to have_select('custom_field_parent_custom_field_id', selected: world.y.name)

    dir = Rails.root.join('tmp', 'capybara', 'dcf', 'wp-10')
    FileUtils.mkdir_p(dir)
    shot = dir.join("admin-cycle-warning-#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}.png").to_s
    page.driver.browser.save_screenshot(shot)
    expect(File.size(shot)).to be > 0
  end
end
