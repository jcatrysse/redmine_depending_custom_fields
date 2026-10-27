# frozen_string_literal: true

require_relative '../rails_helper'

# WP-18 (server design 2.4, quality H1 to H4): the head hook renders the
# i18n meta tag, the runtime, the wizard script and the stylesheet, in this
# order; no inline script, no database access, no Rails.cache. Rewritten:
# the WP-17 and earlier examples pinned the legacy script and the inline
# window.DependingCustomFieldData global (deleted, SD-15).
RSpec.describe RedmineDependingCustomFields::Hooks::ViewLayoutsBaseHtmlHeadHook do
  include DcfFormatCharacterization

  fixtures :users

  let(:hook) { described_class.send(:new) }
  let(:client) { RedmineDependingCustomFields::ClientConfig }

  def render(context = {})
    hook.view_layouts_base_html_head(context)
  end

  def fragment(html)
    Nokogiri::HTML5.fragment(html)
  end

  def meta_payload(html)
    JSON.parse(fragment(html).at_css("meta[name='dcf-i18n']")['content'])
  end

  # A digest (6.x/7.0) or an asset id (5.1) is only added for a file that exists.
  def asset_pattern(name, ext)
    /#{name}(-[0-9a-f]{7,}\.#{ext}|\.#{ext}\?\d+)\z/
  end

  it 'renders exactly the meta tag, the runtime, the wizard script and the stylesheet, in this order' do
    html = render
    nodes = fragment(html).element_children

    expect(nodes.map(&:name)).to eq(%w[meta script script link])
    srcs = fragment(html).css('script[src]').pluck('src')
    runtime = srcs.grep(asset_pattern('depending_custom_fields', 'js'))
    wizard = srcs.grep(asset_pattern('context_menu_wizard', 'js'))
    css = fragment(html).css('link[rel=stylesheet]').pluck('href')
    expect([runtime.size, wizard.size, srcs.size]).to eq([1, 1, 2])
    expect(css.size).to eq(1)
    expect(css.first).to match(asset_pattern('depending_custom_fields', 'css'))
    needles = ['name="dcf-i18n"', runtime.first, wizard.first, '<link']
    positions = needles.map { |needle| html.index(needle) }
    expect(positions).to all(be_an(Integer))
    expect(positions).to eq(positions.sort)
  end

  it 'adds no inline script, no async or defer, and names neither the legacy script nor the removed globals' do
    html = render
    scripts = fragment(html).css('script')

    expect(fragment(html).css('script:not([src])')).to be_empty
    expect(scripts.map { |s| [s['async'], s['defer']] }.flatten.compact).to eq([])
    expect(html).not_to include('depending_custom_fields_legacy')
    expect(html).not_to include('DependingCustomFieldData')
    expect(html).not_to include('ContextMenuWizardConfig')
  end

  it 'writes the flat payload of ClientConfig as JSON in every locale' do
    %w[de en fr nl].each do |locale|
      I18n.with_locale(locale) do
        payload = meta_payload(render)
        expect(payload).to eq(client.payload), locale
        expect(payload.keys).to eq(client::I18N.keys), locale
        expect(payload.values).to all(be_a(String).and(satisfy { |v| !v.match?(/translation missing/i) }))
      end
    end
    en = I18n.with_locale(:en) { meta_payload(render) }
    de = I18n.with_locale(:de) { meta_payload(render) }
    differing = client::I18N.keys - %w[liveMessage]
    expect(differing.select { |key| en[key] == de[key] }).to eq([])
  end

  it 'escapes the meta content exactly once' do
    text = %(<b>"x" & 'y'</b></script>)
    allow(I18n).to receive(:t).and_call_original
    allow(I18n).to receive(:t).with(:text_dcf_hint_no_options).and_return(text)
    html = render

    expect(meta_payload(html)['noOptions']).to eq(text)
    expect(html).not_to include('</b></script>')
    expect(html).not_to include('<b>')
    expect(html).not_to include('&amp;lt;')
    expect(html.scan('<script').size).to eq(2)
  end

  it 'runs no query and calls no Rails.cache method' do
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
    calls = []
    [:fetch, :read, :write, :delete, :delete_matched, :exist?, :fetch_multi, :read_multi, :write_multi,
     :clear].each do |method|
      allow(Rails.cache).to receive(method) { |*args| calls << [method, args.first] }
    end
    render

    expect(dcf_count_queries { render }).to eq(0)
    expect(calls).to eq([])
  end

  it 'renders the same bytes for every user and before and after depending fields exist (SD-15)' do
    as = ->(user) { allow(User).to receive(:current).and_return(user) }
    as.call(User.anonymous)
    before = render
    parent = dcf_list_field(values: %w[SdSecretP1 SdSecretP2])
    parent.update!(visible: false, role_ids: [Role.create!(name: "Nobody-#{SecureRandom.hex(3)}").id])
    child = dcf_list_field(format: 'depending_list', values: %w[SdSecretC1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'SdSecretP1' => %w[SdSecretC1] },
                                default_value_dependencies: { 'SdSecretP1' => 'SdSecretC1' })
    after_anonymous = render
    as.call(dcf_admin)
    after_admin = render

    expect(after_anonymous).to eq(before)
    expect(after_admin).to eq(before)
    expect(before).not_to include('SdSecret')
  end

  it 'keeps accepting a context and a call without arguments' do
    expect(render(controller: nil)).to eq(render)
    expect(hook.view_layouts_base_html_head).to eq(render)
  end

  # WP-25 (editor design 5.1, quality H3): on the two editor controllers the
  # editor model, the editor script and the editor stylesheet follow the base
  # assets, once each; nowhere else.
  describe 'editor assets' do
    let(:editor_names) do
      [asset_pattern('dcf_dependency_editor_model', 'js'), asset_pattern('dcf_dependency_editor', 'js')]
    end

    [CustomFieldsController, ProjectCustomFieldConfigurationController].each do |controller_class|
      it "adds the model, the editor script and the editor stylesheet after the base assets on #{controller_class}" do
        html = render(controller: controller_class.new)
        nodes = fragment(html).element_children
        srcs = fragment(html).css('script[src]').pluck('src')
        hrefs = fragment(html).css('link[rel=stylesheet]').pluck('href')

        expect(nodes.map(&:name)).to eq(%w[meta script script link script script link])
        expect(srcs.size).to eq(4)
        model = srcs.grep(editor_names[0])
        editor = srcs.grep(editor_names[1])
        expect([model.size, editor.size]).to eq([1, 1])
        expect(hrefs.size).to eq(2)
        expect(hrefs.last).to match(asset_pattern('dcf_dependency_editor', 'css'))
        needles = ['name="dcf-i18n"', srcs[0], srcs[1], hrefs.first, model.first, editor.first, hrefs.last]
        positions = needles.map { |needle| html.index(needle) }
        expect(positions).to all(be_an(Integer))
        expect(positions).to eq(positions.sort)
        expect(fragment(html).css('script:not([src])')).to be_empty
        # invariance form (R16): the editor branch adds no query
        expect(dcf_count_queries { render(controller: controller_class.new) }).to eq(dcf_count_queries { render })
      end
    end

    it 'adds nothing on an issue page, without a controller or for a subclass' do
      base = render
      [IssuesController.new, nil, Class.new(CustomFieldsController).new].each do |controller|
        html = render(controller: controller)
        expect(html).to eq(base)
        expect(html).not_to include('dcf_dependency_editor')
      end
    end
  end
end
