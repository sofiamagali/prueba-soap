class VatValidation < ApplicationRecord
  validates :country_code, presence: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :vat_number, presence: true

  def valid
    vies_valid
  end

  def valid=(value)
    self.vies_valid = value
  end
end
