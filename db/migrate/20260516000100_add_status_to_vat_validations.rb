class AddStatusToVatValidations < ActiveRecord::Migration[7.2]
  def change
    add_column :vat_validations, :status, :string, null: false, default: "completed"
  end
end
