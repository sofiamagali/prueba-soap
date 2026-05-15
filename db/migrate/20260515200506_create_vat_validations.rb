class CreateVatValidations < ActiveRecord::Migration[7.2]
  def change
    create_table :vat_validations do |t|
      t.string :country_code, null: false
      t.string :vat_number, null: false
      t.boolean :valid
      t.string :company_name
      t.text :company_address
      t.datetime :queried_at

      t.timestamps
    end

    add_index :vat_validations, [:country_code, :vat_number]
  end
end
