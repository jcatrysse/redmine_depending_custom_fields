require_relative '../rails_helper'

RSpec.describe ContextMenuWizardHelper do
  let(:helper_object) do
    Class.new do
      include ContextMenuWizardHelper
    end.new
  end

  # WP-15: intersect_allowed_values is deleted (no caller since the SD-14
  # fix); its two examples are removed. Public, protected and private alike.
  it 'no longer offers intersect_allowed_values' do
    expect(ContextMenuWizardHelper.method_defined?(:intersect_allowed_values)).to be(false)
    expect(ContextMenuWizardHelper.private_method_defined?(:intersect_allowed_values)).to be(false)
  end

  describe '#render_custom_field' do
    let(:cf) { build_custom_field(id: 5, default_value: 'foo') }
    let(:issues) { [instance_double(Issue)] }

    # Flipped by WP-18: was 'injects the data-field-id attribute into the
    # select tag' with cf.default_value as the value. UD-11: every wizard
    # field opens on '(no change)' (value nil); the core bulk tag (with the
    # plugin's bulk_edit_tag data) is returned as it is.
    it 'returns the core bulk tag for a nil value, unchanged and without data-field-id' do
      tag = ActiveSupport::SafeBuffer.new("<select name='cf'></select>")
      allow(helper_object).to receive(:custom_field_tag_for_bulk_edit)
        .with('issue', cf, issues, nil)
        .and_return(tag)

      html = helper_object.render_custom_field(cf, issues)
      expect(html).to equal(tag)
      expect(html).not_to include('data-field-id')
    end
  end
end
