class CreateDependingCustomFieldSettings < ActiveRecord::Migration[5.2]
  def change
    create_table :depending_custom_field_settings do |t|
      t.integer :custom_field_id, null: false
      t.text :settings
      t.timestamps
    end
  end
end
