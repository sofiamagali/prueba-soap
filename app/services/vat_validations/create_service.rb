module VatValidations
  class CreateService
    Result = Struct.new(:vat_validation, :errors, :status, keyword_init: true) do
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

      vat_validation.assign_attributes(vies_response_for(vat_validation))
      vat_validation.save!

      Result.new(vat_validation: vat_validation)
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
  end
end
