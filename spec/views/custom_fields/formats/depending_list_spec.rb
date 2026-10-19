# frozen_string_literal: true

require_relative '../../../rails_helper'

# WP-10: the parent select of the depending list form offers
# DependencyRules.parent_candidates, and the cycle warning follows the
# sprite_icon guard (UX-10), checked with sprite_icon stubbed on and off.
RSpec.describe 'custom_fields/formats/_depending_list', type: :view do
  include DcfStoredCycle

  let(:root) { dcf_list_field(values: %w[R1], name: 'Root') }
  let(:custom_field) { dcf_list_field(format: 'depending_list', values: %w[a1], name: 'Child', parent: root) }
  let(:select_choices) { [] }

  let(:form_builder) do
    double('FormBuilder').tap do |fb|
      allow(fb).to receive(:text_area).and_return(''.html_safe)
      allow(fb).to receive(:text_field).and_return(''.html_safe)
      allow(fb).to receive(:check_box).and_return(''.html_safe)
      allow(fb).to receive(:select) do |name, choices, *_rest|
        select_choices.concat(choices) if name == :parent_custom_field_id
        ''.html_safe
      end
    end
  end

  before do
    assign(:custom_field, custom_field)
    allow(view).to receive(:edit_tag_style_tag).and_return(''.html_safe)
  end

  subject(:do_render) do
    render partial: 'custom_fields/formats/depending_list', locals: { f: form_builder }
  end

  def stub_sprite_icon(available)
    allow(view).to receive(:respond_to?).and_call_original
    allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(available)
    return unless available

    allow(view).to receive(:sprite_icon).with('warning', instance_of(String)) do |_name, label|
      '<svg class="warning-svg"></svg>'.html_safe + view.content_tag(:span, label, class: 'icon-label')
    end
  end

  def warning
    Nokogiri::HTML.fragment(rendered).css('p.icon.icon-warning').detect do |p|
      p.text.include?(I18n.t(:warning_dcf_parent_cycle, fields: '|').split('|').first)
    end
  end

  context 'when sprite_icon is not available' do
    before { stub_sprite_icon(false) }

    it 'offers the parent candidates as [name, id] pairs, without the field and its descendants' do
      other = dcf_list_field(name: 'Other')
      dcf_list_field(format: 'depending_list', name: 'Grandchild', parent: custom_field)
      dcf_enum_field(name: 'Other family')
      do_render
      expect(select_choices).to eq([['Root', root.id.to_s], ['Other', other.id.to_s]])
      expect(warning).to be_nil
    end

    it 'renders the cycle warning as plain text with the classic icon class' do
      world = dcf_stored_cycles(:list)
      assign(:custom_field, CustomField.find(world.b.id))
      do_render
      expect(warning.text.strip)
        .to eq(I18n.t(:warning_dcf_parent_cycle, fields: [world.b.name, world.c.name, world.a.name].join(', ')))
      expect(warning.css('svg')).to be_empty
      expect(select_choices.map(&:last)).to include(world.c.id.to_s)
    end

    it 'shows no warning on a field whose chain only reaches a cycle' do
      world = dcf_stored_cycles(:list)
      assign(:custom_field, CustomField.find(world.below_self_parent.id))
      do_render
      expect(warning).to be_nil
    end
  end

  context 'when sprite_icon is available' do
    before { stub_sprite_icon(true) }

    it 'renders the cycle warning with the warning sprite and the text as its label' do
      world = dcf_stored_cycles(:list)
      assign(:custom_field, CustomField.find(world.x.id))
      do_render
      expect(warning.at_css('svg.warning-svg')).not_to be_nil
      expect(warning.at_css('span.icon-label').text)
        .to eq(I18n.t(:warning_dcf_parent_cycle, fields: [world.x.name, world.y.name].join(', ')))
    end
  end

  context 'when the custom field is a new record' do
    let(:custom_field) { IssueCustomField.new(name: 'New', field_format: 'depending_list') }

    before { stub_sprite_icon(false) }

    it 'offers every same-type list field and shows no warning' do
      root
      do_render
      expect(select_choices).to eq([['Root', root.id.to_s]])
      expect(warning).to be_nil
    end
  end
end
