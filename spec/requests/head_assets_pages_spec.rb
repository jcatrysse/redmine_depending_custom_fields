# frozen_string_literal: true

require_relative '../rails_helper'

# WP-18 (SD-15, PC-37, frontend rows X8 and X9, quality G3 'No inline
# script'): no page carries a dependency mapping any more. Every base-layout
# page, the anonymous login page included, gets only the dcf-i18n meta tag
# (texts of the current locale), the runtime, the wizard script and the
# stylesheet; parent data reaches a page only per rendered field (WP-16).
# Core renders inline scripts of its own on the issue pages, so the inline
# check targets plugin content.
RSpec.describe 'Head assets on every page (WP-18)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:tag) { "Sd15#{SecureRandom.hex(3)}" }
  let(:plugin_text) { /DependingCustomField|ContextMenuWizard|data-dcf-|dcf-i18n/ }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  # A pair whose parent is hidden from non-admins, with sentinel values,
  # mapping keys and defaults that must appear on no page below (core may
  # list the field names, for example in the column options of My page).
  def secret_pair
    parent = dcf_list_field(values: %W[#{tag}P1 #{tag}P2], name: 'Head parent')
    parent.update!(visible: false, role_ids: [dcf_create_role.id])
    child = dcf_list_field(format: 'depending_list', values: %W[#{tag}C1 #{tag}C2], parent: parent, name: 'Head child')
    dcf_set_dependencies(child, value_dependencies: { "#{tag}P1" => %W[#{tag}C1], "#{tag}P2" => %W[#{tag}C2] },
                                default_value_dependencies: { "#{tag}P1" => "#{tag}C1" })
    [parent, child]
  end

  def head_payload(page)
    JSON.parse(page.at_css("head meta[name='dcf-i18n']")['content'])
  end

  def expect_clean_page(label)
    expect(response).to have_http_status(200), label
    page = Nokogiri::HTML(response.body)
    srcs = page.css('head script[src]').pluck('src')
    expect(head_payload(page).keys).to eq(RedmineDependingCustomFields::ClientConfig::I18N.keys), label
    expect(srcs.grep(%r{/depending_custom_fields(-\h+)?\.js}).size).to eq(1), label
    expect(srcs.grep(%r{/context_menu_wizard(-\h+)?\.js}).size).to eq(1), label
    expect(srcs.grep(/depending_custom_fields_legacy/)).to eq([]), label
    %w[DependingCustomFieldData ContextMenuWizardConfig data-dcf-map data-dcf-parent].each do |needle|
      expect(response.body).not_to include(needle), "#{label}: #{needle}"
    end
    expect(response.body).not_to include(tag), label
    page
  end

  it 'gives the anonymous login and registration pages only the meta tag and the assets' do
    secret_pair
    allow(Setting).to receive(:self_registration?).and_return(true)
    as(User.anonymous)

    get '/login'
    expect_clean_page('/login')
    get '/account/register'
    expect_clean_page('/account/register')
  end

  it 'gives member pages without depending controls no mapping, in the language of the user' do
    secret_pair
    role = dcf_create_role(permissions: [:view_issues])
    member = dcf_create_user("sd15-#{SecureRandom.hex(3)}")
    member.update_column(:language, 'de')
    dcf_add_member(member, project, role)
    as(member)

    get '/projects'
    page = expect_clean_page('/projects')
    expect(head_payload(page)['saveFailed']).to eq(I18n.t(:error_save_failed, locale: :de))
    get '/my/page'
    expect_clean_page('/my/page')
  end

  it 'adds no inline script to the issue pages, the bulk edit form and the context menu' do
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
    issue = dcf_real_issue(project.reload, parent => 'A', child => 'a1')
    as(dcf_admin)

    { "/issues/#{issue.id}/edit" => :get, "/projects/#{project.identifier}/issues/new" => :get,
      '/issues/bulk_edit' => :get, '/issues/context_menu' => :post }.each do |path, method|
      send(method, path, params: path.include?('bulk') || path.include?('context') ? { ids: [issue.id] } : {})
      expect(response).to have_http_status(200), path
      page = Nokogiri::HTML(response.body)
      inline = page.css('script:not([src])').map(&:text)
      expect(inline.grep(plugin_text)).to eq([]), path
      expect(response.body).not_to include('DependingCustomFieldData'), path
      expect(response.body).not_to include('ContextMenuWizardConfig'), path
    end
  end
end
