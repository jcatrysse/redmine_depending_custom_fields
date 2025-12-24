require_dependency 'custom_field'
require 'json'

# Extension for CustomField that triggers a callback on the field format after
# the record is saved. This allows formats to invalidate caches when their
# configuration changes.

module RedmineDependingCustomFields
  module Patches
    module CustomFieldPatch
      def self.prepended(base, *)
        base.after_save :dispatch_after_custom_field_save
        if base.table_exists?
          if base.columns_hash.key?('dependency_rules')
            base.serialize :dependency_rules, JSON
          end
        end
      rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
        Rails.logger.warn "Skipping CustomField serialization patch: Database not ready."
      end

      def update_column(name, value)
        if name.to_s == 'dependency_rules' && !self.class.column_names.include?('dependency_rules')
          self.dependency_rules = value
          save(validate: false)
        else
          super
        end
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
