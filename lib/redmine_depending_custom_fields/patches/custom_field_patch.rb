module RedmineDependingCustomFields
  module Patches
    module CustomFieldPatch
      def self.prepended(base)
        base.after_save :dispatch_after_custom_field_save
      end

      private

      def dispatch_after_custom_field_save
        if format.respond_to?(:after_custom_field_save)
          format.after_custom_field_save(self)
        end
      end
    end
  end
end

CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldPatch
