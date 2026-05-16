module Vies
  module Errors
    class Error < StandardError; end
    class InvalidInputError < Error; end
    class ServiceUnavailableError < Error; end
    class MemberStateUnavailableError < Error; end
    class TimeoutError < Error; end
    class ServerBusyError < Error; end
    class UnexpectedResponseError < Error; end

    FAULT_ERRORS = {
      "INVALID_INPUT" => InvalidInputError,
      "SERVICE_UNAVAILABLE" => ServiceUnavailableError,
      "MS_UNAVAILABLE" => MemberStateUnavailableError,
      "TIMEOUT" => TimeoutError,
      "SERVER_BUSY" => ServerBusyError
    }.freeze

    def self.error_for_fault(faultstring)
      FAULT_ERRORS.fetch(faultstring, Error)
    end
  end

  Error = Errors::Error
  InvalidInputError = Errors::InvalidInputError
  ServiceUnavailableError = Errors::ServiceUnavailableError
  MemberStateUnavailableError = Errors::MemberStateUnavailableError
  TimeoutError = Errors::TimeoutError
  ServerBusyError = Errors::ServerBusyError
  UnexpectedResponseError = Errors::UnexpectedResponseError
end
