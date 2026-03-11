require_relative '../../../rails_helper'

RSpec.describe 'custom_fields/formats/_depending_enumeration', type: :view do
  let(:active_enumerations) { double('active_enumerations', any?: false) }
  let(:enumerations)        { double('enumerations', active: active_enumerations) }

  let(:custom_field) do
    instance_double(
      CustomField,
      new_record?: false,
      id: 1,
      type: 'IssueCustomField',
      enumerations: enumerations,
      parent_custom_field_id: nil,
      url_pattern: nil,
      hide_when_disabled: false
    )
  end

  let(:form_builder) do
    double('FormBuilder').tap do |fb|
      allow(fb).to receive(:text_field).and_return(''.html_safe)
      allow(fb).to receive(:select).and_return(''.html_safe)
      allow(fb).to receive(:check_box).and_return(''.html_safe)
    end
  end

  let(:not_chain)   { double('not_chain', not: []) }
  let(:where_chain) { double('where_chain', where: not_chain) }

  before do
    assign(:custom_field, custom_field)
    allow(CustomField).to receive(:where).and_return(where_chain)
    allow(view).to receive(:custom_field_enumerations_path).and_return('/custom_fields/1/enumerations')
    allow(view).to receive(:edit_tag_style_tag).and_return(''.html_safe)
  end

  subject(:do_render) do
    render partial: 'custom_fields/formats/depending_enumeration',
           locals: { f: form_builder }
  end

  context 'when sprite_icon is not available' do
    before do
      allow(view).to receive(:respond_to?).and_call_original
      allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(false)
    end

    it 'renders without raising NoMethodError' do
      expect { do_render }.not_to raise_error
    end

    it 'renders the edit link with a plain text label' do
      do_render
      expect(rendered).to include('icon icon-edit')
      expect(rendered).to include('/custom_fields/1/enumerations')
    end
  end

  context 'when sprite_icon is available' do
    before do
      allow(view).to receive(:respond_to?).and_call_original
      allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(true)
      allow(view).to receive(:sprite_icon)
        .with('edit', instance_of(String))
        .and_return('<svg aria-hidden="true"></svg>'.html_safe)
    end

    it 'renders without raising any error' do
      expect { do_render }.not_to raise_error
    end

    it 'renders the edit link with the sprite icon' do
      do_render
      expect(rendered).to include('<svg')
      expect(rendered).to include('icon icon-edit')
      expect(rendered).to include('/custom_fields/1/enumerations')
    end
  end

  context 'when the custom field is a new record' do
    let(:custom_field) do
      instance_double(
        CustomField,
        new_record?: true,
        id: nil,
        type: 'IssueCustomField',
        parent_custom_field_id: nil,
        url_pattern: nil,
        hide_when_disabled: false
      )
    end

    before do
      allow(view).to receive(:respond_to?).and_call_original
      allow(view).to receive(:respond_to?).with(:sprite_icon).and_return(false)
    end

    it 'does not render the edit-enumerations link' do
      do_render
      expect(rendered).not_to include('icon-edit')
      expect(rendered).not_to include('/custom_fields/1/enumerations')
    end
  end
end
