class VatValidation < ApplicationRecord
  validates :country_code, presence: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :vat_number, presence: true
end
