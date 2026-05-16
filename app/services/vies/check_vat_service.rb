require "cgi"
require "net/http"
require "nokogiri"

module Vies
  class Error < StandardError; end
  class InvalidInputError < Error; end
  class ServiceUnavailableError < Error; end
  class MemberStateUnavailableError < Error; end
  class TimeoutError < Error; end
  class ServerBusyError < Error; end
  class UnexpectedResponseError < Error; end

  class CheckVatService
    ENDPOINT = URI("https://ec.europa.eu/taxation_customs/vies/services/checkVatService").freeze
    TIMEOUT_SECONDS = 10
    FAULT_ERRORS = {
      "INVALID_INPUT" => InvalidInputError,
      "SERVICE_UNAVAILABLE" => ServiceUnavailableError,
      "MS_UNAVAILABLE" => MemberStateUnavailableError,
      "TIMEOUT" => TimeoutError,
      "SERVER_BUSY" => ServerBusyError
    }.freeze

    def self.call(country_code:, vat_number:)
      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true) do |http|
        http.open_timeout = TIMEOUT_SECONDS
        http.read_timeout = TIMEOUT_SECONDS
        http.request(request(country_code:, vat_number:))
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise ServiceUnavailableError, "VIES request failed with HTTP #{response.code}"
      end

      parse_response(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      raise TimeoutError, "VIES request timed out"
    rescue SocketError, SystemCallError, IOError => e
      raise ServiceUnavailableError, "VIES request failed: #{e.message}"
    end

    def self.request(country_code:, vat_number:)
      Net::HTTP::Post.new(ENDPOINT).tap do |request|
        request["Content-Type"] = "text/xml; charset=utf-8"
        request["SOAPAction"] = ""
        request.body = soap_body(country_code:, vat_number:)
      end
    end
    private_class_method :request

    def self.soap_body(country_code:, vat_number:)
      country_code = CGI.escapeHTML(country_code.to_s.strip.upcase)
      vat_number = CGI.escapeHTML(vat_number.to_s.strip)

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types">
          <soapenv:Header/>
          <soapenv:Body>
            <urn:checkVat>
              <urn:countryCode>#{country_code}</urn:countryCode>
              <urn:vatNumber>#{vat_number}</urn:vatNumber>
            </urn:checkVat>
          </soapenv:Body>
        </soapenv:Envelope>
      XML
    end
    private_class_method :soap_body

    def self.parse_response(body)
      document = Nokogiri::XML(body) { |config| config.strict.noblanks }
      raise_fault(document) if fault?(document)
      valid = text_at(document, "valid")
      raise UnexpectedResponseError, "Unexpected VIES response" if valid.nil?

      {
        valid: valid == "true",
        company_name: normalize_text(text_at(document, "name")),
        company_address: normalize_text(text_at(document, "address")),
        queried_at: Time.respond_to?(:current) ? Time.current : Time.now
      }
    rescue Nokogiri::XML::SyntaxError
      raise UnexpectedResponseError, "Invalid XML response from VIES"
    end
    private_class_method :parse_response

    def self.fault?(document)
      !document.at_xpath("//*[local-name()='Fault']").nil?
    end
    private_class_method :fault?

    def self.raise_fault(document)
      faultstring = normalize_text(text_at(document, "faultstring"))
      error_class = FAULT_ERRORS.fetch(faultstring, Error)
      message = faultstring || "Unknown VIES SOAP fault"

      raise error_class, message
    end
    private_class_method :raise_fault

    def self.text_at(document, name)
      document.at_xpath("//*[local-name()='#{name}']")&.text
    end
    private_class_method :text_at

    def self.normalize_text(value)
      value.to_s.strip.then { |text| text.empty? ? nil : text }
    end
    private_class_method :normalize_text
  end
end
