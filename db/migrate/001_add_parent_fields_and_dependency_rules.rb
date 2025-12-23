# frozen_string_literal: true

class AddParentFieldsAndDependencyRules < ActiveRecord::Migration[5.2]
  def change
    add_column :custom_fields, :parent_field_type, :string
    add_column :custom_fields, :parent_field_key, :string
    add_column :custom_fields, :dependency_rules, :text
  end
end
