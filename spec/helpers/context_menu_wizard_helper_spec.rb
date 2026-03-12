require_relative '../rails_helper'

RSpec.describe ContextMenuWizardHelper do
  let(:helper_object) do
    Class.new do
      include ContextMenuWizardHelper
    end.new
  end

  describe '#intersect_allowed_values' do
    let(:cf) { build_custom_field }
    let(:issue1) { instance_double(Issue) }
    let(:issue2) { instance_double(Issue) }

    it 'returns intersection of allowed values across issues' do
      allow(cf).to receive(:possible_values_options).with(issue1).and_return([['A', 'a'], ['B', 'b']])
      allow(cf).to receive(:possible_values_options).with(issue2).and_return([['B', 'b'], ['C', 'c']])

      result = helper_object.intersect_allowed_values(cf, [issue1, issue2])
      expect(result).to eq(['b'])
    end

    it 'ignores option group entries when intersecting values' do
      allow(cf).to receive(:possible_values_options).with(issue1)
        .and_return([[I18n.t(:status_active), '__group_active__', {class: 'option-group'}], ['U1', '1']])
      allow(cf).to receive(:possible_values_options).with(issue2)
        .and_return([[I18n.t(:status_active), '__group_active__', {class: 'option-group'}], ['U2', '1']])
      result = helper_object.intersect_allowed_values(cf, [issue1, issue2])
      expect(result).to eq(['1'])
    end
  end

  describe '#render_custom_field' do
    let(:cf) { build_custom_field(id: 5, default_value: 'foo') }
    let(:issues) { [instance_double(Issue)] }

    it 'injects the data-field-id attribute into the select tag' do
      allow(helper_object).to receive(:custom_field_tag_for_bulk_edit)
        .with('issue', cf, issues, cf.default_value)
        .and_return("<select name='cf'></select>")

      html = helper_object.render_custom_field(cf, issues)
      expect(html).to include("data-field-id='5'")
    end


    it 'injects data-field-id into each select element' do
      allow(helper_object).to receive(:custom_field_tag_for_bulk_edit)
        .with('issue', cf, issues, cf.default_value)
        .and_return("<div><select name='a'></select><select name='b'></select></div>")

      html = helper_object.render_custom_field(cf, issues)
      expect(html.scan("data-field-id='5'").size).to eq(2)
    end
  end
end
