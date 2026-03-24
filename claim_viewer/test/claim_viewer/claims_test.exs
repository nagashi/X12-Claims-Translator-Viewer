defmodule ClaimViewer.ClaimsTest do
  use ClaimViewer.DataCase, async: true

  alias ClaimViewer.Claims

  @sample_sections [
    %{
      "section" => "subscriber",
      "data" => %{"firstName" => "Jane", "lastName" => "Doe", "dob" => "1990-01-15"}
    },
    %{"section" => "payer", "data" => %{"name" => "BlueCross"}},
    %{"section" => "billing_Provider", "data" => %{"name" => "Dr. Smith", "npi" => "1234567890"}},
    %{"section" => "Pay_To_provider", "data" => %{"name" => "Pay Corp"}},
    %{
      "section" => "renderingProvider",
      "data" => %{"firstName" => "John", "npi" => "0987654321"}
    },
    %{
      "section" => "claim",
      "data" => %{
        "clearinghouseClaimNumber" => "CLM-001",
        "totalCharge" => 150.00,
        "indicators" => %{"a" => "Y", "b" => "A"}
      }
    },
    %{
      "section" => "service_Lines",
      "data" => [
        %{
          "serviceDate" => "2025-06-15",
          "procedureCode" => "99213",
          "charge" => 75.0,
          "lineNumber" => 1
        },
        %{
          "serviceDate" => "2025-06-16",
          "procedureCode" => "99214",
          "charge" => 75.0,
          "lineNumber" => 2
        }
      ]
    }
  ]

  defp create_sample_claim(overrides \\ %{}) do
    search_fields = Claims.extract_search_fields(@sample_sections)

    attrs =
      %{raw_json: @sample_sections, date_of_service: ~D[2025-06-15]}
      |> Map.merge(search_fields)
      |> Map.merge(overrides)

    {:ok, claim} = Claims.create_claim(attrs)
    claim
  end

  describe "create_claim/1" do
    test "inserts a valid claim" do
      assert {:ok, claim} = Claims.create_claim(%{raw_json: @sample_sections})
      assert claim.id
      assert claim.raw_json == @sample_sections
    end

    test "rejects missing raw_json" do
      assert {:error, changeset} = Claims.create_claim(%{})
      assert %{raw_json: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_claim!/1" do
    test "returns the claim" do
      claim = create_sample_claim()
      assert Claims.get_claim!(claim.id).id == claim.id
    end

    test "raises for nonexistent ID" do
      assert_raise Ecto.NoResultsError, fn -> Claims.get_claim!(0) end
    end
  end

  describe "extract_search_fields/1" do
    test "extracts subscriber, payer, billing, rendering, and claim fields" do
      fields = Claims.extract_search_fields(@sample_sections)
      assert fields.member_first_name == "Jane"
      assert fields.member_last_name == "Doe"
      assert fields.payer_name == "BlueCross"
      assert fields.billing_provider_name == "Dr. Smith"
      assert fields.rendering_provider_npi == "0987654321"
      assert fields.clearinghouse_claim_number == "CLM-001"
    end

    test "returns empty map for non-list input" do
      assert Claims.extract_search_fields("not a list") == %{}
    end
  end

  describe "extract_date_of_service/1" do
    test "extracts date from first service line" do
      assert {:ok, ~D[2025-06-15]} = Claims.extract_date_of_service(@sample_sections)
    end

    test "returns error when no service_Lines section" do
      sections = Enum.reject(@sample_sections, &(&1["section"] == "service_Lines"))
      assert {:error, :no_service_lines} = Claims.extract_date_of_service(sections)
    end

    test "returns error for invalid date" do
      bad = [%{"section" => "service_Lines", "data" => [%{"serviceDate" => "not-a-date"}]}]
      assert {:error, :invalid_date} = Claims.extract_date_of_service(bad)
    end
  end

  describe "list_claims/2" do
    test "returns empty when no search criteria" do
      create_sample_claim()
      {claims, meta} = Claims.list_claims(%{}, %{page: 1, per_page: 10})
      assert claims == []
      assert meta.total_count == 0
    end

    test "filters by member last name" do
      create_sample_claim()
      filters = %{"member_last" => "Doe"}
      {claims, meta} = Claims.list_claims(filters, %{page: 1, per_page: 10})
      assert length(claims) == 1
      assert meta.total_count == 1
    end

    test "filters by payer name" do
      create_sample_claim()
      filters = %{"payer" => "BlueCross"}
      {claims, _meta} = Claims.list_claims(filters, %{page: 1, per_page: 10})
      assert length(claims) == 1
    end

    test "filters by status approved" do
      create_sample_claim()
      filters = %{"status" => "approved"}
      {claims, _meta} = Claims.list_claims(filters, %{page: 1, per_page: 10})
      assert length(claims) == 1
    end

    test "pagination works" do
      for _ <- 1..3, do: create_sample_claim()
      filters = %{"member_last" => "Doe"}

      {claims, meta} = Claims.list_claims(filters, %{page: 1, per_page: 2})
      assert length(claims) == 2
      assert meta.total_count == 3
      assert meta.total_pages == 2

      {claims2, _} = Claims.list_claims(filters, %{page: 2, per_page: 2})
      assert length(claims2) == 1
    end

    test "date range filter works" do
      create_sample_claim()
      filters = %{"service_from" => "2025-06-01", "service_to" => "2025-06-30"}
      {claims, _} = Claims.list_claims(filters, %{page: 1, per_page: 10})
      assert length(claims) == 1

      # Out of range
      filters2 = %{"service_from" => "2026-01-01"}
      {claims2, _} = Claims.list_claims(filters2, %{page: 1, per_page: 10})
      assert claims2 == []
    end
  end

  describe "dashboard_stats/0" do
    test "returns correct structure with zero claims" do
      stats = Claims.dashboard_stats()
      assert stats.total_claims == 0
      assert stats.approved_count == 0
      assert stats.pending_count == 0
      assert stats.this_month_count == 0
    end

    test "counts approved and pending correctly" do
      # Approved claim (all indicators Y/A/I)
      create_sample_claim()

      # Pending claim (no indicators)
      pending_sections = [
        %{"section" => "claim", "data" => %{"totalCharge" => 100.0, "indicators" => %{}}},
        %{"section" => "subscriber", "data" => %{"firstName" => "Bob"}}
      ]

      {:ok, _} = Claims.create_claim(%{raw_json: pending_sections})

      stats = Claims.dashboard_stats()
      assert stats.total_claims == 2
      assert stats.approved_count == 1
      assert stats.pending_count == 1
    end
  end
end
