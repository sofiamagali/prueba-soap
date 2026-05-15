module VatValidations
  class ListQuery
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 25

    attr_reader :page, :per_page

    def initialize(params)
      @params = params
      @page = positive_integer_param(params[:page], DEFAULT_PAGE)
      @per_page = positive_integer_param(params[:per_page], DEFAULT_PER_PAGE)
    end

    def call
      total_count = relation.count
      total_pages = (total_count.to_f / per_page).ceil

      {
        items: relation.offset((page - 1) * per_page).limit(per_page),
        pagination: {
          page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: total_pages
        }
      }
    end

    private

    attr_reader :params

    def relation
      @relation ||= begin
        scope = VatValidation.order(created_at: :desc)
        scope = scope.where(country_code: params[:country_code].to_s.strip.upcase) if params[:country_code].present?
        scope = scope.where(vies_valid: boolean_param(params[:valid])) if params.key?(:valid)
        scope = scope.where("queried_at >= ?", Time.zone.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
        scope = scope.where("queried_at <= ?", Time.zone.parse(params[:date_to]).end_of_day) if params[:date_to].present?
        scope
      end
    end

    def boolean_param(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def positive_integer_param(value, default)
      integer = value.to_i
      integer.positive? ? integer : default
    end
  end
end
