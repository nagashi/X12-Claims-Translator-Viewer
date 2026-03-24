defmodule ClaimViewer.Properties.PipelineFidelityPropertiesTest do
  @moduledoc """
  CRITICAL HIPAA property: X12→JSON pipeline fidelity.

  Verifies that the full conversion pipeline:
    JSON sections → Mapper.from_sections → Claim837 struct → Mapper.to_validated_sections → JSON sections
  is an EXACT MIRROR — no field is dropped, mutated, truncated, or reordered.

  This is the "no PHI loss" invariant. If a patient's name, DOB, NPI, diagnosis code,
  or any other field is silently dropped or altered during the pipeline, that's a
  HIPAA data integrity violation.

  Properties tested:
  1. Every known section's data survives the round-trip field-for-field
  2. Service line lists preserve count and order
  3. Nested structures (addresses, contacts, indicators) survive intact
  4. Numeric precision is preserved (charges, units)
  5. The full pipeline is idempotent: running it twice produces identical output
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import ClaimViewer.Generators

  alias ClaimViewer.X12.Mapper

  # Map from section name to known data keys for that section
  @section_field_expectations %{
    "transaction" => ~w(type controlNumber version purpose referenceId date time),
    "submitter" => ~w(name id contact),
    "receiver" => ~w(name id),
    "billing_Provider" => ~w(name taxId npi address),
    "Pay_To_provider" => ~w(name taxId npi address),
    "subscriber" => ~w(firstName lastName id dob sex relationship groupNumber planType address),
    "payer" => ~w(name payerId),
    "claim" =>
      ~w(id totalCharge placeOfService serviceType indicators onsetDate clearinghouseClaimNumber),
    "diagnosis" => ~w(primary secondary),
    "renderingProvider" => ~w(firstName lastName npi),
    "serviceFacility" => ~w(name taxId address),
    "service_Lines" => :list
  }

  describe "full pipeline field-for-field fidelity" do
    property "every field in every section survives the round-trip" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        for input_section <- sections do
          section_name = input_section["section"]
          input_data = input_section["data"]

          output_section =
            Enum.find(output_sections, fn s -> s["section"] == section_name end)

          assert output_section,
                 "Section '#{section_name}' missing from output"

          output_data = output_section["data"]

          case @section_field_expectations[section_name] do
            :list ->
              # Service lines: verify count and each line's fields
              assert is_list(input_data), "Input service_Lines data should be a list"
              assert is_list(output_data), "Output service_Lines data should be a list"

              assert length(output_data) == length(input_data),
                     "Service line count mismatch: input=#{length(input_data)}, output=#{length(output_data)}"

              for {input_line, output_line} <- Enum.zip(input_data, output_data) do
                assert_line_fields_match(input_line, output_line)
              end

            expected_keys when is_list(expected_keys) ->
              for key <- expected_keys do
                input_val = input_data[key]
                output_val = output_data[key]

                assert_field_matches(section_name, key, input_val, output_val)
              end

            nil ->
              # Unknown section — skip (shouldn't happen with our generator)
              :ok
          end
        end
      end
    end
  end

  describe "service line field preservation" do
    @service_line_keys ~w(lineNumber codeQualifier procedureCode charge unitQualifier
                          units diagnosisPointer emergencyIndicator serviceDate placeOfService)

    property "every service line field is preserved exactly" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        input_sl =
          Enum.find(sections, &(&1["section"] == "service_Lines"))

        output_sl =
          Enum.find(output_sections, &(&1["section"] == "service_Lines"))

        if input_sl do
          for {in_line, out_line} <- Enum.zip(input_sl["data"], output_sl["data"]) do
            for key <- @service_line_keys do
              assert_field_matches("service_Lines", key, in_line[key], out_line[key])
            end
          end
        end
      end
    end
  end

  describe "nested structure preservation" do
    property "address fields survive round-trip exactly" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        for section_name <- ~w(billing_Provider Pay_To_provider subscriber serviceFacility) do
          input = Enum.find(sections, &(&1["section"] == section_name))
          output = Enum.find(output_sections, &(&1["section"] == section_name))

          if input && input["data"]["address"] do
            input_addr = input["data"]["address"]
            output_addr = output["data"]["address"]

            for key <- ~w(street city state zip) do
              assert to_string(input_addr[key] || "") == to_string(output_addr[key] || ""),
                     "Address field '#{key}' mismatch in #{section_name}: " <>
                       "#{inspect(input_addr[key])} vs #{inspect(output_addr[key])}"
            end
          end
        end
      end
    end

    property "submitter contact fields survive round-trip" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        input = Enum.find(sections, &(&1["section"] == "submitter"))
        output = Enum.find(output_sections, &(&1["section"] == "submitter"))

        if input && input["data"]["contact"] do
          in_contact = input["data"]["contact"]
          out_contact = output["data"]["contact"]

          for key <- ~w(name phone extension) do
            assert to_string(in_contact[key] || "") == to_string(out_contact[key] || ""),
                   "Contact field '#{key}' mismatch: #{inspect(in_contact[key])} vs #{inspect(out_contact[key])}"
          end
        end
      end
    end

    property "claim indicators map survives round-trip" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        input = Enum.find(sections, &(&1["section"] == "claim"))
        output = Enum.find(output_sections, &(&1["section"] == "claim"))

        if input do
          assert input["data"]["indicators"] == output["data"]["indicators"],
                 "Indicators map mismatch"
        end
      end
    end

    property "diagnosis secondary list survives round-trip" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        input = Enum.find(sections, &(&1["section"] == "diagnosis"))
        output = Enum.find(output_sections, &(&1["section"] == "diagnosis"))

        if input do
          assert input["data"]["primary"] == output["data"]["primary"]
          assert input["data"]["secondary"] == output["data"]["secondary"]
        end
      end
    end
  end

  describe "numeric precision" do
    property "totalCharge numeric value is preserved" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        input = Enum.find(sections, &(&1["section"] == "claim"))
        output = Enum.find(output_sections, &(&1["section"] == "claim"))

        if input do
          in_charge = input["data"]["totalCharge"]
          out_charge = output["data"]["totalCharge"]

          assert in_charge == out_charge,
                 "totalCharge mismatch: #{inspect(in_charge)} vs #{inspect(out_charge)}"
        end
      end
    end

    property "service line charge and units are preserved" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim_struct} = Mapper.from_sections(sections)
        output_sections = Mapper.to_validated_sections(claim_struct)

        input_sl = Enum.find(sections, &(&1["section"] == "service_Lines"))
        output_sl = Enum.find(output_sections, &(&1["section"] == "service_Lines"))

        if input_sl do
          for {in_line, out_line} <- Enum.zip(input_sl["data"], output_sl["data"]) do
            assert in_line["charge"] == out_line["charge"],
                   "Line charge mismatch: #{inspect(in_line["charge"])} vs #{inspect(out_line["charge"])}"

            assert in_line["units"] == out_line["units"],
                   "Line units mismatch: #{inspect(in_line["units"])} vs #{inspect(out_line["units"])}"
          end
        end
      end
    end
  end

  describe "idempotency" do
    property "running the pipeline twice produces identical output" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        {:ok, claim1} = Mapper.from_sections(sections)
        output1 = Mapper.to_validated_sections(claim1)

        {:ok, claim2} = Mapper.from_sections(output1)
        output2 = Mapper.to_validated_sections(claim2)

        assert output1 == output2,
               "Pipeline is not idempotent — second pass produced different output"
      end
    end
  end

  # ===== Assertion Helpers =====

  defp assert_field_matches(section, key, input_val, output_val) do
    # Normalize: structs convert nils to "" via to_string(val || "")
    normalized_input = normalize_value(input_val)
    normalized_output = normalize_value(output_val)

    assert normalized_input == normalized_output,
           "Field '#{key}' mismatch in section '#{section}': " <>
             "input=#{inspect(input_val)} output=#{inspect(output_val)}"
  end

  defp assert_line_fields_match(input_line, output_line) do
    for key <- Map.keys(input_line) do
      assert_field_matches("service_Lines", key, input_line[key], output_line[key])
    end
  end

  defp normalize_value(nil), do: nil
  defp normalize_value(val) when is_map(val), do: val
  defp normalize_value(val) when is_list(val), do: val
  defp normalize_value(val) when is_number(val), do: val
  defp normalize_value(val) when is_binary(val), do: val
  defp normalize_value(val), do: to_string(val)
end
