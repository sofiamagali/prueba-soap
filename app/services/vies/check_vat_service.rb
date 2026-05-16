require "cgi"
require "net/http"
require "nokogiri"
require_relative "errors"

module Vies
  class CheckVatService
    ENDPOINT = URI("https://ec.europa.eu/taxation_customs/vies/services/checkVatService").freeze
    TIMEOUT_SECONDS = 10
    MAX_REDIRECTS = 3
    REDIRECT_CODES = %w[301 302 307 308].freeze
    # Evita tratar como fallos transitorios los paises que VIES nunca va a aceptar.
    # Esos casos deben responder 422 sin crear pending ni encolar Sidekiq.
    SUPPORTED_COUNTRY_CODES = %w[
      AT BE BG CY CZ DE DK EE EL ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK XI
    ].freeze

    def self.call(country_code:, vat_number:)
      # Net::HTTP alcanza para este caso y evita sumar una dependencia SOAP solo para un endpoint.
      response = perform_request(
        ENDPOINT,
        country_code: country_code,
        vat_number: vat_number
      )

      # Algunos faults vienen con HTTP 500, pero igual conviene parsearlos para no perder el motivo real.
      if fault_body?(response.body)
        parse_response(response.body)
      elsif !response.is_a?(Net::HTTPSuccess)
        raise ServiceUnavailableError, "VIES request failed with HTTP #{response.code}"
      end

      parse_response(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      raise TimeoutError, "VIES request timed out"
    rescue SocketError, SystemCallError, IOError => e
      raise ServiceUnavailableError, "VIES request failed: #{e.message}"
    end

    def self.perform_request(uri, country_code:, vat_number:, redirects_remaining: MAX_REDIRECTS)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.open_timeout = TIMEOUT_SECONDS
        http.read_timeout = TIMEOUT_SECONDS
        http.request(request(uri, country_code:, vat_number:))
      end

      return response unless redirect_response?(response)
      raise ServiceUnavailableError, "VIES redirect limit exceeded" if redirects_remaining.zero?

      perform_request(
        redirect_uri(uri, response),
        country_code: country_code,
        vat_number: vat_number,
        redirects_remaining: redirects_remaining - 1
      )
    end
    private_class_method :perform_request

    def self.request(uri, country_code:, vat_number:)
      Net::HTTP::Post.new(uri).tap do |request|
        request["Content-Type"] = "text/xml; charset=utf-8"
        request["SOAPAction"] = ""
        request.body = soap_body(country_code:, vat_number:)
      end
    end
    private_class_method :request

    def self.redirect_response?(response)
      REDIRECT_CODES.include?(response.code)
    end
    private_class_method :redirect_response?

    def self.redirect_uri(current_uri, response)
      location = response["location"].to_s
      raise ServiceUnavailableError, "VIES redirect response missing location" if location.blank?

      uri = URI.join(current_uri, location)
      unless safe_redirect_uri?(uri)
        raise ServiceUnavailableError, "VIES redirected to an unsupported location"
      end

      uri
    rescue URI::InvalidURIError
      raise ServiceUnavailableError, "VIES returned an invalid redirect location"
    end
    private_class_method :redirect_uri

    def self.safe_redirect_uri?(uri)
      uri.is_a?(URI::HTTPS) && (uri.host == ENDPOINT.host || uri.host.end_with?(".#{ENDPOINT.host}"))
    end
    private_class_method :safe_redirect_uri?

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
      # NONET evita que Nokogiri intente resolver entidades externas al parsear XML no confiable.
      document = Nokogiri::XML(body) { |config| config.strict.noblanks.nonet }
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

    def self.fault_body?(body)
      body.to_s.include?("Fault")
    end
    private_class_method :fault_body?

    def self.fault?(document)
      !document.at_xpath("//*[local-name()='Fault']").nil?
    end
    private_class_method :fault?

    def self.raise_fault(document)
      faultstring = normalize_text(text_at(document, "faultstring"))
      # VIES manda faults tanto por input invalido como por caidas temporales; no todos se tratan igual.
      error_class = Vies::Errors.error_for_fault(faultstring)
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
