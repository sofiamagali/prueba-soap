require_relative "errors"

module Vies
  # Protege la API cuando VIES esta degradado: despues de varios fallos transitorios,
  # dejamos de llamar al servicio externo por unos minutos y derivamos el trabajo a Sidekiq.
  class CircuitBreaker
    FAILURE_THRESHOLD = 5
    OPEN_TIMEOUT = 5.minutes

    FAILURE_COUNT_KEY = "vies:circuit_breaker:failure_count"
    OPEN_UNTIL_KEY = "vies:circuit_breaker:open_until"

    TRANSIENT_ERRORS = [
      Vies::ServiceUnavailableError,
      Vies::MemberStateUnavailableError,
      Vies::TimeoutError,
      Vies::ServerBusyError,
      Timeout::Error
    ].freeze

    def self.call
      raise CircuitOpenError, "VIES circuit breaker is open" if open?

      begin
        result = yield
        record_success
        result
      rescue *TRANSIENT_ERRORS
        record_failure
        raise
      end
    end

    def self.open?
      open_until = Rails.cache.read(OPEN_UNTIL_KEY)
      open_until.present? && open_until.future?
    end

    def self.record_success
      Rails.cache.delete(FAILURE_COUNT_KEY)
      Rails.cache.delete(OPEN_UNTIL_KEY)
    end

    def self.record_failure
      failures = Rails.cache.read(FAILURE_COUNT_KEY).to_i + 1
      Rails.cache.write(FAILURE_COUNT_KEY, failures, expires_in: OPEN_TIMEOUT)

      return if failures < FAILURE_THRESHOLD

      Rails.cache.write(OPEN_UNTIL_KEY, Time.current + OPEN_TIMEOUT, expires_in: OPEN_TIMEOUT)
    end

    def self.reset!
      Rails.cache.delete(FAILURE_COUNT_KEY)
      Rails.cache.delete(OPEN_UNTIL_KEY)
    end
  end
end
