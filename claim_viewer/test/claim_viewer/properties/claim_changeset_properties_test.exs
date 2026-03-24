defmodule ClaimViewer.Properties.ClaimChangesetPropertiesTest do
  @moduledoc """
  Property-based tests for Claim changeset validations.

  HIPAA properties verified:
  - Valid data with valid NPIs always produces a valid changeset
  - Invalid NPIs are ALWAYS rejected (no false accepts)
  - Missing raw_json is ALWAYS rejected
  - Fuzz data never causes changeset to crash (always returns valid or invalid)
  """
  use ClaimViewer.DataCase, async: true
  use ExUnitProperties

  import ClaimViewer.Generators

  alias ClaimViewer.Claims.Claim

  describe "valid data always accepted" do
    property "valid attrs with valid NPIs produce valid changeset" do
      check all(attrs <- gen_valid_claim_attrs(), max_runs: 200) do
        changeset = Claim.changeset(%Claim{}, attrs)

        assert changeset.valid?,
               "Expected valid changeset, got errors: #{inspect(changeset.errors)}"
      end
    end
  end

  describe "NPI validation" do
    property "invalid billing_provider_npi is ALWAYS rejected" do
      check all(
              bad_npi <- gen_invalid_npi(),
              sections <- gen_valid_sections(),
              max_runs: 200
            ) do
        attrs = %{raw_json: sections, billing_provider_npi: bad_npi}
        changeset = Claim.changeset(%Claim{}, attrs)

        if bad_npi != nil and bad_npi != "" do
          refute changeset.valid?,
                 "NPI '#{bad_npi}' should have been rejected but changeset was valid"
        end
      end
    end

    property "invalid rendering_provider_npi is ALWAYS rejected" do
      check all(
              bad_npi <- gen_invalid_npi(),
              sections <- gen_valid_sections(),
              max_runs: 200
            ) do
        attrs = %{raw_json: sections, rendering_provider_npi: bad_npi}
        changeset = Claim.changeset(%Claim{}, attrs)

        if bad_npi != nil and bad_npi != "" do
          refute changeset.valid?,
                 "NPI '#{bad_npi}' should have been rejected but changeset was valid"
        end
      end
    end

    property "valid 10-digit NPIs are ALWAYS accepted" do
      check all(
              npi <- gen_npi(),
              sections <- gen_valid_sections(),
              max_runs: 200
            ) do
        attrs = %{raw_json: sections, billing_provider_npi: npi, rendering_provider_npi: npi}
        changeset = Claim.changeset(%Claim{}, attrs)
        assert changeset.valid?, "Valid NPI '#{npi}' was rejected: #{inspect(changeset.errors)}"
      end
    end
  end

  describe "raw_json always required" do
    property "missing raw_json is always rejected regardless of other attrs" do
      check all(
              npi <- gen_npi(),
              name <- gen_safe_string(min_length: 1, max_length: 30),
              max_runs: 100
            ) do
        attrs = %{
          member_first_name: name,
          billing_provider_npi: npi,
          rendering_provider_npi: npi
        }

        changeset = Claim.changeset(%Claim{}, attrs)
        refute changeset.valid?
        assert %{raw_json: _} = errors_on(changeset)
      end
    end
  end

  describe "fuzz robustness" do
    property "fuzz attrs never crash changeset — always returns valid or invalid" do
      check all(attrs <- gen_fuzz_claim_attrs(), max_runs: 200) do
        changeset = Claim.changeset(%Claim{}, attrs)
        # Must be a changeset regardless
        assert %Ecto.Changeset{} = changeset
      end
    end

    property "fuzz attrs that pass changeset can be inserted" do
      check all(attrs <- gen_fuzz_claim_attrs(), max_runs: 50) do
        changeset = Claim.changeset(%Claim{}, attrs)

        if changeset.valid? do
          assert {:ok, _claim} = Repo.insert(changeset)
        end
      end
    end
  end
end
