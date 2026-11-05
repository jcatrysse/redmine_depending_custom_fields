# frozen_string_literal: true

require_relative '../rails_helper'

# WP-38 (SD-22, owner decision of 2026-11-03): the WP-09b rule on time
# entries, with the same result on every supported core. Core 6.1 and 7.0
# validate only the values User.current can see
# (TimeEntry#validate_custom_field_values); 5.1 and 6.0 validate every value
# (acts_as_customizable), but their TimeEntry#safe_attributes= (the time
# entry form, bulk edit, the context menu and the REST API) first drops the
# values the user cannot see. On a time entry editable means visible, so a
# depending child the user cannot edit is one the user cannot see: it is
# judged by NonEditableDependencies only, never by the format under its own
# name. A parent change is refused while such a child keeps a value the new
# parent value does not allow: one message on the parent field, or on base
# when the parent is hidden too or did not change; the child is never named,
# its value never shown, and nothing is cleared. A child the user can see and
# an administrator keep core's 'is invalid' under the child's name, once.
#
# Kit: parent values A, B, C, D; A allows the secret value and a2, B allows
# b1, C allows nothing, D allows the secret value. Entries store A with the
# secret value unless noted.
RSpec.describe 'Time entries with a depending child the user cannot see (WP-38, SD-22)', type: :request do
  include DcfFormatCharacterization

  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:hidden_message) { I18n.t('activerecord.errors.messages.dcf_hidden_child_conflict') }
  let(:base_message) { I18n.t('error_dcf_hidden_child_conflict') }
  let(:hidden_texts) do
    { 'en' => 'cannot be changed because a dependent field you cannot see has a value that does not match the ' \
              'new value',
      'de' => 'kann nicht geändert werden, weil ein abhängiges Feld, das Sie nicht sehen können, einen Wert hat, ' \
              'der nicht zum neuen Wert passt' }
  end
  let(:base_texts) do
    { 'en' => 'This change cannot be saved because a dependent field you cannot see has a value that the ' \
              'change does not allow.',
      'de' => 'Diese Änderung kann nicht gespeichert werden, weil ein abhängiges Feld, das Sie nicht sehen können, ' \
              'einen Wert hat, den die Änderung nicht zulässt.' }
  end
  let(:secret) { "Qz#{SecureRandom.hex(4)}secret" }
  let(:project) do
    record = dcf_create_project
    record.enabled_module_names = %w[issue_tracking time_tracking]
    record
  end
  let(:role) do
    dcf_create_role(permissions: [:view_time_entries, :log_time, :edit_time_entries, :edit_own_time_entries])
  end
  let(:other_role) { dcf_create_role(permissions: [:view_time_entries]) }
  let(:user) do
    member = dcf_create_user("te-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:activity) { TimeEntryActivity.create!(name: "Act-#{SecureRandom.hex(3)}", active: true) }
  let(:kit) { build_pair }
  let(:parent) { kit.first }
  let(:child) { kit.last }
  let(:other) { dcf_list_field(values: %w[X Y], type: TimeEntryCustomField) }

  before { allow(User).to receive(:current).and_return(user) }

  def patch_module
    RedmineDependingCustomFields::Patches::TimeEntryValidationPatch
  end

  # +kind+ :list (values stored as names) or :enum (enumeration ids).
  def build_pair(kind: :list, parent: nil, multiple: false)
    hex = SecureRandom.hex(4)
    names = [secret, 'a2', 'b1', 'b2']
    if kind == :list
      parent ||= dcf_list_field(values: %w[A B C D], type: TimeEntryCustomField, name: "Parent#{hex}")
      child = dcf_list_field(format: 'depending_list', values: names, parent: parent, type: TimeEntryCustomField,
                             multiple: multiple, name: "Child#{hex}")
    else
      parent ||= dcf_enum_field(names: %w[A B C D], type: TimeEntryCustomField, name: "Parent#{hex}")
      child = dcf_enum_field(format: 'depending_enumeration', names: names, parent: parent,
                             type: TimeEntryCustomField, name: "Child#{hex}")
      child.update!(multiple: true) if multiple
    end
    links = { kit_key(parent, 'A') => [kit_key(child, secret), kit_key(child, 'a2')],
              kit_key(parent, 'B') => [kit_key(child, 'b1')],
              kit_key(parent, 'D') => [kit_key(child, secret)] }
    [parent, dcf_set_dependencies(child, value_dependencies: links)]
  end

  def hide(field)
    field.update!(visible: false, role_ids: [other_role.id])
    field
  end

  def keys(values)
    values.to_h { |f, names| [f.id.to_s, kit_value(f, names)] }
  end

  # A persisted entry of +user+ holding +values+ (field => name or names),
  # stored without validation so legacy combinations can be set up. Reloaded.
  def stored_entry(values = nil)
    values ||= { parent => 'A', child => secret }
    entry = TimeEntry.new(project: project, user: user, author: user, spent_on: Date.new(2026, 1, 1), hours: 1,
                          activity: activity)
    entry.custom_field_values = keys(values)
    entry.save!(validate: false)
    TimeEntry.find(entry.id)
  end

  # A direct assignment (a script or another plugin): every value stays in
  # custom_field_values, so core 5.1 and 6.0 also validate the hidden one.
  def assign(entry, values)
    entry = TimeEntry.find(entry.id)
    entry.custom_field_values = keys(values)
    entry
  end

  # What the time entry paths do: safe_attributes= for the user. Core 5.1 and
  # 6.0 drop the values the user cannot see here, 6.1 and 7.0 keep them.
  def change(entry, values, by: user)
    entry = TimeEntry.find(entry.id)
    entry.send(:safe_attributes=, { 'custom_field_values' => keys(values) }, by)
    entry
  end

  def stored(record, field)
    record.class.find(record.id).custom_field_value(field)
  end

  def leaks?(text, field)
    text.include?(field.name) || text.include?(secret)
  end

  def json_headers
    { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def error_items
    doc.css('#errorExplanation li').map { |li| li.text.squish }
  end

  # Exactly one error: +message+ on +attribute+, nothing else.
  def expect_only(record, attribute, message)
    expect(record.errors.attribute_names.map(&:to_s)).to eq([attribute.to_s])
    expect(record.errors[attribute]).to eq([message])
  end

  describe 'patch registration' do
    it 'prepends the check on TimeEntry before the validate_custom_field_values core defines, once' do
      expect(TimeEntry.ancestors.index(patch_module)).to be < TimeEntry.ancestors.index(TimeEntry)
      method = TimeEntry.instance_method(:validate_custom_field_values)
      expect(method.owner).to eq(patch_module)
      # 6.1 and 7.0 define it in TimeEntry, 5.1 and 6.0 inherit it from acts_as_customizable.
      expect([TimeEntry, Redmine::Acts::Customizable::InstanceMethods]).to include(method.super_method.owner)
      expect(TimeEntry._validate_callbacks.count { |c| c.filter == :validate_custom_field_values }).to eq(1)
    end

    it 'decides by the values core judged, never by the Redmine version' do
      %w[lib/redmine_depending_custom_fields/patches/time_entry_validation_patch.rb
         lib/redmine_depending_custom_fields/non_editable_dependencies.rb
         lib/redmine_depending_custom_fields/depending_format_methods.rb].each do |path|
        source = File.read(File.expand_path("../../#{path}", __dir__))
        expect(source).not_to match(/Redmine::VERSION|VERSION::(MAJOR|MINOR)/), path
      end
    end
  end

  describe 'a parent change while a hidden child holds a value the new parent value does not allow' do
    before { hide(child) }

    it 'is refused on the parent field without naming the child, in en and de (direct assignment)' do
      hidden_texts.each do |locale, text|
        I18n.with_locale(locale) do
          entry = assign(stored_entry, parent => 'B')
          expect(entry.visible_custom_field_values(user).map(&:custom_field_id)).not_to include(child.id)
          expect(entry.save).to be(false), locale
          expect_only(entry, parent.name, text)
          expect(entry.errors.full_messages).to eq(["#{parent.name} #{text}"]), locale
          expect(entry.errors.details.values.flatten.map { |d| d[:error].to_s }.join).not_to include(secret)
          expect(entry.custom_field_value(child)).to eq(secret)
          expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
        end
      end
    end

    it 'is refused the same way through safe_attributes= (form, bulk edit, context menu, REST API)' do
      hidden_texts.each do |locale, text|
        I18n.with_locale(locale) do
          entry = change(stored_entry, { parent => 'B' })
          expect(entry.save).to be(false), locale
          expect_only(entry, parent.name, text)
          expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
        end
      end
    end

    it 'is refused for an enumeration child and for a multiple child holding the secret value and a2' do
      enum_parent, enum_child = build_pair(kind: :enum)
      hide(enum_child)
      multi = hide(build_pair(parent: parent, multiple: true).last)
      entry = stored_entry(parent => 'A', multi => [secret, 'a2'], enum_parent => 'A', enum_child => secret)
      expect(Array(stored(entry, multi))).to match_array([secret, 'a2'])
      changed = { parent => 'B', enum_parent => 'B' }
      [assign(entry, changed), change(entry, changed)].each do |record|
        expect(record.valid?).to be(false)
        expect(record.errors.full_messages)
          .to contain_exactly("#{parent.name} #{hidden_message}", "#{enum_parent.name} #{hidden_message}")
      end
    end

    it 'gives one parent message for several hidden children of the same parent' do
      second = hide(build_pair(parent: parent).last)
      entry = stored_entry(parent => 'A', child => secret, second => 'a2')
      [assign(entry, parent => 'B'), change(entry, { parent => 'B' })].each do |record|
        expect(record.valid?).to be(false)
        expect(record.errors.full_messages).to eq(["#{parent.name} #{hidden_message}"])
      end
    end

    it 'saves a parent change to a value that allows the hidden child (A to D)' do
      entry = assign(stored_entry, parent => 'D')
      expect(entry.save).to be(true), entry.errors.full_messages.inspect
      expect([stored(entry, parent), stored(entry, child)]).to eq(['D', secret])
      expect(change(stored_entry, { parent => 'D' }).valid?).to be(true)
    end
  end

  describe 'tolerance while the parent is unchanged (UD-04)' do
    before { hide(child) }

    it 'saves a change of another field while a hidden child holds a legacy value' do
      entry = stored_entry(parent => 'A', child => 'b1', other => 'X')
      assigned = assign(entry, other => 'Y')
      expect(assigned.save).to be(true), assigned.errors.full_messages.inspect
      expect([stored(entry, other), stored(entry, child)]).to eq(%w[Y b1])
      expect(change(entry, { other => 'X' }).valid?).to be(true)
      unrelated = TimeEntry.find(entry.id)
      unrelated.safe_attributes = { 'hours' => '2', 'comments' => 'later' }
      expect(unrelated.valid?).to be(true)
    end

    it 'puts the message on base for a new value of a hidden child that its unchanged parent does not allow' do
      base_texts.each do |locale, text|
        I18n.with_locale(locale) do
          entry = assign(stored_entry, child => 'b1')
          expect(entry.save).to be(false), locale
          expect_only(entry, :base, text)
          expect(stored(entry, child)).to eq(secret)
        end
      end
    end

    it 'refuses a new entry whose hidden child has a stale default under a blank parent, on base' do
      child.update_column(:default_value, secret)
      entry = TimeEntry.new(project: project, user: user, author: user, spent_on: Date.new(2026, 1, 2), hours: 1,
                            activity: activity)
      expect(entry.custom_field_value(child)).to eq(secret)
      expect(entry.valid?).to be(false)
      expect_only(entry, :base, base_message)
      entry.custom_field_values = keys(parent => 'A')
      expect(entry.save).to be(true), entry.errors.full_messages.inspect
      expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
    end
  end

  describe 'placement' do
    it 'puts the message on base when the parent is hidden too, naming neither field' do
      hide(child)
      hide(parent)
      base_texts.each do |locale, text|
        I18n.with_locale(locale) do
          entry = assign(stored_entry, parent => 'B')
          expect(entry.valid?).to be(false), locale
          expect_only(entry, :base, text)
          expect(entry.errors.full_messages.join).not_to include(parent.name)
          expect(leaks?(entry.errors.full_messages.join, child)).to be(false)
        end
      end
    end

    it 'leaves a child the user can see to core: is invalid under its name, once, nothing on the parent' do
      [assign(stored_entry, parent => 'B'), change(stored_entry, { parent => 'B' })].each do |entry|
        expect(entry.valid?).to be(false)
        expect_only(entry, child.name, invalid)
      end
    end

    it 'names the hidden child for an administrator, who sees every field (core validates it)' do
      hide(child)
      allow(User).to receive(:current).and_return(dcf_admin)
      [assign(stored_entry, parent => 'B'), change(stored_entry, { parent => 'B' }, by: dcf_admin)].each do |entry|
        expect(entry.valid?).to be(false)
        expect_only(entry, child.name, invalid)
      end
    end
  end

  # Both core shapes on every supported version: a subclass of TimeEntry
  # with core's validate_custom_field_values of 5.1 and 6.0 (every value) or
  # of 6.1 and 7.0 (the values User.current can see) under the patch, and
  # the values 5.1 and 6.0 drop in safe_attributes=.
  describe 'whatever core validates' do
    before { hide(child) }

    def core_shape(every_value)
      patch = patch_module
      Class.new(TimeEntry) do
        def self.name
          'TimeEntry'
        end

        define_method(:validate_custom_field_values) do
          return unless new_record? || custom_field_values_changed?

          (every_value ? custom_field_values : editable_custom_field_values(User.current)).each(&:validate_value)
        end
        prepend patch
      end
    end

    it 'gives the same single parent error when core validates every value, only the visible ones, ' \
       'or never saw the hidden one' do
      results = [true, false].flat_map do |every_value|
        klass = core_shape(every_value)
        expect(klass.instance_method(:validate_custom_field_values).owner).to eq(patch_module)
        [false, true].map do |dropped|
          entry = klass.find(stored_entry.id)
          entry.custom_field_values = keys(parent => 'B')
          entry.custom_field_values.delete_if { |value| value.custom_field_id == child.id } if dropped
          entry.valid?
          [every_value, dropped, entry.errors.to_hash.transform_keys(&:to_s)]
        end
      end
      expect(results.map(&:last).uniq).to eq([{ parent.name => [hidden_message] }]), results.inspect
    end

    it 'judges a value core dropped by its stored value only (a new entry keeps nothing to judge)' do
      klass = core_shape(true)
      tolerated = klass.find(stored_entry(parent => 'A', child => 'b1', other => 'X').id)
      tolerated.custom_field_values = keys(other => 'Y')
      tolerated.custom_field_values.delete_if { |value| value.custom_field_id == child.id }
      expect(tolerated.valid?).to be(true)
      child.update_column(:default_value, secret)
      fresh = klass.new(project: project, user: user, author: user, spent_on: Date.new(2026, 1, 2), hours: 1,
                        activity: activity)
      fresh.custom_field_values = keys(parent => 'B')
      fresh.custom_field_values.delete_if { |value| value.custom_field_id == child.id }
      expect(fresh.valid?).to be(true), fresh.errors.full_messages.inspect
    end
  end

  # Characterization of core, not of the plugin: 5.1 and 6.0 inherit
  # validate_custom_field_values and their TimeEntry#safe_attributes= drops
  # the values the user cannot see, which the save then deletes; 6.1 and 7.0
  # define their own and restore those values (one core change).
  describe 'core and a hidden value on a saved time entry edit (characterization)' do
    it 'keeps it where core restores it and deletes it where core drops it' do
      hide(child)
      entry = change(stored_entry(parent => 'A', child => secret, other => 'X'), { other => 'Y' })
      dropped = entry.custom_field_values.none? { |value| value.custom_field_id == child.id }
      own = TimeEntry.instance_method(:validate_custom_field_values).super_method.owner == TimeEntry
      expect(dropped).to eq(!own)
      expect(entry.save).to be(true), entry.errors.full_messages.inspect
      expect([stored(entry, other), stored(entry, child)]).to eq(['Y', dropped ? nil : secret])
    end
  end

  describe 'REST API (PUT /time_entries/:id)' do
    before { hide(child) }

    def put_entry(entry, value, format: 'json')
      body = { time_entry: { custom_fields: [{ id: parent.id, value: value }] } }
      headers = json_headers.merge('ACCEPT' => "application/#{format}")
      put "/time_entries/#{entry.id}.#{format}", params: body.to_json, headers: headers
    end

    it 'answers 422 with the parent message, without the child name or value, in en and de' do
      hidden_texts.each do |language, text|
        user.update_column(:language, language)
        entry = stored_entry
        put_entry(entry, 'B')
        expect(response).to have_http_status(422), response.body
        expect(JSON.parse(response.body)['errors']).to eq(["#{parent.name} #{text}"]), language
        expect(leaks?(response.body, child)).to be(false), response.body
        expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
      end
    end

    it 'answers 422 in XML with the parent message and no leak' do
      entry = stored_entry
      put_entry(entry, 'B', format: 'xml')
      expect(response).to have_http_status(422), response.body
      errors = Nokogiri::XML(response.body).xpath('//errors/error').map(&:text)
      expect(errors).to eq(["#{parent.name} #{hidden_message}"])
      expect(leaks?(response.body, child)).to be(false), response.body
      expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
    end

    it 'saves a parent change to a value that allows the hidden child' do
      entry = stored_entry
      put_entry(entry, 'D')
      expect(response).to have_http_status(204), response.body
      expect(stored(entry, parent)).to eq('D')
    end
  end

  describe 'time entry form (PUT /time_entries/:id)' do
    it 're-renders the form with the parent message, never naming the hidden child' do
      hide(child)
      entry = stored_entry
      put "/time_entries/#{entry.id}", params: { time_entry: { custom_field_values: keys(parent => 'B') } }
      expect(response).to have_http_status(200)
      expect(error_items).to eq(["#{parent.name} #{hidden_message}"])
      expect(leaks?(response.body, child)).to be(false)
      expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
    end
  end

  # The link posts to bulk update, which re-renders core's bulk edit form.
  # That form lists every available time entry field (core:
  # TimeEntry.first.available_custom_fields, on every supported version),
  # the hidden one too, so only the errors are checked for a leak.
  describe 'context menu (core: /time_entries/context_menu and its bulk update links)' do
    it 'offers no plugin wizard, and its parent link refuses the change like bulk edit' do
      hide(child)
      entry = stored_entry
      get '/time_entries/context_menu', params: { ids: [entry.id] }
      expect(response).to have_http_status(200)
      expect(doc.css('.cf-parent, template[id^="cf-wizard-"]')).to be_empty
      link = doc.css('a').detect do |a|
        href = CGI.unescape(a['href'].to_s)
        href.include?('/time_entries/bulk_update') && href.include?("[custom_field_values][#{parent.id}]=B")
      end
      expect(link).not_to be_nil, response.body
      expect(link['data-method']).to eq('post')
      post link['href']
      expect(response).to have_http_status(200)
      expect(error_items).to eq(["#{parent.name} #{hidden_message}: ##{entry.id}"])
      expect(leaks?(doc.css('#errorExplanation, .flash').text, child)).to be(false)
      expect([stored(entry, parent), stored(entry, child)]).to eq(['A', secret])
    end
  end

  describe 'context-menu wizard (POST /depending_custom_fields/save)' do
    it 'exists for issues only: no time entry route, model or hook' do
      routes = Rails.application.routes.routes.select { |r| r.defaults[:controller] == 'context_menu_wizard' }
      # Changed by WP-36 (UD-13 changed by the owner): the GET of the wizard
      # body (issues only as well) is the second route; was the save alone.
      expect(routes.map { |r| [r.path.spec.to_s, r.defaults[:action]] })
        .to eq([['/depending_custom_fields/wizard(.:format)', 'show'], ['/depending_custom_fields/save(.:format)', 'save']])
      source = File.read(File.expand_path('../../app/controllers/context_menu_wizard_controller.rb', __dir__))
      expect(source).to include('Issue.where(id: ids)')
      expect(source).not_to include('TimeEntry')
      hook = RedmineDependingCustomFields::Hooks::ContextMenuHook
      expect(hook.public_instance_methods(false)).to eq([:view_issues_context_menu_end])
    end
  end

  describe 'query cost' do
    it 'adds no query to a valid change while a hidden child passes' do
      hide(child)
      prepared = Array.new(3) { change(stored_entry(parent => 'A', child => secret, other => 'X'), { other => 'Y' }) }
      expect(prepared[0].valid?).to be(true)
      with = dcf_count_queries { expect(prepared[1].valid?).to be(true) }
      allow(RedmineDependingCustomFields::NonEditableDependencies).to receive(:validate)
      without = dcf_count_queries { expect(prepared[2].valid?).to be(true) }
      expect(with).to eq(without)
    end
  end
end
