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
        total_validations = VatValidation.count
        valid_count = VatValidation.where(vies_valid: true).count
        invalid_count = VatValidation.where(vies_valid: false).count

        render json: {
          total_validations: total_validations,
          valid_percentage: percentage(valid_count, total_validations),
          invalid_percentage: percentage(invalid_count, total_validations),
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
