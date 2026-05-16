module Api
  module V1
    class VatValidationsController < ApplicationController
      def create
        result = VatValidations::CreateService.new(params).call

        return render json: { errors: result.errors }, status: result.status unless result.success?

        render json: vat_validation_json(result.vat_validation, cached: result.cached), status: result.status
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
      rescue VatValidations::ListQuery::InvalidDateError, VatValidations::ListQuery::InvalidBooleanError => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end

      def stats
        total_validations = VatValidation.count
        # Los porcentajes salen solo de completed porque pending/failed todavia no tienen una respuesta final de VIES.
        completed_validations = VatValidation.where(status: "completed")
        completed_count = completed_validations.count
        valid_count = completed_validations.where(vies_valid: true).count
        invalid_count = completed_validations.where(vies_valid: false).count

        render json: {
          total_validations: total_validations,
          completed_validations: completed_count,
          pending_validations: VatValidation.where(status: "pending").count,
          failed_validations: VatValidation.where(status: "failed").count,
          valid_percentage: percentage(valid_count, completed_count),
          invalid_percentage: percentage(invalid_count, completed_count),
          top_countries: top_countries
        }
      end

      private

      def percentage(count, total)
        return 0 if total.zero?

        ((count.to_f / total) * 100).round(2)
      end

      def top_countries
        VatValidation
          .group(:country_code)
          .order(Arel.sql("COUNT(*) DESC"))
          .limit(5)
          .count
          .map { |country_code, count| { country_code: country_code, count: count } }
      end

      def vat_validation_json(vat_validation, cached: false)
        {
          id: vat_validation.id,
          country_code: vat_validation.country_code,
          vat_number: vat_validation.vat_number,
          status: vat_validation.status,
          valid: vat_validation.vies_valid,
          company_name: vat_validation.company_name,
          company_address: vat_validation.company_address,
          queried_at: vat_validation.queried_at,
          cached: cached
        }
      end
    end
  end
end
