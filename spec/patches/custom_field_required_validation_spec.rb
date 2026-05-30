require_relative '../rails_helper'

# These specs exercise CustomFieldPatch#validate_custom_value, which strips the
# "can't be blank" error that CustomField#validate_custom_value adds independently
# after calling format.validate_custom_value.  The format-level early return alone
# is not sufficient because CustomField re-checks is_required? after the format
# returns [].
#
# We build a minimal base class that mirrors the relevant behaviour of
# CustomField#validate_custom_value so the patch can be tested without a
# database, then prepend the patch to it.

RSpec.describe 'CustomFieldPatch#validate_custom_value required-check bypass' do
  let(:blank_msg)   { I18n.t('activerecord.errors.messages.blank') }
  let(:invalid_msg) { I18n.t('activerecord.errors.messages.invalid') }

  let(:issue)     { double('Issue') }
  let(:parent_cf) { double('parent_cf', id: 1) }

  before do
    allow(CustomField).to receive(:find_by).with(id: 1).and_return(parent_cf)
  end

  # ---------------------------------------------------------------------------
  # Minimal stand-in for CustomField that carries just enough state for the
  # patch to work, plus a validate_custom_value that mirrors the core model:
  #   1. call format.validate_custom_value (may return [])
  #   2. independently add blank_msg when is_required? && value.blank?
  # ---------------------------------------------------------------------------
  def build_base_class
    Class.new do
      def self.after_save(*); end  # prevent ActiveRecord callback registration

      attr_accessor :field_format, :parent_custom_field_id, :value_dependencies

      def initialize(attrs = {})
        @field_format           = attrs[:field_format]
        @parent_custom_field_id = attrs[:parent_custom_field_id]
        @value_dependencies     = attrs[:value_dependencies] || {}
        @required               = attrs.fetch(:is_required, false)
        @format_obj             = attrs[:format]
      end

      def is_required? = @required
      def format       = @format_obj

      def set_custom_field_value(_cv, v) = v  # required by CustomFieldValue#value=

      # Mirrors the relevant part of CustomField#validate_custom_value
      def validate_custom_value(custom_value)
        value = custom_value.value
        errs  = format.validate_custom_value(custom_value)

        unless errs.any?
          errs << I18n.t('activerecord.errors.messages.blank') if is_required? && value.blank?
        end

        errs
      end
    end.tap { |k| k.prepend(RedmineDependingCustomFields::Patches::CustomFieldPatch) }
  end

  # Returns a fresh copy on every call to prevent cross-call mutation.
  def stub_format_returning(errs)
    dbl = double('format')
    allow(dbl).to receive(:validate_custom_value) { |_cv| errs.dup }
    dbl
  end

  def make_value(cf, val)
    CustomFieldValue.new(custom_field: cf, customized: issue, value: val)
  end

  # ---------------------------------------------------------------------------
  # Core scenario: depending field, required, parent maps to no child options
  # ---------------------------------------------------------------------------
  [
    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
  ].each do |fmt|
    context "field_format: #{fmt}" do
      let(:klass) { build_base_class }

      context 'when parent value has no mapped child options' do
        let(:cf) do
          klass.new(
            field_format:           fmt,
            parent_custom_field_id: 1,
            value_dependencies:     { 'A' => ['x'] },
            is_required:            true,
            format:                 stub_format_returning([])
          )
        end

        before do
          # Parent returns 'Z', which has no entry in the mapping.
          allow(issue).to receive(:custom_field_value).with(parent_cf).and_return('Z')
        end

        it 'returns no errors for a blank child value' do
          expect(cf.validate_custom_value(make_value(cf, ''))).to be_empty
        end

        it 'returns no errors for a nil child value' do
          expect(cf.validate_custom_value(make_value(cf, nil))).to be_empty
        end
      end

      context 'when parent value has a valid mapping' do
        let(:cf) do
          klass.new(
            field_format:           fmt,
            parent_custom_field_id: 1,
            value_dependencies:     { 'A' => ['x'] },
            is_required:            true,
            format:                 stub_format_returning([])
          )
        end

        before do
          # Parent returns 'A', which maps to ['x'] — options exist.
          allow(issue).to receive(:custom_field_value).with(parent_cf).and_return('A')
        end

        it 'preserves the blank error when options are available but value is blank' do
          expect(cf.validate_custom_value(make_value(cf, ''))).to include(blank_msg)
        end
      end

      context 'when parent field has no value selected (blank parent)' do
        let(:cf) do
          klass.new(
            field_format:           fmt,
            parent_custom_field_id: 1,
            value_dependencies:     { 'A' => ['x'] },
            is_required:            true,
            format:                 stub_format_returning([])
          )
        end

        before do
          allow(issue).to receive(:custom_field_value).with(parent_cf).and_return('')
        end

        it 'strips the blank error when parent is blank (no options available)' do
          expect(cf.validate_custom_value(make_value(cf, ''))).not_to include(blank_msg)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Non-depending formats must not be affected
  # ---------------------------------------------------------------------------
  context 'when field_format is not a depending format' do
    let(:klass) { build_base_class }
    let(:cf) do
      klass.new(
        field_format: 'list',
        is_required:  true,
        format:       stub_format_returning([])
      )
    end

    it 'preserves the blank error for a plain list field' do
      expect(cf.validate_custom_value(make_value(cf, ''))).to include(blank_msg)
    end
  end

  # ---------------------------------------------------------------------------
  # When format already returns errors the blank check is skipped entirely
  # (CustomField behaviour) — patch must not double-strip anything
  # ---------------------------------------------------------------------------
  context 'when the format itself returns errors' do
    let(:klass) { build_base_class }
    let(:cf) do
      klass.new(
        field_format:           RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        parent_custom_field_id: 1,
        value_dependencies:     {},
        is_required:            true,
        format:                 stub_format_returning([I18n.t('activerecord.errors.messages.invalid')])
      )
    end

    before do
      allow(issue).to receive(:custom_field_value).with(parent_cf).and_return('Z')
    end

    it 'passes through the format errors unchanged' do
      result = cf.validate_custom_value(make_value(cf, 'bad'))
      expect(result).to eq([invalid_msg])
      expect(result).not_to include(blank_msg)
    end
  end

  # ---------------------------------------------------------------------------
  # Guard: customized is nil (background jobs, import contexts)
  # The patch cannot determine the parent value so it must not suppress the error.
  # ---------------------------------------------------------------------------
  context 'when customized is nil' do
    let(:klass) { build_base_class }
    let(:cf) do
      klass.new(
        field_format:           RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        parent_custom_field_id: 1,
        value_dependencies:     { 'A' => ['x'] },
        is_required:            true,
        format:                 stub_format_returning([])
      )
    end

    it 'preserves the blank error when customized is nil' do
      cv = CustomFieldValue.new(custom_field: cf, customized: nil, value: '')
      expect(cf.validate_custom_value(cv)).to include(blank_msg)
    end
  end

  # ---------------------------------------------------------------------------
  # Guard: parent custom field has been deleted
  # The patch falls back to preserving the error (safe default).
  # ---------------------------------------------------------------------------
  context 'when parent custom field record no longer exists' do
    let(:klass) { build_base_class }
    let(:cf) do
      klass.new(
        field_format:           RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        parent_custom_field_id: 99,
        value_dependencies:     { 'A' => ['x'] },
        is_required:            true,
        format:                 stub_format_returning([])
      )
    end

    before do
      allow(CustomField).to receive(:find_by).with(id: 99).and_return(nil)
    end

    it 'preserves the blank error when the parent field cannot be found' do
      cv = CustomFieldValue.new(custom_field: cf, customized: issue, value: '')
      expect(cf.validate_custom_value(cv)).to include(blank_msg)
    end
  end

  # ---------------------------------------------------------------------------
  # multiple: true field — CustomField uses a separate array branch for blank
  # check; the patch must strip blank_msg there too.
  # ---------------------------------------------------------------------------
  context 'when the field accepts multiple values' do
    let(:klass) do
      Class.new do
        def self.after_save(*); end

        attr_accessor :field_format, :parent_custom_field_id, :value_dependencies

        def initialize(attrs = {})
          @field_format           = attrs[:field_format]
          @parent_custom_field_id = attrs[:parent_custom_field_id]
          @value_dependencies     = attrs[:value_dependencies] || {}
          @required               = attrs.fetch(:is_required, false)
          @format_obj             = attrs[:format]
        end

        def is_required? = @required
        def format       = @format_obj
        def multiple?    = true

        def set_custom_field_value(_cv, v) = v

        # Array branch of CustomField#validate_custom_value
        def validate_custom_value(custom_value)
          value = custom_value.value
          errs  = format.validate_custom_value(custom_value)

          unless errs.any?
            if value.is_a?(Array)
              errs << I18n.t('activerecord.errors.messages.blank') if is_required? && value.detect(&:present?).nil?
            else
              errs << I18n.t('activerecord.errors.messages.blank') if is_required? && value.blank?
            end
          end

          errs
        end
      end.tap { |k| k.prepend(RedmineDependingCustomFields::Patches::CustomFieldPatch) }
    end

    let(:cf) do
      klass.new(
        field_format:           RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        parent_custom_field_id: 1,
        value_dependencies:     { 'A' => ['x'] },
        is_required:            true,
        format:                 stub_format_returning([])
      )
    end

    before do
      allow(issue).to receive(:custom_field_value).with(parent_cf).and_return('Z')
    end

    it 'strips the blank error for an empty array when no options are available' do
      cv = CustomFieldValue.new(custom_field: cf, customized: issue, value: [])
      expect(cf.validate_custom_value(cv)).to be_empty
    end

    it 'strips the blank error for an all-blank array when no options are available' do
      cv = CustomFieldValue.new(custom_field: cf, customized: issue, value: ['', nil])
      expect(cf.validate_custom_value(cv)).to be_empty
    end
  end
end
