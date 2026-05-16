module VatValidations
  class ListQuery
    class InvalidDateError < StandardError; end
    class InvalidBooleanError < StandardError; end

    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

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
        scope = scope.where("queried_at >= ?", date_param(:date_from).beginning_of_day) if params[:date_from].present?
        scope = scope.where("queried_at <= ?", date_param(:date_to).end_of_day) if params[:date_to].present?
        scope
      end
    end

    def date_param(name)
      Time.zone.parse(params[name]).tap do |date|
        raise InvalidDateError, "#{name} is invalid" unless date
      end
    rescue ArgumentError, TypeError
      raise InvalidDateError, "#{name} is invalid"
    end

    def boolean_param(value)
      case value.to_s
      when "true", "1"
        true
      when "false", "0"
        false
      else
        raise InvalidBooleanError, "valid must be true, false, 1 or 0"
      end
    end

    def positive_integer_param(value, default)
      integer = value.to_i
      integer.positive? ? [integer, MAX_PER_PAGE].min : default
    end
  end
end
