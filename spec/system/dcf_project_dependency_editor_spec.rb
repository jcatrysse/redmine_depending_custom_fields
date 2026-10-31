# frozen_string_literal: true

require_relative '../rails_helper'

# Opt-in (DCF_SYSTEM_SPECS=1). WP-27 (quality 5.4 scenario 6, gap 1, gap 14,
# UD-16, UD-17): the project dependency page on the shared editor in a real
# browser on 5.1 and 7.0: Save served disabled and enabled by the editor, no
# unload prompt on an untouched page, a failed save re-rendered dirty from
# data-dcf-editor-mapping with a blank hidden input, a stale save across two
# windows with the conflict panel, and a CSV import through the WP-26 panel
# saved and audited with source import. Screenshots (the scope banner icon
# included) go to tmp/capybara/dcf/wp-27/.
RSpec.describe 'Project dependency editor in the browser (WP-27)', type: :system do
  fixtures :users

  let(:version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }
  let(:project) { dcf_create_project(name: 'Editor project') }
  let(:parent) { dcf_list_field(values: %w[Belgium France Germany], name: 'Pr country') }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', values: %w[Antwerp Brussels Paris Lyon], parent: parent,
                           name: 'Pr city')
    dcf_set_dependencies(field, value_dependencies: { 'Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris] },
                                default_value_dependencies: { 'Belgium' => 'Brussels' })
  end
  let(:path) { "/projects/#{project.identifier}/custom_field_configuration/fields/#{child.id}/dependencies" }

  def shot(name, anchor = 'fieldset.dcf-dep-editor')
    page.execute_script('var e = document.querySelector(arguments[0]); if (e) e.scrollIntoView();', anchor)
    dir = Rails.root.join('tmp', 'capybara', 'dcf', 'wp-27')
    FileUtils.mkdir_p(dir)
    file = dir.join("#{name}-#{version}.png").to_s
    page.driver.browser.save_screenshot(file)
    expect(File.size(file)).to be > 0
  end

  def js(script)
    page.evaluate_script(script)
  end

  def editor_js(expression)
    js("DcfDependencyEditor.get(document.querySelector('[data-dcf-editor]')).#{expression}")
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

  def edit
    visit path
    expect(page).to have_css('fieldset.dcf-dep-editor .dcf-dep-editor__sections')
  end

  def save
    find('form input[type=submit][data-dcf-editor-submit]').click
  end

  def last_row
    RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: child.id).order(:id).last
  end

  # The page as served (before any script ran), parsed by the browser.
  def served(selector, property)
    page.evaluate_async_script(<<~JS, selector, property)
      var done = arguments[arguments.length - 1];
      var selector = arguments[0], property = arguments[1];
      fetch(location.href, { credentials: 'same-origin' }).then(function (r) { return r.text(); }).then(function (html) {
        var node = new DOMParser().parseFromString(html, 'text/html').querySelector(selector);
        done(node ? node[property] : 'missing');
      });
    JS
  end

  it 'serves Save disabled, enables it after init, keeps an untouched page quiet and shows the scope banner' do
    dcf_login
    edit
    expect(served('form input[data-dcf-editor-submit]', 'disabled')).to be(true)
    expect(served('input[name=dependencies_json]', 'value')).to eq('')
    expect(find('form input[type=submit][data-dcf-editor-submit]').disabled?).to be(false)
    expect(js("document.querySelector('form[enctype=\"multipart/form-data\"] fieldset[data-dcf-editor]') !== null"))
      .to be(true)
    expect(editor_js('wantsWarning()')).to be(false)
    banner = find('div.flash.warning', text: I18n.t(:text_global_field_warning))
    expect(banner).to have_css('svg', visible: :all, count: Redmine::VERSION::MAJOR >= 6 ? 1 : 0)
    if Redmine::VERSION::MAJOR < 6
      expect(js("getComputedStyle(document.querySelector('div.flash.warning')).backgroundImage")).not_to eq('none')
    end
    shot('project-editor', 'div.flash.warning')
    tick(open_section('Germany'), 'Lyon')
    expect(editor_js('wantsWarning()')).to be(true)
  end

  it 're-renders a failed save dirty from the posted mapping with a blank hidden input, then saves it corrected' do
    dcf_login
    edit
    tick(open_section('Germany'), 'Lyon')
    # The state hash covers the child, not the parent's values, so this gives
    # a 422 for an unknown parent key, not a 409.
    parent.update!(possible_values: %w[Belgium France])
    save

    expect(page).to have_css('#flash_error', text: I18n.t(:error_invalid_dependency))
    expect(page).to have_css('fieldset[data-dcf-editor][data-dcf-editor-dirty="1"]')
    # A hidden input's value attribute follows the editor's writes, so the
    # blank served input is pinned by the request specs (T-DEPJ-6, T-DEPJ-14).
    expect(editor_js('dirty')).to be(true)
    expect(editor_js('wantsWarning()')).to be(true)
    mapping = JSON.parse(find('fieldset[data-dcf-editor]')['data-dcf-editor-mapping'])
    expect(mapping['value_dependencies']).to include('Germany' => %w[Lyon])
    # Germany is no parent value any more: the editor reports it as an orphan.
    expect(page).to have_css('[data-dcf-ed-notice=orphans]')
    shot('project-editor-failed-save', '#flash_error')
    expect(stored(child)[0]).to eq('Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris])

    tick(open_section('France'), 'Lyon')
    save
    expect(page).to have_css('#flash_notice', text: I18n.t(:notice_dependencies_saved))
    expect(stored(child)[0]).to eq('Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris Lyon])
  end

  it 'refuses a stale save from a second window with the conflict panel and saves my version on request (UD-17)' do
    dcf_login
    edit
    tick(open_section('Germany'), 'Paris')
    other = open_new_window
    within_window(other) do
      edit
      tick(open_section('Belgium'), 'Antwerp')
      tick(open_section('France'), 'Lyon')
      save
      expect(page).to have_css('#flash_notice')
    end
    other.close
    current = { 'Belgium' => %w[Brussels], 'France' => %w[Paris Lyon] }
    expect(stored(child)[0]).to eq(current)
    save

    expect(page).to have_css('#flash_error', text: I18n.t(:error_stale_edit))
    panel = find('.dcf-dep-editor__conflict[role=alert]')
    expect(panel).to have_text(I18n.t(:text_dcf_editor_conflict, only_mine: 2, only_current: 1))
    shot('project-editor-conflict', '.dcf-dep-editor__conflict')
    expect(stored(child)[0]).to eq(current)
    panel.find('button[data-dcf-ed-use-mine]').click
    expect(page).to have_css('[data-dcf-ed-notice=mine_loaded]')
    save

    expect(page).to have_css('#flash_notice')
    expect(stored(child)[0]).to eq('Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris], 'Germany' => %w[Paris])
  end

  # Gap 14, WP-26 open input: the import panel in project mode, end to end.
  it 'imports pasted links through the import panel and audits the save with source import, mode and rows' do
    dcf_login
    edit
    panel = find('details.dcf-dep-editor__import')
    panel.find('summary').click
    expect(panel).to have_no_css('input[data-dcf-ed-import-add-missing]')
    panel.find('textarea[data-dcf-ed-import-text]').set("Germany,Lyon\nFrance,Lyon")
    panel.find('button[data-dcf-ed-import-preview]').click
    expect(panel).to have_css('li[data-dcf-ed-summary=to_add]', text: I18n.t(:text_dcf_import_to_add, count: 2))
    shot('project-import-preview', '.dcf-dep-editor__preview')
    panel.find('button[data-dcf-ed-import-apply]').click
    expect(page).to have_css('[data-dcf-ed-notice=import_applied]',
                             text: I18n.t(:text_dcf_import_applied, added: 2, removed: 0))
    rows = RedmineDependingCustomFields::ConfigAuditEvent.count
    save

    expect(page).to have_css('#flash_notice', text: I18n.t(:notice_dependencies_saved))
    expect(stored(child)[0]).to eq('Belgium' => %w[Antwerp Brussels], 'France' => %w[Paris Lyon],
                                   'Germany' => %w[Lyon])
    expect(RedmineDependingCustomFields::ConfigAuditEvent.count).to eq(rows + 1)
    after = JSON.parse(last_row.after_value)
    expect(after.values_at('source', 'import', 'added')).to eq(['import', { 'mode' => 'merge', 'rows' => 2 }, 2])
    expect(last_row.changes_summary).to start_with('Updated dependency mapping (import, merge, 2 rows): +2/-0 links')
  end
end
