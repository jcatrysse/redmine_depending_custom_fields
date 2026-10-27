# frozen_string_literal: true

require_relative '../rails_helper'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-25 (editor design 5.4 to 5.11, UD-16,
# UD-17, UD-20): the admin dependency editor in a real browser on 5.1 and
# 7.0: links edited, saved and reloaded; the form switched to multipart; a
# live parent change through the values endpoint; a stale save across two
# tabs with the conflict panel; the size pre-check; lazy sections, search
# and check all shown; the unsaved warning only after an edit. Screenshots
# (icons included) go to tmp/capybara/dcf/wp-25/.
RSpec.describe 'Admin dependency editor in the browser (WP-25)', type: :system do
  fixtures :users

  let(:version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }
  let(:parent) { dcf_list_field(values: %w[Belgium France Germany], name: 'Ed country') }
  let(:other) { dcf_list_field(values: %w[Spain Belgium], name: 'Ed other') }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', values: %w[Antwerp Brussels Paris Lyon], parent: parent,
                           name: 'Ed city')
    field.update!(is_required: true)
    dcf_set_dependencies(field, value_dependencies: { 'Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris],
                                                      'Atlantis' => %w[Gone] },
                                default_value_dependencies: { 'Belgium' => 'Brussels' })
  end

  def shot(name)
    page.execute_script("var e = document.querySelector('fieldset.dcf-dep-editor'); if (e) e.scrollIntoView();")
    dir = Rails.root.join('tmp', 'capybara', 'dcf', 'wp-25')
    FileUtils.mkdir_p(dir)
    path = dir.join("#{name}-#{version}.png").to_s
    page.driver.browser.save_screenshot(path)
    expect(File.size(path)).to be > 0
  end

  def js(script)
    page.evaluate_script(script)
  end

  def stored(field)
    record = CustomField.find(field.id)
    [record.value_dependencies.to_hash, record.default_value_dependencies.to_hash]
  end

  def section(key)
    find("details.dcf-dep-section[data-dcf-ed-section='#{key}']")
  end

  def open_section(key)
    details = section(key)
    details.find('summary').click
    expect(details).to have_css('.dcf-dep-section__body')
    details
  end

  def tick(details, key)
    details.find("input[data-dcf-ed-child-key='#{key}']").click
  end

  def save
    find('#custom_field_form input[type=submit][name=commit]', match: :first).click
  end

  def edit(field)
    visit "/custom_fields/#{field.id}/edit"
    expect(page).to have_css('fieldset.dcf-dep-editor .dcf-dep-editor__sections')
  end

  def wants_warning
    js("DcfDependencyEditor.get(document.querySelector('[data-dcf-editor]')).wantsWarning()")
  end

  def linked(count, total)
    I18n.t(:label_dcf_linked_count, linked: count, total: total)
  end

  it 'edits links, saves through the multipart form and shows them after a reload' do
    dcf_login
    edit(child)
    expect(js("document.getElementById('custom_field_form').enctype")).to eq('multipart/form-data')
    expect(page).to have_css('[data-dcf-ed-notice=orphans]')
    expect(page).to have_css('p[data-dcf-editor-required-warning]:not(.dcf-hidden) .icon-warning')
    if Redmine::VERSION::MAJOR >= 6
      expect(page).to have_css('p[data-dcf-editor-required-warning] svg', visible: :all)
    end
    expect(js("document.getElementById('custom_field_dependencies_json').value")).to eq('')
    expect(wants_warning).to be(false)
    germany = open_section('Germany')
    tick(germany, 'Lyon')
    expect(wants_warning).to be(true)
    expect(page).to have_css('p[data-dcf-editor-required-warning].dcf-hidden', visible: :all)
    germany.find('select[data-dcf-ed-default]').find('option[value=Lyon]').select_option
    expect(germany).to have_css('.dcf-dep-section__default', text: 'Lyon')
    shot('admin-editor-edited')
    save

    expect(page).to have_css('#flash_notice')
    expect(stored(child)).to eq([{ 'Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris], 'Germany' => %w[Lyon] },
                                 { 'Belgium' => 'Brussels', 'Germany' => 'Lyon' }])
    edit(child)
    expect(section('Germany')).to have_css('.dcf-dep-section__counts', text: linked(1, 4))
    expect(page).to have_no_css('[data-dcf-ed-notice=orphans]')
    expect(wants_warning).to be(false)
  end

  it 'rebuilds the sections live after a parent change and prunes on save' do
    other
    dcf_login
    edit(child)
    find("#custom_field_parent_custom_field_id option[value='#{other.id}']").select_option
    expect(page).to have_css("details.dcf-dep-section[data-dcf-ed-section='Spain']")
    expect(page).to have_css('[data-dcf-ed-notice=parent_changed]', text: '2')
    expect(page).to have_no_css("details.dcf-dep-section[data-dcf-ed-section='France']")
    shot('admin-editor-parent-changed')
    save

    expect(page).to have_css('#flash_notice')
    expect(stored(child)).to eq([{ 'Belgium' => %w[Antwerp Brussels] }, { 'Belgium' => 'Brussels' }])
  end

  it 'refuses a stale save from a second tab, shows the conflict panel and saves my version on the fresh base' do
    dcf_login
    edit(child)
    tick(open_section('Germany'), 'Paris')
    other_tab = open_new_window
    within_window(other_tab) do
      edit(child)
      belgium = open_section('Belgium')
      tick(belgium, 'Antwerp')
      tick(open_section('France'), 'Lyon')
      save
      expect(page).to have_css('#flash_notice')
    end
    other_tab.close
    current = { 'Belgium' => %w[Brussels], 'France' => %w[Paris Lyon] }
    expect(stored(child)[0]).to eq(current)
    save

    expect(page).to have_css('#errorExplanation')
    panel = find('.dcf-dep-editor__conflict[role=alert]')
    expect(panel).to have_text(I18n.t(:text_dcf_editor_conflict, only_mine: 2, only_current: 1))
    # core #icon-copy-source and createSVGIcon exist from 6.1 (UX-10)
    sprite = Gem::Version.new(version) >= Gem::Version.new('6.1')
    expect(panel).to have_css('svg.icon-svg', visible: :all, count: sprite ? 1 : 0)
    shot('admin-editor-conflict')
    expect(stored(child)[0]).to eq(current)
    panel.find('button[data-dcf-ed-use-mine]').click
    expect(page).to have_css('[data-dcf-ed-notice=mine_loaded]')
    save

    expect(page).to have_css('#flash_notice')
    expect(stored(child)[0]).to eq('Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris], 'Germany' => %w[Paris])
  end

  it 'blocks an oversize payload with the pre-check and keeps Save enabled' do
    dcf_login
    edit(child)
    js("DcfDependencyEditor.get(document.querySelector('[data-dcf-editor]')).config.maxPayload = 10")
    tick(open_section('Germany'), 'Lyon')
    save

    error = find('[data-dcf-ed-notice=too_large][role=alert]')
    expect(error).to have_text(I18n.t(:error_dcf_dependencies_too_large_to_send, size: 0, limit: 0).split(' (').first)
    expect(page).to have_current_path("/custom_fields/#{child.id}/edit")
    # rails-ujs disables data-disable-with buttons 13 ms after a submit event it sees.
    disabled = page.evaluate_async_script(<<~JS)
      var done = arguments[0];
      setTimeout(function () { done(document.querySelector('#custom_field_form input[name=commit]').disabled); }, 200);
    JS
    expect(disabled).to be(false)
    shot('admin-editor-precheck')
  end

  it 'pages 100 sections, filters them and checks all shown children including unrendered rows' do
    big_parent = dcf_list_field(values: (1..150).map { |i| format('Region %03d', i) }, name: 'Ed regions')
    children = (1..250).map { |i| format('Town %03d', i) }
    field = dcf_list_field(format: 'depending_list', values: children, parent: big_parent, name: 'Ed towns')
    dcf_login
    edit(field)
    expect(page).to have_css('details.dcf-dep-section', count: 100)
    find('button[data-dcf-ed-more-sections]').click
    expect(page).to have_css('details.dcf-dep-section', count: 150)
    find('input[data-dcf-ed-parent-filter]').fill_in(with: 'region 007')
    # 150 sections are replaced after the debounce; a slow browser needs more than the default wait
    expect(page).to have_css('details.dcf-dep-section', count: 1, wait: 10)
    region = open_section('Region 007')
    expect(region).to have_css('input[data-dcf-ed-child-key]', count: 200)
    region.find('button[data-dcf-ed-check-shown]').click
    expect(region).to have_css('.dcf-dep-section__counts', text: linked(250, 250))
    shot('admin-editor-lazy')
    save

    expect(page).to have_css('#flash_notice')
    expect(stored(field)[0]).to eq('Region 007' => children)
  end
end
