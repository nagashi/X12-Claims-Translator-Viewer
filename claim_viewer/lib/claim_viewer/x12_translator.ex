defmodule ClaimViewer.X12Translator do
  @moduledoc """
  Translates X12 files to JSON using Python parser
  """

  @python_script_path Path.join(:code.priv_dir(:claim_viewer), "python/parser_for_viewer.py")

  def translate_x12_to_json(x12_file_path) do
    # Generate temp output file path
    temp_output = System.tmp_dir!()
                  |> Path.join("x12_output_#{:os.system_time(:millisecond)}.json")

        # Use python3 for Mac compatibility (fallback to python)
    python_cmd =
      System.find_executable("python3") ||
      System.find_executable("python") ||
      raise("Python not found. Please install Python 3.")

    # Call Python script
    case System.cmd("python", [@python_script_path, x12_file_path, temp_output], stderr_to_stdout: true) do
      {_output, 0} ->
        # Success - read JSON
        case File.read(temp_output) do
          {:ok, json_string} ->
            # Clean up temp file
            File.rm(temp_output)

            # Parse JSON
            case Jason.decode(json_string) do
              {:ok, json_data} -> {:ok, json_data}
              {:error, reason} -> {:error, "JSON parse error: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "Failed to read output JSON: #{inspect(reason)}"}
        end

      {error_output, _exit_code} ->
        {:error, "Python script failed: #{error_output}"}
    end
  end
end
