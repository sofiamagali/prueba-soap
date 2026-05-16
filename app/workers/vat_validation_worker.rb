class VatValidationWorker
  include Sidekiq::Job

  CIRCUIT_OPEN_RETRY_IN = Vies::CircuitBreaker::OPEN_TIMEOUT

  # VIES puede fallar de forma transitoria; reintento pocas veces antes de cerrar el intento como fallido.
  sidekiq_options retry: 3

  sidekiq_retries_exhausted do |job, _error|
    VatValidation.find_by(id: job["args"].first)&.update!(status: "failed")
  end

  def perform(vat_validation_id)
    vat_validation = VatValidation.find_by(id: vat_validation_id)
    return unless vat_validation
    # El job podria encolarse mas de una vez; solo proceso registros que siguen pending.
    return unless vat_validation.status == "pending"

    response = Vies::CircuitBreaker.call do
      Vies::CheckVatService.call(
        country_code: vat_validation.country_code,
        vat_number: vat_validation.vat_number
      )
    end

    vat_validation.update!(
      response.except(:valid).merge(
        vies_valid: response[:valid],
        status: "completed"
      )
    )
  rescue Vies::CircuitOpenError
    # El circuito abierto no significa que la validacion sea fallida; solo pospone el intento.
    VatValidationWorker.perform_in(CIRCUIT_OPEN_RETRY_IN, vat_validation.id) if vat_validation
  rescue Vies::Error, Timeout::Error
    raise
  end
end
