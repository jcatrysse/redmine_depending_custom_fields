# frozen_string_literal: true

require_relative '../rails_helper'

# WP-04 characterization: pins what the issue context menu patch and the wizard
# hook render today (0.0.16), including known gaps, before the refactor. Only
# WP-15 may change an expectation here, and only as a listed flip.
RSpec.describe 'Issue context menu (characterization)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }

  # Chain parent (list) -> child (depending_list) -> grandchild (depending_list).
  let(:parent) { dcf_list_field(name: 'Parent', values: %w[A B]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
  end
  let(:grandchild) do
    field = dcf_list_field(format: 'depending_list', name: 'Grandchild', values: %w[g1], parent: child)
    dcf_set_dependencies(field, value_dependencies: { 'a1' => %w[g1] })
  end

  # Pair enumeration parent -> depending_enumeration child.
  let(:enum_parent) { dcf_enum_field(name: 'EnumParent', names: %w[X Y]) }
  let(:enum_child) do
    field = dcf_enum_field(format: 'depending_enumeration', name: 'EnumChild', names: %w[x1 y1], parent: enum_parent)
    key = ->(cf, name) { cf.enumerations.detect { |e| e.name == name }.id.to_s }
    dcf_set_dependencies(field, value_dependencies: { key.call(enum_parent, 'X') => [key.call(field, 'x1')] })
  end

  let(:unrelated) { dcf_list_field(name: 'Unrelated', values: %w[U1 U2]) }
  let(:parentless) { dcf_list_field(format: 'depending_list', name: 'Parentless', values: %w[p1 p2]) }

  # A depending child whose parent is not enabled on the issue tracker.
  let(:offstage_parent) { dcf_list_field(name: 'OffstageParent', values: %w[O1]) }
  let(:offstage_child) do
    field = dcf_list_field(format: 'depending_list', name: 'OffstageChild', values: %w[o1], parent: offstage_parent)
    dcf_set_dependencies(field, value_dependencies: { 'O1' => %w[o1] })
  end

  let(:user_field) do
    field = IssueCustomField.new(name: 'ExtendedUser', field_format: 'extended_user', is_for_all: true)
    field.show_active = '1'
    field.save!
    field.reload
  end

  let(:fields) do
    [parent, child, grandchild, enum_parent, enum_child, unrelated, parentless,
     offstage_parent, offstage_child, user_field]
  end

  let(:issue) do
    created = dcf_real_issue(project, parent => 'A', child => 'a1', unrelated => 'U1')
    tracker = created.tracker
    (fields - [parent, child, unrelated, offstage_parent]).each { |f| tracker.custom_fields << f }
    created
  end

  def mapping_cache_key
    'depending_custom_fields/mapping'
  end

  def open_menu
    post '/issues/context_menu', params: { ids: [issue.id] }
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  # Core renders one <li class="folder <format>_cf cf_<id>"> per bulk-editable
  # custom field (context_menus/issues.html.erb, 5.1 to 7.0).
  def core_folder(menu, field)
    menu.at_css("li.folder.cf_#{field.id}")
  end

  def folder_links(folder)
    folder.css('ul li a').map { |a| [a.text.strip, CGI.unescape(a['href'].to_s)] }
  end

  # Ids of the fields in each data-level column of the wizard template.
  def wizard_levels(menu, parent_field)
    template = menu.at_css("template#cf-wizard-#{parent_field.id}")
    return nil unless template

    template.css('div.cf-col').map do |col|
      col.css('select').map { |s| s['name'][/\[(\d+)\]\z/, 1].to_i }
    end
  end

  # What core itself would offer before the patch filters: editable, single
  # value, bulk-edit capable fields with at least one option.
  def core_candidates
    fresh = Issue.find(issue.id)
    fresh.editable_custom_fields.reject(&:multiple?)
         .select { |f| f.format.bulk_edit_supported && f.possible_values_options([fresh.project]).present? }
  end

  before do
    Rails.cache.delete(mapping_cache_key)
    allow(User).to receive(:current).and_return(dcf_admin)
    fields
    issue
  end

  after { Rails.cache.delete(mapping_cache_key) }

  describe 'routing to the patched controller' do
    it 'serves /issues/context_menu from a controller that has the patch prepended' do
      open_menu

      ancestors = controller.class.ancestors
      patch_index = ancestors.index(RedmineDependingCustomFields::Patches::ContextMenusControllerPatch)
      expect(patch_index).not_to be_nil
      expect(patch_index).to be < ancestors.index(controller.class)
      # 5.x/6.x: ContextMenusController#issues; 7.0: ContextMenus::IssuesController#index.
      expect([%w[context_menus issues], %w[context_menus/issues index]])
        .to include([controller.controller_path, controller.action_name])
    end
  end

  describe 'core custom field submenus' do
    it 'would be offered by core for every field of the fixture except the offstage parent' do
      expect(core_candidates.map(&:id)).to match_array((fields - [offstage_parent]).map(&:id))
    end

    it 'keeps an unrelated list field with its values and the none entry' do
      folder = core_folder(open_menu, unrelated)

      expect(folder).not_to be_nil
      expect(folder.css('ul li a').map { |a| a.text.strip }).to eq(%w[U1 U2 none])
    end

    it 'removes the list parent, the depending child and the depending grandchild' do
      menu = open_menu

      expect(core_folder(menu, parent)).to be_nil
      expect(core_folder(menu, child)).to be_nil
      expect(core_folder(menu, grandchild)).to be_nil
    end

    it 'removes the enumeration parent and its depending_enumeration child' do
      menu = open_menu

      expect(core_folder(menu, enum_parent)).to be_nil
      expect(core_folder(menu, enum_child)).to be_nil
    end

    it 'keeps a depending_list field that has no parent' do
      expect(core_folder(open_menu, parentless)).not_to be_nil
    end

    # Gap: the child is hidden from core, but the wizard only offers parents
    # that are available on the issue, so the child is editable nowhere here.
    it 'removes a depending child whose parent is not on the issue tracker, leaving it in no menu entry' do
      menu = open_menu

      expect(core_folder(menu, offstage_child)).to be_nil
      expect(menu.at_css("li.cf-parent[data-parent-id='#{offstage_parent.id}']")).to be_nil
      expect(menu.css("select[name='issue[custom_field_values][#{offstage_child.id}]']")).to be_empty
    end
  end

  describe 'extended_user submenu' do
    it 'drops the __group_* status headers but keeps the folder and the user entries' do
      offered = user_field.format.possible_values_options(user_field).map { |o| o[1].to_s }
      expect(offered).to include('__group_active__')

      folder = core_folder(open_menu, user_field)

      expect(folder).not_to be_nil
      links = folder_links(folder)
      expect(links.map(&:first)).to eq(['<< me >>', dcf_admin.name, 'none'])
      expect(links.map(&:last).grep(/__group_/)).to be_empty
    end
  end

  describe 'wizard hook output' do
    it 'appends one cf-parent folder per top-level parent with a template of the field chain by level' do
      menu = open_menu

      wizard_parents = menu.css('li.folder.cf-parent').map { |li| li['data-parent-id'].to_i }
      expect(wizard_parents).to match_array([parent.id, enum_parent.id])
      entry = menu.at_css("li.folder.cf-parent[data-parent-id='#{parent.id}']")
      expect(entry['data-issue-ids']).to eq(issue.id.to_s)
      expect(entry.at_css('a.submenu').text.strip).to eq('Parent')

      expect(wizard_levels(menu, parent)).to eq([[parent.id], [child.id], [grandchild.id]])
      expect(wizard_levels(menu, enum_parent)).to eq([[enum_parent.id], [enum_child.id]])
      expect(wizard_levels(menu, child)).to be_nil
    end
  end

  describe 'failure handling' do
    # The test cache store is a null store, so every fetch rebuilds the
    # mapping. The patch filters before the view renders, so the first build of
    # the request is the patch's; later builds (wizard hook) succeed.
    it 'rescues and logs a failure inside the filtering and renders the menu unfiltered' do
      builds = 0
      allow(RedmineDependingCustomFields::MappingBuilder).to receive(:build).and_wrap_original do |original|
        builds += 1
        raise 'mapping boom' if builds == 1

        original.call
      end
      allow(Rails.logger).to receive(:warn).and_call_original

      menu = open_menu

      expect(builds).to be > 1
      expect(Rails.logger).to have_received(:warn)
        .with('[DCF] context menu filtering failed: RuntimeError - mapping boom').once
      # Nothing was filtered: the depending fields and the group header stay.
      expect(core_folder(menu, parent)).not_to be_nil
      expect(core_folder(menu, child)).not_to be_nil
      expect(folder_links(core_folder(menu, user_field)).map(&:last).grep(/__group_active__/)).not_to be_empty
      # The hook builds its own mapping, so the wizard still renders.
      expect(wizard_levels(menu, parent)).to eq([[parent.id], [child.id], [grandchild.id]])
    end
  end
end
