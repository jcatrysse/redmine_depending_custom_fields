# frozen_string_literal: true

require_relative '../../../rails_helper'

# WP-10: real records instead of an instance_double and a stubbed
# CustomField.where chain (was: where/not doubles), because the parent select
# now reads DependencyRules.parent_candidates and the cycle warning reads the
# stored topology. The sprite_icon guards (edit link and cycle warning) are
# checked with sprite_icon stubbed on and off.
RSpec.describe 'custom_fields/formats/_depending_enumeration', type: :view do
  include DcfStoredCycle

  let(:root) { dcf_enum_field(names: %w[R1], name: 'Root') }
  let(:custom_field) { dcf_enum_field(format: 'depending_enumeration', names: %w[a1], name: 'Child', parent: root) }
  let(:select_choices) { [] }

  let(:form_builder) do
    double('FormBuilder').tap do |fb|
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
    allow(view).to receive(:custom_field_enumerations_path).and_return('/custom_fields/1/enumerations')
    allow(view).to receive(:edit_tag_style_tag).and_return(''.html_safe)
  end

  subject(:do_render) do
    render partial: 'custom_fields/formats/depending_enumeration',
           locals: { f: form_builder }
  end

  def stub_sprite_icon(available)
    allow(view).to receive(:respond_to?).and_call_original
    allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(available)
    return unless available

    allow(view).to receive(:sprite_icon).with('edit', instance_of(String))
                                        .and_return('<svg aria-hidden="true"></svg>'.html_safe)
    allow(view).to receive(:sprite_icon).with('warning', instance_of(String)) do |_name, label|
      '<svg class="warning-svg"></svg>'.html_safe + view.content_tag(:span, label, class: 'icon-label')
    end
  end

  context 'when sprite_icon is not available' do
    before { stub_sprite_icon(false) }

    it 'renders without raising NoMethodError' do
      expect { do_render }.not_to raise_error
    end

    it 'renders the edit link with a plain text label' do
      do_render
      expect(rendered).to include('icon icon-edit')
      expect(rendered).to include('/custom_fields/1/enumerations')
    end

    it 'offers the parent candidates as [name, id] pairs and no cycle warning' do
      other = dcf_enum_field(name: 'Other')
      do_render
      expect(select_choices).to eq([['Root', root.id.to_s], ['Other', other.id.to_s]])
      expect(rendered).not_to include('icon-warning')
    end

    it 'renders the cycle warning as plain text with the classic icon class' do
      world = dcf_stored_cycles(:enumeration)
      assign(:custom_field, CustomField.find(world.x.id))
      do_render
      warning = Nokogiri::HTML.fragment(rendered).at_css('p.icon.icon-warning')
      expect(warning.text.strip).to eq(I18n.t(:warning_dcf_parent_cycle, fields: [world.x.name, world.y.name].join(', ')))
      expect(warning.css('svg')).to be_empty
    end
  end

  context 'when sprite_icon is available' do
    before { stub_sprite_icon(true) }

    it 'renders without raising any error' do
      expect { do_render }.not_to raise_error
    end

    it 'renders the edit link with the sprite icon' do
      do_render
      expect(rendered).to include('<svg')
      expect(rendered).to include('icon icon-edit')
      expect(rendered).to include('/custom_fields/1/enumerations')
    end

    it 'renders the cycle warning with the warning sprite and the text as its label' do
      world = dcf_stored_cycles(:enumeration)
      assign(:custom_field, CustomField.find(world.self_parent.id))
      do_render
      warning = Nokogiri::HTML.fragment(rendered).at_css('p.icon.icon-warning')
      expect(warning.at_css('svg.warning-svg')).not_to be_nil
      expect(warning.at_css('span.icon-label').text).to eq(I18n.t(:warning_dcf_parent_cycle, fields: world.self_parent.name))
    end
  end

  context 'when the custom field is a new record' do
    let(:custom_field) { IssueCustomField.new(name: 'New', field_format: 'depending_enumeration') }

    before { stub_sprite_icon(false) }

    it 'does not render the edit-enumerations link' do
      do_render
      expect(rendered).not_to include('icon-edit')
      expect(rendered).not_to include('/custom_fields/1/enumerations')
    end

    it 'keeps the parent select with every same-type enumeration field and no warning' do
      root
      do_render
      expect(select_choices).to eq([['Root', root.id.to_s]])
      expect(rendered).not_to include('icon-warning')
    end
  end
end
