# frozen_string_literal: true

require_relative '../rails_helper'
require 'timeout'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-15: the context menu wizard rendered from
# the selection graph opens and saves. WP-18: the wizard script posts to the
# form action (the named route) and the new runtime filters the fields; every
# field opens on '(no change)' (UD-11), this example picks both values.
# WP-34 (UD-10 changed by the owner on 2026-11-02): a required descendant gets
# no (none) option and stays on '(No change)' when the root is set to (none)
# (screenshots in tmp/capybara/dcf/wp-34/). WP-36 (UD-13 changed by the
# owner): the menu holds the entry only and the body is fetched on open: a
# loading state, a Cancel button and Escape, and a generic message for a
# failed fetch that a second click retries (screenshots in
# tmp/capybara/dcf/wp-36/).
RSpec.describe 'Context menu wizard', type: :system do
  fixtures :users

  let(:version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }

  def shot(name, wp: 'wp-34')
    dir = Rails.root.join('tmp', 'capybara', 'dcf', wp)
    FileUtils.mkdir_p(dir)
    path = dir.join("#{name}-#{version}.png").to_s
    page.driver.browser.save_screenshot(path)
    expect(File.size(path)).to be > 0
  end

  def wizard_world(name)
    project = dcf_create_project(name: name)
    project.enabled_module_names = %w[issue_tracking]
    parent = dcf_list_field(name: "#{name}Parent", values: %w[A B])
    child = dcf_list_field(format: 'depending_list', name: "#{name}Child", values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
    issue = dcf_real_issue(project.reload, parent => 'A', child => 'a1')
    [project, parent, child, issue]
  end

  def open_entry(project, issue, parent)
    visit "/projects/#{project.identifier}/issues"
    find("tr#issue-#{issue.id} td.subject").right_click
    entry = find("#context-menu li.cf-parent[data-parent-id='#{parent.id}']")
    # WP-36: the menu carries the entry only.
    expect(entry).to have_no_css('select, form, template', visible: :all)
    expect(page).to have_no_css('#context-menu template', visible: :all)
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu").click
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
      shot('wizard-open', wp: 'wp-36')
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

  # WP-36: the loading state is visible until the body arrives (the server
  # answer is held back), then the form; Cancel and Escape close it and
  # store nothing.
  it 'shows a loading state, then closes with Cancel and with Escape without saving (WP-36)' do
    project, parent, child, issue = wizard_world('WizCancel')
    dcf_login
    visit "/projects/#{project.identifier}/issues"
    # Hold the answer back in the page (fetch wrapped) to see the loading state.
    page.execute_script(<<~JS)
      window.dcfHold = [];
      var realFetch = window.fetch;
      window.fetch = function (url, init) {
        if (init && init.method === 'GET') {
          return new Promise(function (resolve) { window.dcfHold.push(function () { resolve(realFetch(url, init)); }); });
        }
        return realFetch(url, init);
      };
    JS
    find("tr#issue-#{issue.id} td.subject").right_click
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu").click
    expect(page).to have_css('#cf-wizard-container [role=status]', text: 'Loading...')
    expect(page).to have_no_css('#cf-wizard-container form')
    shot('wizard-loading', wp: 'wp-36')
    page.execute_script('window.dcfHold.forEach(function (go) { go(); });')
    within('#cf-wizard-container') do
      find("select[name='issue[custom_field_values][#{parent.id}]'] option[value='B']").select_option
      click_button 'Cancel'
    end
    expect(page).to have_no_css('#cf-wizard-container form', visible: :all)
    expect(page).to have_css('#cf-wizard-container', visible: :hidden)

    visit "/projects/#{project.identifier}/issues"
    open_entry(project, issue, parent)
    within('#cf-wizard-container') do
      find("select[name='issue[custom_field_values][#{parent.id}]'] option[value='B']").select_option
    end
    find("select[name='issue[custom_field_values][#{parent.id}]']").send_keys(:escape)
    expect(page).to have_no_css('#cf-wizard-container form', visible: :all)
    expect(issue.reload.custom_field_value(parent)).to eq('A')
    expect(issue.reload.custom_field_value(child)).to eq('a1')
  end

  # WP-39 (R5a): the entry starts loading the body when the pointer rests on
  # it (about 150 ms) or the link gets the keyboard focus; the click then
  # opens with that body (no second request); a pass-over sends nothing.
  # Changed by WP-39 review round 1: no fixed sleeps (polling, and waits on a
  # page timer, which fires after any prefetch timer set before it), the
  # pass-over is timed in the page and retried on a fresh menu when the
  # driver rested 100 ms or more on the entry, and the adoption is shown by
  # the one GET starting before the click.
  # Records the wizard GETs (start time), their answers, the entry clicks and
  # the pointer crossings of an entry, all in page time (performance.now()).
  def instrument_wizard
    page.execute_script(<<~JS)
      window.dcfGets = []; window.dcfDone = 0; window.dcfClicks = []; window.dcfDwell = [];
      var realFetch = window.fetch;
      window.fetch = function (url, init) {
        var answer = realFetch.apply(this, arguments);
        if ((!init || init.method === 'GET') && String(url).indexOf('/depending_custom_fields/wizard') !== -1) {
          window.dcfGets.push(performance.now());
          answer.then(function () { window.dcfDone += 1; }, function () { window.dcfDone += 1; });
        }
        return answer;
      };
      var entry = function (e) {
        var li = e.target.closest ? e.target.closest('li.cf-parent') : null;
        return li && !(e.relatedTarget && li.contains(e.relatedTarget)) ? li : null;
      };
      document.addEventListener('mouseover', function (e) { if (entry(e)) window.dcfDwell.push(['in', performance.now()]); }, true);
      document.addEventListener('mouseout', function (e) { if (entry(e)) window.dcfDwell.push(['out', performance.now()]); }, true);
      document.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('li.cf-parent > a.submenu')) window.dcfClicks.push(performance.now());
      }, true);
    JS
  end

  def wizard_gets
    page.evaluate_script('window.dcfGets.length')
  end

  def wait_until(seconds = Capybara.default_max_wait_time)
    Timeout.timeout(seconds) { sleep 0.05 until yield }
  end

  # Waits for a page timer of ms: every timer the page set before it with a
  # shorter delay (the 150 ms prefetch delay) has fired by then.
  def wait_page_timer(ms)
    page.execute_script("window.dcfTick = false; setTimeout(function () { window.dcfTick = true; }, #{Integer(ms)});")
    wait_until { page.evaluate_script('window.dcfTick') }
  end

  # Opens the menu, moves away and passes over the entry in one action chain.
  # The time between entering and leaving the entry, or nil when the driver
  # dispatched no crossing; nil too when the open itself started a prefetch.
  def pass_over(issue, link_css, away)
    find("tr#issue-#{issue.id} td.subject").right_click
    link = find(link_css)
    page.driver.browser.action.move_to(away.native).perform
    wait_page_timer(400)
    return nil unless wizard_gets.zero?

    page.execute_script('window.dcfDwell = [];')
    # duration 0: Selenium's default move takes 250 ms and passes the entry slowly.
    page.driver.browser.action.move_to(link.native, duration: 0).move_to(away.native, duration: 0).perform
    wait_page_timer(400)
    page.evaluate_script(<<~JS)
      (function () {
        var d = window.dcfDwell;
        var into = d.filter(function (x) { return x[0] === 'in'; })[0];
        var out = d.filter(function (x) { return x[0] === 'out'; }).pop();
        return into && out ? out[1] - into[1] : null;
      })()
    JS
  end

  it 'prefetches the body on hover and on focus, opens it with that one request and saves (WP-39)' do
    project, parent, child, issue = wizard_world('WizPrefetch')
    dcf_login
    visit "/projects/#{project.identifier}/issues"
    instrument_wizard
    link_css = "#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu"
    heading = find('#content h2', match: :first)
    dwell = nil
    attempts = 0
    3.times do
      attempts += 1
      dwell = pass_over(issue, link_css, heading)
      break if dwell && dwell < 100

      # A slow chain (or a prefetch on open): close the menu (core hides it,
      # the wizard drops the prefetch) and try again on a rebuilt menu.
      heading.click
      page.execute_script('window.dcfGets = []; window.dcfDone = 0;')
    end
    puts "DCF PASS-OVER dwell #{dwell.inspect} ms, attempts #{attempts}"
    expect(dwell).to be < 100
    expect(wizard_gets).to eq(0)

    link = find(link_css)
    link.hover
    wait_until { wizard_gets == 1 }
    wait_until { page.evaluate_script('window.dcfDone') == 1 }
    link.click
    within('#cf-wizard-container') do
      expect(page).to have_css("select[name='issue[custom_field_values][#{child.id}]'][data-dcf-map-ref]")
    end
    expect(wizard_gets).to eq(1)
    started, clicked = page.evaluate_script('[window.dcfGets[0], window.dcfClicks[window.dcfClicks.length - 1]]')
    expect(started).to be < clicked
    within('#cf-wizard-container') do
      expect(page).to have_css('script[type="application/json"]', visible: :all, count: 1)
      find("select[name='issue[custom_field_values][#{parent.id}]'] option[value='B']").select_option
      selectable = dcf_selectable_options("issue_custom_field_values_#{child.id}")
      expect(selectable).to include('b1')
      expect(selectable).not_to include('a1')
      find("select[name='issue[custom_field_values][#{child.id}]'] option[value='b1']").select_option
      shot('wizard-prefetched', wp: 'wp-39')
      find('form.cf-wizard-form button[type=submit]').click
    end
    Timeout.timeout(Capybara.default_max_wait_time * 3) do
      sleep 0.1 until issue.reload.custom_field_value(parent) == 'B'
    end
    expect(issue.reload.custom_field_value(child)).to eq('b1')

    visit "/projects/#{project.identifier}/issues"
    instrument_wizard
    find("tr#issue-#{issue.id} td.subject").right_click
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}']")
    page.execute_script(<<~JS, parent.id)
      document.querySelector('#context-menu li.cf-parent[data-parent-id="' + arguments[0] + '"] > a.submenu').focus();
    JS
    wait_until { wizard_gets == 1 }
    wait_page_timer(300)
    expect(wizard_gets).to eq(1)
  end

  it 'shows a generic message when the body cannot be loaded, and a second click retries (WP-36)' do
    project, parent, _child, issue = wizard_world('WizFail')
    role = dcf_create_role(permissions: [:view_issues, :edit_issues])
    hidden = dcf_list_field(format: 'depending_list', name: 'WizFailHiddenZz', values: %w[h1], parent: parent)
    hidden.update!(visible: false, role_ids: [dcf_create_role(permissions: [:view_issues]).id])
    issue.tracker.custom_fields << hidden
    member = User.new(login: "wizfail#{SecureRandom.hex(3)}", firstname: 'Wiz', lastname: 'Fail',
                      mail: "wizfail#{SecureRandom.hex(3)}@example.net", status: User::STATUS_ACTIVE, language: 'en')
    member.password = 'secret-12345'
    member.password_confirmation = 'secret-12345'
    member.save!
    dcf_add_member(member, project, role)
    dcf_login(member.login, 'secret-12345')
    visit "/projects/#{project.identifier}/issues"
    find("tr#issue-#{issue.id} td.subject").right_click
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}']")
    # A missing issue id: the server answers 404.
    page.execute_script(<<~JS, parent.id, Issue.maximum(:id).to_i + 1_000)
      document.querySelector('#context-menu li.cf-parent[data-parent-id="' + arguments[0] + '"]')
        .setAttribute('data-issue-ids', String(arguments[1]));
    JS
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu").click
    expect(page).to have_css('#cf-wizard-container [role=alert]',
                             text: 'The wizard could not be loaded. Click the entry again to try again.')
    expect(page).to have_no_css('#cf-wizard-container form')
    expect(page).not_to have_text('WizFailHiddenZz')
    shot('wizard-load-failed', wp: 'wp-36')
    page.execute_script(<<~JS, parent.id, issue.id)
      document.querySelector('#context-menu li.cf-parent[data-parent-id="' + arguments[0] + '"]')
        .setAttribute('data-issue-ids', String(arguments[1]));
    JS
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu").click
    within('#cf-wizard-container') do
      expect(page).to have_css("select[name='issue[custom_field_values][#{parent.id}]']")
      expect(page).to have_no_css('[role=alert]')
    end
    expect(page).not_to have_text('WizFailHiddenZz')
  end
end
