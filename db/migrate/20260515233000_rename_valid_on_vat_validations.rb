class RenameValidOnVatValidations < ActiveRecord::Migration[7.2]
  def change
    rename_column :vat_validations, :valid, :vies_valid
  end
end
