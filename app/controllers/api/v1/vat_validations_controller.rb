require_dependency "vies/check_vat_service"

module Api
  module V1
    class VatValidationsController < ApplicationController
      def create
        vat_validation = VatValidation.new(vat_validation_params)

        unless vat_validation.valid?
          return render json: { errors: vat_validation.errors.full_messages }, status: :unprocessable_entity
        end

        vies_response = Vies::CheckVatService.call(
          country_code: vat_validation.country_code,
          vat_number: vat_validation.vat_number
        )

        vat_validation.assign_attributes(vies_response)
        vat_validation.save!

        render json: vat_validation_json(vat_validation), status: :created
      rescue Vies::InvalidInputError => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      rescue Vies::ServiceUnavailableError, Vies::MemberStateUnavailableError,
             Vies::TimeoutError, Vies::ServerBusyError => e
        render json: { errors: [e.message] }, status: :service_unavailable
      end

      def show
        vat_validation = VatValidation.find_by(id: params[:id])

        unless vat_validation
          return render json: { error: "Vat validation not found" }, status: :not_found
        end

        render json: vat_validation_json(vat_validation)
      end

      def index
      end

      def stats
      end

      private

      def vat_validation_params
        {
          country_code: params[:country_code].to_s.strip.upcase,
          vat_number: params[:vat_number].to_s.strip
        }
      end

      def vat_validation_json(vat_validation)
        {
          id: vat_validation.id,
          country_code: vat_validation.country_code,
          vat_number: vat_validation.vat_number,
          valid: vat_validation.valid,
          company_name: vat_validation.company_name,
          company_address: vat_validation.company_address,
          queried_at: vat_validation.queried_at,
          cached: false
        }
      end
    end
  end
end
