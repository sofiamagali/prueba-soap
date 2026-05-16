require "test_helper"

class VatValidationsTest < ActionDispatch::IntegrationTest
  test "create stores a valid vat validation" do
    vies_response = {
      valid: true,
      company_name: "Example SL",
      company_address: "Madrid",
      queried_at: Time.zone.local(2026, 5, 15)
    }

    original_call = Vies::CheckVatService.method(:call)
    Vies::CheckVatService.define_singleton_method(:call) { |country_code:, vat_number:| vies_response }

    post api_v1_vat_validations_path, params: { country_code: "es", vat_number: "A12345678" }

    assert_response :created
    assert_equal "ES", response.parsed_body["country_code"]
    assert_equal "A12345678", response.parsed_body["vat_number"]
    assert_equal true, response.parsed_body["valid"]
    assert_equal "Example SL", response.parsed_body["company_name"]
  ensure
    Vies::CheckVatService.define_singleton_method(:call, original_call) if original_call
  end

  test "create returns validation errors for invalid params" do
    post api_v1_vat_validations_path, params: { country_code: "ARG", vat_number: "" }

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Country code is invalid"
    assert_includes response.parsed_body["errors"], "Vat number can't be blank"
  end

  test "show returns an existing vat validation" do
    vat_validation = VatValidation.create!(
      country_code: "ES",
      vat_number: "A12345678",
      valid: true,
      company_name: "Example SL",
      company_address: "Madrid",
      queried_at: Time.zone.local(2026, 5, 15)
    )

    get api_v1_vat_validation_path(vat_validation)

    assert_response :success
    assert_equal vat_validation.id, response.parsed_body["id"]
    assert_equal "ES", response.parsed_body["country_code"]
    assert_equal true, response.parsed_body["valid"]
  end

  test "show returns not found for missing vat validation" do
    get api_v1_vat_validation_path(0)

    assert_response :not_found
    assert_equal "Vat validation not found", response.parsed_body["error"]
  end

  test "index filters and paginates vat validations" do
    VatValidation.create!(
      country_code: "ES",
      vat_number: "A12345678",
      valid: true,
      queried_at: Time.zone.local(2026, 5, 10)
    )
    VatValidation.create!(
      country_code: "ES",
      vat_number: "B12345678",
      valid: true,
      queried_at: Time.zone.local(2026, 5, 12)
    )
    VatValidation.create!(
      country_code: "FR",
      vat_number: "C12345678",
      valid: false,
      queried_at: Time.zone.local(2026, 5, 12)
    )

    get api_v1_vat_validations_path, params: {
      country_code: "es",
      valid: "true",
      date_from: "2026-05-10",
      date_to: "2026-05-12",
      page: 1,
      per_page: 1
    }

    assert_response :success
    assert_equal 1, response.parsed_body["items"].size
    assert_equal 1, response.parsed_body["pagination"]["page"]
    assert_equal 1, response.parsed_body["pagination"]["per_page"]
    assert_equal 2, response.parsed_body["pagination"]["total_count"]
    assert_equal 2, response.parsed_body["pagination"]["total_pages"]
    assert_equal "ES", response.parsed_body["items"].first["country_code"]
    assert_equal true, response.parsed_body["items"].first["valid"]
  end

  test "index returns validation error for invalid date_from" do
    get api_v1_vat_validations_path, params: { date_from: "not-a-date" }

    assert_response :unprocessable_entity
    assert_equal ["date_from is invalid"], response.parsed_body["errors"]
  end

  test "index returns validation error for invalid date_to" do
    get api_v1_vat_validations_path, params: { date_to: "not-a-date" }

    assert_response :unprocessable_entity
    assert_equal ["date_to is invalid"], response.parsed_body["errors"]
  end
end
