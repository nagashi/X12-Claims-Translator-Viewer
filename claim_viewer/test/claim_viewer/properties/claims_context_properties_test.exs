defmodule ClaimViewer.Properties.ClaimsContextPropertiesTest do
  @moduledoc """
  Property-based tests for the Claims context.

  HIPAA properties verified:
  - extract_search_fields never crashes on valid section lists
  - extract_date_of_service never crashes on valid section lists
  - LIKE wildcard injection: searching for % or _ never matches all rows
  - Filter composition: adding more filters never increases result count
  - list_claims never crashes on any filter combination
  """
  use ClaimViewer.DataCase, async: true
  use ExUnitProperties

  import ClaimViewer.Generators

  alias ClaimViewer.Claims

  defp insert_sample_claim(sections) do
    search_fields = Claims.extract_search_fields(sections)

    date_of_service =
      case Claims.extract_date_of_service(sections) do
        {:ok, d} -> d
        _ -> nil
      end

    attrs =
      %{raw_json: sections, date_of_service: date_of_service}
      |> Map.merge(search_fields)

    {:ok, claim} = Claims.create_claim(attrs)
    claim
  end

  describe "extract_search_fields" do
    @tag max_runs: 200
    property "never crashes on generated valid sections" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        fields = Claims.extract_search_fields(sections)
        assert is_map(fields)

        assert Map.has_key?(fields, :member_first_name)
        assert Map.has_key?(fields, :member_last_name)
        assert Map.has_key?(fields, :payer_name)
        assert Map.has_key?(fields, :billing_provider_name)
        assert Map.has_key?(fields, :rendering_provider_npi)
        assert Map.has_key?(fields, :clearinghouse_claim_number)
      end
    end

    @tag max_runs: 200
    property "extracted fields are always strings or nil" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        fields = Claims.extract_search_fields(sections)

        for {_key, val} <- fields do
          assert is_nil(val) or is_binary(val),
                 "Expected string or nil, got: #{inspect(val)}"
        end
      end
    end
  end

  describe "extract_date_of_service" do
    @tag max_runs: 200
    property "always returns {:ok, date} or {:error, _} — never crashes" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        result = Claims.extract_date_of_service(sections)

        case result do
          {:ok, date} -> assert %Date{} = date
          {:error, reason} -> assert is_atom(reason)
        end
      end
    end
  end

  describe "LIKE wildcard injection" do
    @tag max_runs: 50
    property "searching with % or _ does not match unrelated claims" do
      check all(
              sections <- gen_valid_sections(),
              wildcard <- gen_sql_wildcard_string(),
              max_runs: 50
            ) do
        # Insert claim with known data
        _claim = insert_sample_claim(sections)

        # Search with wildcard — should not match unless the claim actually contains the wildcard
        filters = %{"payer" => wildcard}
        {results, _meta} = Claims.list_claims(filters, %{page: 1, per_page: 100})

        if String.length(wildcard) >= 2 do
          for result <- results do
            # Every matched claim must actually contain the search term in its payer_name
            # (case-insensitive substring match after escaping)
            result_payer = String.downcase(result.payer_name || "")
            search_lower = String.downcase(wildcard)

            assert String.contains?(result_payer, search_lower),
                   "Wildcard '#{wildcard}' matched payer '#{result.payer_name}' which doesn't contain it"
          end
        end
      end
    end
  end

  describe "filter composition" do
    @tag max_runs: 30
    property "adding more filters to an active search never increases result count" do
      check all(sections <- gen_valid_sections(), max_runs: 30) do
        claim = insert_sample_claim(sections)

        # Use the actual inserted claim's field values (guaranteed >= 2 chars if present)
        last = claim.member_last_name
        payer = claim.payer_name

        # Only test when we have a meaningful base filter
        if last && String.length(last) >= 2 do
          base_filters = %{"member_last" => last}
          {_base_results, base_meta} = Claims.list_claims(base_filters, %{page: 1, per_page: 100})

          if payer && String.length(payer) >= 2 do
            more_filters = Map.put(base_filters, "payer", payer)

            {_more_results, more_meta} =
              Claims.list_claims(more_filters, %{page: 1, per_page: 100})

            assert more_meta.total_count <= base_meta.total_count,
                   "Adding payer filter increased results: #{more_meta.total_count} > #{base_meta.total_count}"
          end
        end
      end
    end
  end

  describe "list_claims never crashes" do
    @tag max_runs: 100
    property "arbitrary filter combinations never cause exceptions" do
      check all(
              first <- gen_fuzz_string(),
              last <- gen_fuzz_string(),
              payer <- gen_fuzz_string(),
              status <- StreamData.member_of(["", "approved", "pending", "bogus"]),
              max_runs: 100
            ) do
        filters = %{
          "member_first" => first || "",
          "member_last" => last || "",
          "payer" => payer || "",
          "status" => status
        }

        {results, meta} = Claims.list_claims(filters, %{page: 1, per_page: 10})
        assert is_list(results)
        assert is_map(meta)
      end
    end
  end
end
