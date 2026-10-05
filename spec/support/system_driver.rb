# frozen_string_literal: true

# Opt-in browser specs (DCF_SYSTEM_SPECS=1). Uses core's test gems
# (capybara + selenium-webdriver, present in the test group of 5.1..7.0).
# Browser: Selenium Manager resolves a matching Chrome + chromedriver unless
# CHROME_BIN (and a matching driver on PATH) is given.
require 'capybara/rspec'
require 'selenium-webdriver'

module DcfSystemHelpers
  def dcf_login(login = 'admin', password = 'admin')
    visit '/login'
    fill_in 'username', with: login
    fill_in 'password', with: password
    find('#login-submit').click
    # 5.1-6.x show #loggedas, 7.0 an avatar menu; a.logout exists in all of them.
    expect(page).to have_css('a.logout', visible: :all)
  end

  # Selenium reports every <option> of a visible <select> as displayed, even
  # with [hidden]; assert selectability from the DOM instead.
  def dcf_selectable_options(dom_id)
    page.evaluate_script(<<~JS)
      Array.prototype.filter.call(document.getElementById(#{dom_id.to_json}).options, function (o) {
        return !o.hidden && !o.disabled && getComputedStyle(o).display !== 'none';
      }).map(function (o) { return o.value; })
    JS
  end
end

RSpec.configure do |config|
  config.include DcfSystemHelpers, type: :system
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000] do |options|
      options.binary = ENV['CHROME_BIN'] if ENV['CHROME_BIN'].to_s != ''
      %w[no-sandbox disable-dev-shm-usage disable-gpu].each { |arg| options.add_argument("--#{arg}") }
    end
  end
end
