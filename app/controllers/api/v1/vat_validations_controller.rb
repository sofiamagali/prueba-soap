module Api
  module V1
    class VatValidationsController < ApplicationController
      def create
        result = VatValidations::CreateService.new(params).call

        return render json: { errors: result.errors }, status: result.status unless result.success?

        render json: vat_validation_json(result.vat_validation, cached: result.cached), status: :created
      end

      def show
        vat_validation = VatValidation.find_by(id: params[:id])

        return render json: { error: "Vat validation not found" }, status: :not_found unless vat_validation

        render json: vat_validation_json(vat_validation)
      end

      def index
        result = VatValidations::ListQuery.new(params).call

        render json: {
          items: result[:items].map { |vat_validation| vat_validation_json(vat_validation) },
          pagination: result[:pagination]
        }
      end

      def stats
      end

      private

      def vat_validation_json(vat_validation, cached: false)
        {
          id: vat_validation.id,
          country_code: vat_validation.country_code,
          vat_number: vat_validation.vat_number,
          valid: vat_validation.valid,
          company_name: vat_validation.company_name,
          company_address: vat_validation.company_address,
          queried_at: vat_validation.queried_at,
          cached: cached
        }
      end
    end
  end
end
