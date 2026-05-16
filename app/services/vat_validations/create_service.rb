require "timeout"
require_relative "../vies/check_vat_service"

module VatValidations
  class CreateService
    SYNC_TIMEOUT_SECONDS = 3

    Result = Struct.new(:vat_validation, :errors, :status, :cached, keyword_init: true) do
      def success?
        errors.blank?
      end
    end

    def initialize(params)
      @params = params
    end

    def call
      vat_validation = VatValidation.new(vat_validation_params)

      return Result.new(errors: vat_validation.errors.full_messages, status: :unprocessable_entity) unless vat_validation.valid?

      cached_vat_validation = cached_vat_validation_for(vat_validation)
      if cached_vat_validation
        return Result.new(vat_validation: cached_vat_validation, cached: true, status: :created)
      end

      vat_validation.assign_attributes(vat_validation_attributes_from(vies_response_for(vat_validation)))
      vat_validation.save!

      Result.new(vat_validation: vat_validation, cached: false, status: :created)
    rescue Vies::InvalidInputError => e
      Result.new(errors: [e.message], status: :unprocessable_entity)
    rescue Vies::ServiceUnavailableError, Vies::MemberStateUnavailableError,
           Vies::TimeoutError, Vies::ServerBusyError => e
      enqueue_pending_validation(vat_validation, e.message)
    rescue Vies::UnexpectedResponseError => e
      enqueue_pending_validation(vat_validation, e.message)
    rescue Vies::Error => e
      enqueue_pending_validation(vat_validation, e.message)
    rescue Timeout::Error => e
      enqueue_pending_validation(vat_validation, e.message)
    end

    private

    attr_reader :params

    def vat_validation_params
      {
        country_code: params[:country_code].to_s.strip.upcase,
        vat_number: params[:vat_number].to_s.strip
      }
    end

    def vies_response_for(vat_validation)
      Timeout.timeout(SYNC_TIMEOUT_SECONDS) do
        Vies::CheckVatService.call(
          country_code: vat_validation.country_code,
          vat_number: vat_validation.vat_number
        )
      end
    end

    def vat_validation_attributes_from(vies_response)
      vies_response.except(:valid).merge(
        vies_valid: vies_response[:valid],
        status: "completed"
      )
    end

    def enqueue_pending_validation(vat_validation, _error_message)
      vat_validation.status = "pending"
      vat_validation.save!
      VatValidationWorker.perform_async(vat_validation.id)

      Result.new(vat_validation: vat_validation, cached: false, status: :accepted)
    end

    def cached_vat_validation_for(vat_validation)
      VatValidation
        .where(country_code: vat_validation.country_code, vat_number: vat_validation.vat_number)
        .where(status: "completed")
        .where(queried_at: 24.hours.ago..)
        .order(queried_at: :desc)
        .first
    end
  end
end
