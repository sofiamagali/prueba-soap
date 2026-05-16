require "test_helper"

Vies::CheckVatService

class VatValidationsTest < ActionDispatch::IntegrationTest
  test "create stores a valid vat validation" do
    vies_response = {
      valid: true,
      company_name: "Example SL",
      company_address: "Madrid",
      queried_at: Time.zone.local(2026, 5, 15)
    }

    stub_vies_call(vies_response) do
      post api_v1_vat_validations_path, params: { country_code: "es", vat_number: "A12345678" }
    end

    assert_response :created
    assert_equal "ES", response.parsed_body["country_code"]
    assert_equal "A12345678", response.parsed_body["vat_number"]
    assert_equal "completed", response.parsed_body["status"]
    assert_equal true, response.parsed_body["valid"]
    assert_equal "Example SL", response.parsed_body["company_name"]
    assert_equal false, response.parsed_body["cached"]
  end

  test "create returns validation errors for invalid params" do
    post api_v1_vat_validations_path, params: { country_code: "ARG", vat_number: "" }

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Country code is invalid"
    assert_includes response.parsed_body["errors"], "Vat number can't be blank"
  end

  test "create returns cached vat validation without calling VIES again" do
    VatValidation.create!(
      country_code: "ES",
      vat_number: "A12345678",
      vies_valid: true,
      company_name: "Cached SL",
      company_address: "Madrid",
      status: "completed",
      queried_at: Time.current
    )

    calls = 0
    stub_vies_call(->(**) { calls += 1 }) do
      post api_v1_vat_validations_path, params: { country_code: "es", vat_number: "A12345678" }
    end

    assert_response :created
    assert_equal true, response.parsed_body["cached"]
    assert_equal "completed", response.parsed_body["status"]
    assert_equal "Cached SL", response.parsed_body["company_name"]
    assert_equal 0, calls
    assert_equal 1, VatValidation.where(country_code: "ES", vat_number: "A12345678").count
    assert_equal 0, VatValidationWorker.jobs.size
  end

  test "create enqueues a pending validation when VIES fails" do
    stub_vies_error(Vies::InvalidInputError, "INVALID_INPUT") do
      post api_v1_vat_validations_path, params: { country_code: "ES", vat_number: "INVALID" }
    end

    assert_response :accepted
    assert_equal "pending", response.parsed_body["status"]
    assert_equal 1, VatValidationWorker.jobs.size

    vat_validation = VatValidation.find(response.parsed_body["id"])
    assert_equal "pending", vat_validation.status
  end

  test "create enqueues a pending validation when VIES times out" do
    stub_vies_error(Vies::TimeoutError, "VIES request timed out") do
      post api_v1_vat_validations_path, params: { country_code: "ES", vat_number: "TIMEOUT" }
    end

    assert_response :accepted
    assert_equal "pending", response.parsed_body["status"]
    assert_equal 1, VatValidationWorker.jobs.size
  end

  test "worker completes a pending vat validation when VIES succeeds" do
    vat_validation = VatValidation.create!(
      country_code: "ES",
      vat_number: "A12345678",
      status: "pending"
    )
    vies_response = {
      valid: true,
      company_name: "Worker SL",
      company_address: "Barcelona",
      queried_at: Time.zone.local(2026, 5, 16)
    }

    stub_vies_call(vies_response) do
      VatValidationWorker.new.perform(vat_validation.id)
    end

    vat_validation.reload
    assert_equal "completed", vat_validation.status
    assert_equal true, vat_validation.vies_valid
    assert_equal "Worker SL", vat_validation.company_name
  end

  test "worker marks a pending vat validation as failed when VIES fails" do
    vat_validation = VatValidation.create!(
      country_code: "ES",
      vat_number: "A12345678",
      status: "pending"
    )

    stub_vies_error(Vies::ServiceUnavailableError, "SERVICE_UNAVAILABLE") do
      VatValidationWorker.new.perform(vat_validation.id)
    end

    assert_equal "failed", vat_validation.reload.status
  end

  test "show returns an existing vat validation" do
    vat_validation = VatValidation.create!(
      country_code: "ES",
      vat_number: "A12345678",
      vies_valid: true,
      company_name: "Example SL",
      company_address: "Madrid",
      status: "completed",
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
      vies_valid: true,
      queried_at: Time.zone.local(2026, 5, 10)
    )
    VatValidation.create!(
      country_code: "ES",
      vat_number: "B12345678",
      vies_valid: true,
      queried_at: Time.zone.local(2026, 5, 12)
    )
    VatValidation.create!(
      country_code: "FR",
      vat_number: "C12345678",
      vies_valid: false,
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

  test "stats returns totals percentages and top countries" do
    2.times do |index|
      VatValidation.create!(
        country_code: "ES",
        vat_number: "A1234567#{index}",
        vies_valid: true,
        status: "completed",
        queried_at: Time.zone.local(2026, 5, 15)
      )
    end
    VatValidation.create!(
      country_code: "FR",
      vat_number: "B12345678",
      vies_valid: false,
      status: "completed",
      queried_at: Time.zone.local(2026, 5, 15)
    )
    VatValidation.create!(
      country_code: "FR",
      vat_number: "PENDING123",
      status: "pending",
      queried_at: Time.zone.local(2026, 5, 15)
    )
    VatValidation.create!(
      country_code: "IT",
      vat_number: "FAILED123",
      status: "failed",
      queried_at: Time.zone.local(2026, 5, 15)
    )

    get stats_api_v1_vat_validations_path

    assert_response :success
    assert_equal 5, response.parsed_body["total_validations"]
    assert_equal 3, response.parsed_body["completed_validations"]
    assert_equal 1, response.parsed_body["pending_validations"]
    assert_equal 1, response.parsed_body["failed_validations"]
    assert_equal 66.67, response.parsed_body["valid_percentage"]
    assert_equal 33.33, response.parsed_body["invalid_percentage"]
    assert_equal [
      { "country_code" => "ES", "count" => 2 },
      { "country_code" => "FR", "count" => 2 },
      { "country_code" => "IT", "count" => 1 }
    ], response.parsed_body["top_countries"]
  end

  private

  def stub_vies_call(response)
    original_call = Vies::CheckVatService.method(:call)
    Vies::CheckVatService.define_singleton_method(:call) do |country_code:, vat_number:|
      response.respond_to?(:call) ? response.call(country_code:, vat_number:) : response
    end

    yield
  ensure
    Vies::CheckVatService.define_singleton_method(:call, original_call) if original_call
  end

  def stub_vies_error(error_class, message, &block)
    stub_vies_call(->(**) { raise error_class, message }, &block)
  end
end
