class CreateVehicleTypeCategories < ActiveRecord::Migration[5.0]
  def change
    create_table :vehicle_type_categories do |t|
      t.references :vehicle_type, foreign_key: true, null: false, index:true
      t.references :vehicle_category, foreign_key: true, null: false, index:true

      t.timestamps
    end
  end
end
