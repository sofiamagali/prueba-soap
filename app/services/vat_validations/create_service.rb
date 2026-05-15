module VatValidations
  class CreateService
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
      return Result.new(vat_validation: cached_vat_validation, cached: true) if cached_vat_validation

      vat_validation.assign_attributes(vies_response_for(vat_validation))
      vat_validation.save!

      Result.new(vat_validation: vat_validation, cached: false)
    rescue Vies::InvalidInputError => e
      Result.new(errors: [e.message], status: :unprocessable_entity)
    rescue Vies::ServiceUnavailableError, Vies::MemberStateUnavailableError,
           Vies::TimeoutError, Vies::ServerBusyError => e
      Result.new(errors: [e.message], status: :service_unavailable)
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
      Vies::CheckVatService.call(
        country_code: vat_validation.country_code,
        vat_number: vat_validation.vat_number
      )
    end

    def cached_vat_validation_for(vat_validation)
      VatValidation
        .where(country_code: vat_validation.country_code, vat_number: vat_validation.vat_number)
        .where("queried_at >= :since OR created_at >= :since", since: 24.hours.ago)
        .order(queried_at: :desc, created_at: :desc)
        .first
    end
  end
end
