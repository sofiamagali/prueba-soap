require "cgi"
require "net/http"
require "nokogiri"

module Vies
  class CheckVatService
    ENDPOINT = URI("https://ec.europa.eu/taxation_customs/vies/services/checkVatService").freeze
    TIMEOUT_SECONDS = 10

    def self.call(country_code:, vat_number:)
      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true) do |http|
        http.open_timeout = TIMEOUT_SECONDS
        http.read_timeout = TIMEOUT_SECONDS
        http.request(request(country_code:, vat_number:))
      end

      raise "VIES request failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parse_response(response.body)
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
      fault = text_at(document, "Fault")

      raise "VIES SOAP fault: #{fault.strip}" if fault

      {
        valid: text_at(document, "valid") == "true",
        company_name: normalize_text(text_at(document, "name")),
        company_address: normalize_text(text_at(document, "address")),
        queried_at: Time.respond_to?(:current) ? Time.current : Time.now
      }
    end
    private_class_method :parse_response

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
