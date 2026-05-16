class VatValidation < ApplicationRecord
  STATUSES = %w[pending completed failed].freeze

  validates :country_code, presence: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :country_code,
            inclusion: { in: Vies::CheckVatService::SUPPORTED_COUNTRY_CODES, message: "is not supported by VIES" },
            if: -> { country_code.present? && country_code.match?(/\A[A-Z]{2}\z/) }
  validates :vat_number, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
end
