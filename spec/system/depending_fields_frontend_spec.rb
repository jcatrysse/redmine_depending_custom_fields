# frozen_string_literal: true

require_relative '../rails_helper'
require 'timeout'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-18: the issue form, bulk edit and the
# context-menu wizard run the new runtime (assets/javascripts/
# depending_custom_fields.js) and the reworked wizard script in a real
# browser on 5.1 and 7.0: filtering, hints shown and hidden ([hidden] beats
# core's display:block on em.info and .check_box_group label), the live
# region, a stored value the parent does not allow kept through a
# notes-only save and restored on A to B to A, bulk edit (UD-09),
# updateIssueFrom re-init, the wizard save (UD-11), the WP-09b case and the
# UD-37 warning. Screenshots go to tmp/capybara/dcf/wp-18/. WP-19 adds a
# required radio child cleared through the blank sentinel and the marked
# (none) of a required child in bulk edit (UD-10); their screenshots go to
# tmp/capybara/dcf/wp-19/.
RSpec.describe 'Depending fields in the browser (WP-18, WP-19)', type: :system do
  fixtures :users

  let(:version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }
  let(:project) do
    record = dcf_create_project(name: 'Frontend')
    record.enabled_module_names = %w[issue_tracking]
    record
  end

  def shot(name, wp: 'wp-18')
    dir = Rails.root.join('tmp', 'capybara', 'dcf', wp)
    FileUtils.mkdir_p(dir)
    path = dir.join("#{name}-#{version}.png").to_s
    page.driver.browser.save_screenshot(path)
    expect(File.size(path)).to be > 0
  end

  def js(script)
    page.evaluate_script(script)
  end

  def display_of(selector)
    js("(function () { var el = document.querySelector(#{selector.to_json}); return el ? getComputedStyle(el).display : null; })()")
  end

  def select_value(dom_id, value)
    find("##{dom_id} option[value='#{value}']").select_option
  end

  def value_of(dom_id)
    js("document.getElementById(#{dom_id.to_json}).value")
  end

  def attribute_of(dom_id, name)
    js("document.getElementById(#{dom_id.to_json}).getAttribute(#{name.to_json})")
  end

  # The text of the visible hint tied to the control by aria-describedby.
  def hint_of(dom_id)
    js(<<~JS)
      (function () {
        var el = document.getElementById(#{dom_id.to_json});
        var ids = (el.getAttribute('aria-describedby') || '').split(/\\s+/).filter(Boolean);
        for (var i = 0; i < ids.length; i += 1) {
          var h = document.getElementById(ids[i]);
          if (h && !h.hidden && getComputedStyle(h).display !== 'none') return h.textContent;
        }
        return null;
      })()
    JS
  end

  def wait_until(seconds = Capybara.default_max_wait_time * 3)
    Timeout.timeout(seconds) { sleep 0.1 until yield }
  end

  def pair(multiple: false, style: nil)
    parent = dcf_list_field(values: %w[Alpha Beta Gamma], name: 'Fe parent')
    child = dcf_list_field(format: 'depending_list', values: %w[Ant Ape Bee], parent: parent, name: 'Fe child',
                           multiple: multiple)
    child.update!(edit_tag_style: style) if style
    child = dcf_set_dependencies(child, value_dependencies: { 'Alpha' => %w[Ant Ape], 'Beta' => %w[Bee] },
                                        default_value_dependencies: { 'Beta' => 'Bee' })
    [parent, child]
  end

  def member_with(permissions)
    role = dcf_create_role(permissions: permissions)
    user = User.new(firstname: 'Fe', lastname: 'Member', mail: "fe-#{SecureRandom.hex(3)}@example.net", language: 'en')
    user.login = "fe#{SecureRandom.hex(3)}"
    user.password = user.password_confirmation = 'dcf-frontend-1'
    user.status = User::STATUS_ACTIVE
    user.save!
    dcf_add_member(user, project, role)
    [user, role]
  end

  it 'filters the issue form, shows and hides hints and keeps a stored value through a notes-only save' do
    parent, child = pair
    issue = dcf_real_issue(project.reload, parent => 'Alpha', child => 'Ant')
    CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: child.id).update_all(value: 'Bee')
    child_id = "issue_custom_field_values_#{child.id}"
    parent_id = "issue_custom_field_values_#{parent.id}"

    dcf_login
    visit "/issues/#{issue.id}/edit"
    expect(page).to have_css("##{child_id}[data-dcf-state='legacy']", visible: :all)
    expect(dcf_selectable_options(child_id)).to eq(['', 'Ant', 'Ape', 'Bee'])
    expect(hint_of(child_id)).to include('Bee')
    expect(js("document.querySelector('##{child_id} option[value=\"Bee\"]').classList.contains('dcf-legacy-option')"))
      .to be(true)
    expect(js("document.getElementById(#{child_id.to_json}).disabled")).to be(false)
    shot('issue-form-legacy')

    hint_box = "document.getElementById(#{child_id.to_json}).closest('p').querySelector('em.dcf-hint')"
    expect(js("getComputedStyle(#{hint_box}).display")).to eq('block')

    select_value(parent_id, 'Gamma')
    expect(dcf_selectable_options(child_id)).to eq([''])
    expect(value_of(child_id)).to eq('')
    expect(hint_of(child_id)).to eq('No values are available for the selected Fe parent.')
    wait_until { js("(document.getElementById('dcf-live') || {}).textContent || ''").include?('No values are available') }
    expect(attribute_of('dcf-live', 'aria-live')).to eq('polite')
    # A to B to A: the cleared stored value comes back, kept and marked.
    select_value(parent_id, 'Alpha')
    expect(value_of(child_id)).to eq('Bee')
    expect(attribute_of(child_id, 'data-dcf-state')).to eq('legacy')
    expect(hint_of(child_id)).to include('Bee')
    select_value(parent_id, 'Gamma')
    expect(value_of(child_id)).to eq('')
    select_value(parent_id, '')
    expect(hint_of(child_id)).to eq('Select a value for Fe parent first.')
    select_value(parent_id, 'Beta')
    expect(dcf_selectable_options(child_id)).to eq(['', 'Bee'])
    expect(value_of(child_id)).to eq('Bee')
    # The hint is hidden: [hidden] beats core em.info display:block.
    expect(js("#{hint_box}.hidden")).to be(true)
    expect(js("getComputedStyle(#{hint_box}).display")).to eq('none')
    expect(hint_of(child_id)).to be_nil
    shot('issue-form')
    select_value(parent_id, 'Alpha')
    expect(value_of(child_id)).to eq('Bee')
    expect(attribute_of(child_id, 'data-dcf-state')).to eq('legacy')

    fill_in 'issue_notes', with: 'Only a note'
    find('#issue-form input[name=commit]').click
    expect(page).to have_css('#flash_notice')
    expect(issue.reload.custom_field_value(child)).to eq('Bee')
    expect(issue.journals.last.notes).to eq('Only a note')
  end

  it 'hides the label of a disallowed check box (core display:block loses to [hidden])' do
    parent, child = pair(multiple: true, style: 'check_box')
    issue = dcf_real_issue(project.reload, parent => 'Alpha', child => %w[Ant])

    dcf_login
    visit "/issues/#{issue.id}/edit"
    group = "span.check_box_group[data-dcf-field='#{child.id}']"
    expect(page).to have_css("#{group}[data-dcf-state='ok']", visible: :all)
    bee = "#{group} input[value='Bee']"
    expect(js("document.querySelector(#{bee.to_json}).closest('label').hidden")).to be(true)
    expect(js("getComputedStyle(document.querySelector(#{bee.to_json}).closest('label')).display")).to eq('none')
    expect(js("getComputedStyle(document.querySelector(#{"#{group} input[value='Ant']".to_json}).closest('label')).display"))
      .not_to eq('none')
  end

  it 'filters again after updateIssueFrom re-renders the form' do
    parent, child = pair
    issue = dcf_real_issue(project.reload, parent => 'Alpha', child => 'Ant')
    child_id = "issue_custom_field_values_#{child.id}"

    dcf_login
    visit "/issues/#{issue.id}/edit"
    expect(page).to have_css("##{child_id}[data-dcf-state='ok']", visible: :all)
    select_value("issue_custom_field_values_#{parent.id}", 'Beta')
    expect(value_of(child_id)).to eq('Bee')
    # execute_script: the jqXHR updateIssueFrom returns is not serializable.
    page.execute_script("window.dcfOldChild = document.getElementById(#{child_id.to_json}); " \
                        "updateIssueFrom(#{"/issues/#{issue.id}/edit.js".to_json}, document.getElementById('issue_subject'));")
    wait_until { js("document.getElementById(#{child_id.to_json}) !== window.dcfOldChild") }
    expect(attribute_of(child_id, 'data-dcf-state')).to eq('ok')
    expect(dcf_selectable_options(child_id)).to eq(['', 'Bee'])
    expect(value_of(child_id)).to eq('Bee')
  end

  it 'applies the bulk edit rules of UD-09' do
    parent, child = pair
    issues = [dcf_real_issue(project.reload, parent => 'Alpha', child => 'Ant'),
              dcf_real_issue(project.reload, parent => 'Beta', child => 'Bee')]
    child_id = "issue_custom_field_values_#{child.id}"
    parent_id = "issue_custom_field_values_#{parent.id}"

    dcf_login
    visit "/issues/bulk_edit?#{issues.map { |issue| "ids[]=#{issue.id}" }.join('&')}"
    expect(page).to have_css("##{child_id}[data-dcf-state='unfiltered']", visible: :all)
    expect(value_of(child_id)).to eq('')
    select_value(parent_id, 'Beta')
    expect(value_of(child_id)).to eq('Bee')
    expect(js("document.getElementById(#{child_id.to_json}).classList.contains('dcf-auto-applied')")).to be(true)
    expect(hint_of(child_id)).to eq('Set to the default for the selected Fe parent. Choose (No change) to keep the current values.')
    expect(dcf_selectable_options(child_id)).to include('')
    select_value(parent_id, 'Alpha')
    expect(value_of(child_id)).to eq('')
    expect(dcf_selectable_options(child_id)).to eq(['', '__none__', 'Ant', 'Ape'])
    select_value(parent_id, '__none__')
    expect(value_of(child_id)).to eq('__none__')
    expect(hint_of(child_id)).to eq('Cleared because the current choice for Fe parent allows no values for this field.')
    select_value(parent_id, '')
    expect(value_of(child_id)).to eq('')
    expect(attribute_of(child_id, 'data-dcf-state')).to eq('unfiltered')
    # A pick under '(No change)' comes back when the parent returns to it,
    # and a parent value without links forces '(none)'.
    select_value(child_id, 'Ape')
    select_value(parent_id, '__none__')
    expect(value_of(child_id)).to eq('__none__')
    select_value(parent_id, '')
    expect(value_of(child_id)).to eq('Ape')
    expect(attribute_of(child_id, 'data-dcf-state')).to eq('unfiltered')
    select_value(parent_id, 'Gamma')
    expect(value_of(child_id)).to eq('__none__')
    expect(dcf_selectable_options(child_id)).to eq(['__none__'])
    expect(hint_of(child_id)).to eq('Cleared because the current choice for Fe parent allows no values for this field.')
    select_value(parent_id, '')
    expect(value_of(child_id)).to eq('Ape')
    select_value(child_id, '')
    expect(value_of(child_id)).to eq('')
    shot('bulk-edit')
    find('#bulk_edit_form input[type=submit]').click
    expect(page).to have_css('#flash_notice')
    expect(issues.map { |issue| issue.reload.custom_field_value(child) }).to eq(%w[Ant Bee])
  end

  it 'opens the wizard on (no change) and saves the chosen values' do
    parent, child = pair
    parent.update!(default_value: 'Beta')
    issue = dcf_real_issue(project.reload, parent => 'Alpha', child => 'Ant')

    dcf_login
    visit "/projects/#{project.identifier}/issues"
    find("tr#issue-#{issue.id} td.subject").right_click
    find("#context-menu li.cf-parent[data-parent-id='#{parent.id}'] > a.submenu").click
    within('#cf-wizard-container') do
      expect(page).to have_css("label.cf-wizard-label select[name='issue[custom_field_values][#{parent.id}]']")
    end
    root_value = js("document.querySelector('#cf-wizard-container select[name=\"issue[custom_field_values][#{parent.id}]\"]').value")
    expect(root_value).to eq('')
    expect(js("document.querySelector('#cf-wizard-container select[name=\"issue[custom_field_values][#{child.id}]\"]').getAttribute('data-dcf-state')"))
      .to eq('unfiltered')
    within('#cf-wizard-container') do
      find("select[name='issue[custom_field_values][#{parent.id}]'] option[value='Beta']").select_option
      expect(page).to have_css("select[name='issue[custom_field_values][#{child.id}]'].dcf-auto-applied")
    end
    shot('wizard')
    within('#cf-wizard-container') { find('form.cf-wizard-form button[type=submit]').click }
    wait_until { issue.reload.custom_field_value(parent) == 'Beta' }
    expect(issue.reload.custom_field_value(child)).to eq('Bee')
  end

  # WP-09b open input: an editable dependent field holding a stored value
  # its parent does not allow, with a field the member cannot edit below
  # it. The legacy script cleared it and the save was refused; the new
  # runtime keeps it, so a note saves.
  it 'saves a note on an issue whose editable middle field holds a value its parent does not allow (WP-09b)' do
    grand = dcf_list_field(values: %w[G H], name: 'Fe grand')
    middle = dcf_list_field(format: 'depending_list', values: %w[p1 p2], parent: grand, name: 'Fe middle')
    middle = dcf_set_dependencies(middle, value_dependencies: { 'G' => ['p1'] })
    low = dcf_list_field(format: 'depending_list', values: %w[l1], parent: middle, name: 'Fe low')
    low = dcf_set_dependencies(low, value_dependencies: { 'p2' => ['l1'] })
    member, role = member_with([:view_issues, :edit_issues, :add_issue_notes])
    issue = dcf_real_issue(project.reload, grand => 'G', middle => 'p1', low => '')
    CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: middle.id).update_all(value: 'p2')
    CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: low.id).update_all(value: 'l1')
    WorkflowPermission.create!(tracker_id: issue.tracker_id, old_status_id: issue.status_id, role_id: role.id,
                               field_name: low.id.to_s, rule: 'readonly')
    middle_id = "issue_custom_field_values_#{middle.id}"

    dcf_login(member.login, 'dcf-frontend-1')
    visit "/issues/#{issue.id}/edit"
    expect(page).to have_css("##{middle_id}[data-dcf-state='legacy']", visible: :all)
    expect(page).to have_css('span[data-dcf-locked-parent]', visible: :all)
    expect(value_of(middle_id)).to eq('p2')

    # UD-37: a change the server would refuse shows the warning (text only).
    select_value(middle_id, 'p1')
    warning = 'A dependent field that you cannot edit has a value that this choice does not allow; saving will be refused.'
    expect(hint_of(middle_id)).to eq(warning)
    expect(js("document.querySelector('em.dcf-hint--locked').parentNode === document.getElementById(#{middle_id.to_json}).closest('p')"))
      .to be(true)
    select_value(middle_id, 'p2')
    expect(js("Array.prototype.some.call(document.querySelectorAll('em.dcf-hint--locked'), function (h) { return !h.hidden; })"))
      .to be(false)
    shot('issue-form-wp09b')

    fill_in 'issue_notes', with: 'Note with a kept value'
    find('#issue-form input[name=commit]').click
    expect(page).to have_css('#flash_notice')
    expect([issue.reload.custom_field_value(middle), issue.custom_field_value(low)]).to eq(%w[p2 l1])
    expect(issue.journals.last.notes).to eq('Note with a kept value')
  end

  # WP-19: before the sentinel nothing was posted when no radio was checked,
  # so the stored Ant stayed and the save was refused as 'is invalid'.
  it 'clears a required radio child when the new parent value allows nothing (WP-19)' do
    parent, child = pair(style: 'check_box')
    child.update!(is_required: true)
    issue = dcf_real_issue(project.reload, parent => 'Alpha', child => 'Ant')
    parent_id = "issue_custom_field_values_#{parent.id}"
    group = "span.check_box_group[data-dcf-field='#{child.id}']"
    radios = "#{group} input[type=radio]"

    dcf_login
    visit "/issues/#{issue.id}/edit"
    expect(page).to have_css("#{group}[data-dcf-state='ok']", visible: :all)
    expect(js("document.querySelector(#{group.to_json}).previousElementSibling.getAttribute('data-dcf-blank')")).to eq('1')
    expect(js("document.querySelectorAll('input[data-dcf-blank]').length")).to eq(1)
    select_value(parent_id, 'Gamma')
    expect(js("Array.prototype.filter.call(document.querySelectorAll(#{radios.to_json}), function (i) { return i.checked; }).length"))
      .to eq(0)
    expect(js("Array.prototype.every.call(document.querySelectorAll(#{radios.to_json}), function (i) { return i.closest('label').hidden; })"))
      .to be(true)
    expect(js("document.querySelector('input[data-dcf-blank]').value")).to eq('')
    shot('issue-form-required-radio-cleared', wp: 'wp-19')

    find('#issue-form input[name=commit]').click
    expect(page).to have_css('#flash_notice')
    expect(issue.reload.custom_field_value(parent)).to eq('Gamma')
    expect(issue.custom_field_value(child)).to be_blank
  end

  it 'offers the marked (none) of a required child in bulk edit only while the parent allows nothing (WP-19)' do
    parent, child = pair
    child.update!(is_required: true)
    issues = [dcf_real_issue(project.reload, parent => 'Alpha', child => 'Ant'),
              dcf_real_issue(project.reload, parent => 'Beta', child => 'Bee')]
    child_id = "issue_custom_field_values_#{child.id}"
    parent_id = "issue_custom_field_values_#{parent.id}"
    none = "##{child_id} option[value='__none__'][data-dcf-required-none='1']"

    dcf_login
    visit "/issues/bulk_edit?#{issues.map { |issue| "ids[]=#{issue.id}" }.join('&')}"
    expect(page).to have_css("##{child_id}[data-dcf-state='unfiltered']", visible: :all)
    expect(js("[document.querySelector(#{none.to_json}).disabled, document.querySelector(#{none.to_json}).hidden]"))
      .to eq([true, true])
    select_value(parent_id, 'Alpha')
    expect(dcf_selectable_options(child_id)).to eq(['', 'Ant', 'Ape'])
    select_value(parent_id, '__none__')
    expect(value_of(child_id)).to eq('__none__')
    expect(dcf_selectable_options(child_id)).to eq(['__none__'])
    expect(hint_of(child_id)).to eq('Cleared because the current choice for Fe parent allows no values for this field.')
    shot('bulk-edit-required-none', wp: 'wp-19')

    find('#bulk_edit_form input[type=submit]').click
    expect(page).to have_css('#flash_notice')
    expect(issues.map { |issue| [issue.reload.custom_field_value(parent), issue.custom_field_value(child)] })
      .to eq([['', ''], ['', '']])
  end
end
