class VatValidationWorker
  include Sidekiq::Job

  sidekiq_options retry: false

  def perform(vat_validation_id)
    vat_validation = VatValidation.find_by(id: vat_validation_id)
    return unless vat_validation

    response = Vies::CheckVatService.call(
      country_code: vat_validation.country_code,
      vat_number: vat_validation.vat_number
    )

    vat_validation.update!(
      response.except(:valid).merge(
        vies_valid: response[:valid],
        status: "completed"
      )
    )
  rescue Vies::Error, Timeout::Error
    vat_validation&.update!(status: "failed")
  end
end
