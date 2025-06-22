module RedmineDependingCustomFields
  module Patches
    module QueryCustomFieldColumnPatch
      # Ensure that the custom field order statement is used for sorting when
      # available. Delegates the rest of the initialization to the original
      # implementation so it keeps the default behaviour.
      def initialize(custom_field, options = {})
        if custom_field.respond_to?(:order_statement)
          options = options.merge(sortable: custom_field.order_statement)
        end
        super(custom_field, options)
      end
    end
  end
end

QueryCustomFieldColumn.prepend RedmineDependingCustomFields::Patches::QueryCustomFieldColumnPatch
