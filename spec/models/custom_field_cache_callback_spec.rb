require_relative '../rails_helper'

RSpec.describe 'CustomField cache clearing callback' do
  before do
    allow(Rails.cache).to receive(:delete)
  end

  let(:dummy_class) do
    Class.new do
      include RedmineDependingCustomFields::Patches::CustomFieldPatch
      attr_accessor :format
    end
  end

  it 'clears caches for depending list field' do
    cf = dummy_class.new
    cf.format = RedmineDependingCustomFields::DependingListFormat.instance
    cf.send(:dispatch_after_custom_field_save)
    expect(Rails.cache).to have_received(:delete).with('depending_custom_fields/mapping')
  end

  it 'clears caches for depending enumeration field' do
    cf = dummy_class.new
    cf.format = RedmineDependingCustomFields::DependingEnumerationFormat.instance
    cf.send(:dispatch_after_custom_field_save)
    expect(Rails.cache).to have_received(:delete).with('depending_custom_fields/mapping')
  end
end
