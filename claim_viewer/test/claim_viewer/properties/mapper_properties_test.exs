defmodule ClaimViewer.Properties.MapperPropertiesTest do
  @moduledoc """
  Property-based tests for X12.Mapper.

  HIPAA properties verified:
  - Section ordering independence: shuffled sections produce same struct
  - Unknown section tolerance: extra sections are silently skipped
  - Validation always rejects malformed input shapes
  - from_sections never crashes on well-shaped input
  - Round-trip: to_validated_sections(from_sections(s)) produces valid sections
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import ClaimViewer.Generators

  alias ClaimViewer.X12.Mapper

  describe "section ordering independence" do
    property "shuffled sections produce identical Claim837 struct" do
      check all(sections <- gen_valid_sections(), max_runs: 100) do
        {:ok, claim_ordered} = Mapper.from_sections(sections)
        shuffled = Enum.shuffle(sections)
        {:ok, claim_shuffled} = Mapper.from_sections(shuffled)
        assert claim_ordered == claim_shuffled
      end
    end
  end

  describe "unknown section tolerance" do
    property "extra unknown sections are silently ignored" do
      check all(
              sections <- gen_valid_sections(),
              unknown_name <- StreamData.string(:alphanumeric, min_length: 5, max_length: 20),
              max_runs: 100
            ) do
        extra = %{"section" => "unknown_#{unknown_name}", "data" => %{"foo" => "bar"}}
        with_extra = sections ++ [extra]
        {:ok, claim_without} = Mapper.from_sections(sections)
        {:ok, claim_with} = Mapper.from_sections(with_extra)
        assert claim_without == claim_with
      end
    end
  end

  describe "from_sections never crashes on valid shapes" do
    property "always returns {:ok, _} for generated valid sections" do
      check all(sections <- gen_valid_sections(), max_runs: 200) do
        assert {:ok, claim} = Mapper.from_sections(sections)
        assert is_struct(claim, ClaimViewer.X12.Claim837)
      end
    end
  end

  describe "round-trip through to_validated_sections" do
    property "to_validated_sections produces valid section list" do
      check all(sections <- gen_valid_sections(), max_runs: 100) do
        {:ok, claim} = Mapper.from_sections(sections)
        validated = Mapper.to_validated_sections(claim)

        assert is_list(validated)
        assert length(validated) == 12

        for section <- validated do
          assert is_binary(section["section"])
          assert not is_nil(section["data"])
        end
      end
    end

    property "double round-trip produces identical struct" do
      check all(sections <- gen_valid_sections(), max_runs: 100) do
        {:ok, claim1} = Mapper.from_sections(sections)
        validated = Mapper.to_validated_sections(claim1)
        {:ok, claim2} = Mapper.from_sections(validated)
        assert claim1 == claim2
      end
    end
  end

  describe "validation rejects malformed input" do
    property "non-map elements always produce error" do
      check all(
              bad <-
                StreamData.one_of([
                  StreamData.binary(),
                  StreamData.integer(),
                  StreamData.constant(nil),
                  StreamData.list_of(StreamData.integer(), min_length: 1, max_length: 3)
                ]),
              max_runs: 100
            ) do
        result = Mapper.from_sections([bad])
        assert {:error, msg} = result
        assert is_binary(msg)
      end
    end

    property "sections missing 'data' key always produce error" do
      check all(
              name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
              max_runs: 100
            ) do
        result = Mapper.from_sections([%{"section" => name}])
        assert {:error, msg} = result
        assert msg =~ "missing"
      end
    end

    property "sections with non-map/non-list data always produce error" do
      check all(
              name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
              bad_data <-
                StreamData.one_of([
                  StreamData.integer(),
                  StreamData.binary(min_length: 1)
                ]),
              max_runs: 100
            ) do
        result = Mapper.from_sections([%{"section" => name, "data" => bad_data}])
        assert {:error, msg} = result
        assert msg =~ "invalid"
      end
    end
  end
end
