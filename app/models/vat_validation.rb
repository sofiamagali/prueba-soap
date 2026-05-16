class VatValidation < ApplicationRecord
  STATUSES = %w[pending completed failed].freeze

  validates :country_code, presence: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :vat_number, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  def valid
    vies_valid
  end

  def valid=(value)
    self.vies_valid = value
  end
end
