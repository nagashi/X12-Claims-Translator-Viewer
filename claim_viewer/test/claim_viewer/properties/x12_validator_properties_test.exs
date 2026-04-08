defmodule ClaimViewer.Properties.X12ValidatorPropertiesTest do
  @moduledoc """
  Property-based fuzz tests for X12Validator.

  HIPAA properties verified:
  - Random binary content never crashes the validator
  - Always returns {:ok, _} or {:error, _}
  - Error reasons are always strings
  - Truncated or corrupted X12 content never causes unhandled exceptions
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag :io

  describe "validate_file_content fuzz robustness" do
    property "random binary files never crash — always return {:ok, _} or {:error, _}" do
      check all(
              content <- StreamData.binary(min_length: 0, max_length: 1000),
              max_runs: 500
            ) do
        # Write to temp file
        path = Path.join(System.tmp_dir!(), "fuzz_#{:os.system_time(:nanosecond)}.x12")
        File.write!(path, content)

        try do
          result = ClaimViewer.X12Validator.validate_file_content(path)

          case result do
            {:ok, count} ->
              assert is_integer(count)
              assert count > 0

            {:error, reason} ->
              assert is_binary(reason)
          end
        after
          File.rm(path)
        end
      end
    end

    property "ISA-prefixed but truncated content never crashes" do
      check all(
              suffix <- StreamData.binary(min_length: 0, max_length: 200),
              max_runs: 200
            ) do
        content = "ISA" <> suffix
        path = Path.join(System.tmp_dir!(), "isa_fuzz_#{:os.system_time(:nanosecond)}.x12")
        File.write!(path, content)

        try do
          result = ClaimViewer.X12Validator.validate_file_content(path)

          case result do
            {:ok, count} -> assert is_integer(count)
            {:error, reason} -> assert is_binary(reason)
          end
        after
          File.rm(path)
        end
      end
    end

    property "nonexistent file paths return {:error, _} — never crash" do
      check all(
              path <- StreamData.string(:alphanumeric, min_length: 10, max_length: 50),
              max_runs: 100
            ) do
        full_path = Path.join(System.tmp_dir!(), "nonexistent_#{path}.x12")
        result = ClaimViewer.X12Validator.validate_file_content(full_path)
        assert {:error, reason} = result
        assert is_binary(reason)
      end
    end
  end
end
