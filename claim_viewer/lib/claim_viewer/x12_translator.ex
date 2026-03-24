defmodule ClaimViewer.X12Translator do
  @moduledoc """
  Translates X12 files to JSON using Python parser.

  Runs the Python script inside a Task with a hard 30-second timeout.
  Temp files are always cleaned up regardless of success or failure.
  """

  require Logger

  @python_script_path Path.join(:code.priv_dir(:claim_viewer), "python/parser_for_viewer.py")
  @timeout_ms 30_000

  @doc """
  Translate an X12 file to parsed JSON sections.

  Returns `{:ok, json_data}` or `{:error, reason}`.
  """
  @spec translate_x12_to_json(String.t()) :: {:ok, term()} | {:error, String.t()}
  def translate_x12_to_json(x12_file_path) do
    case find_python() do
      {:ok, python_cmd} ->
        run_translation(python_cmd, x12_file_path)

      {:error, _} = err ->
        err
    end
  end

  # ===== Private =====

  defp find_python do
    case System.find_executable("python3") || System.find_executable("python") do
      nil -> {:error, "Python not found. Please install Python 3."}
      cmd -> {:ok, cmd}
    end
  end

  defp run_translation(python_cmd, x12_file_path) do
    temp_output =
      System.tmp_dir!()
      |> Path.join("x12_output_#{:os.system_time(:millisecond)}.json")

    task =
      Task.async(fn ->
        System.cmd(python_cmd, [@python_script_path, x12_file_path, temp_output],
          stderr_to_stdout: true
        )
      end)

    try do
      case Task.await(task, @timeout_ms) do
        {_output, 0} ->
          read_and_parse_json(temp_output)

        {error_output, _exit_code} ->
          {:error, "Python script failed: #{error_output}"}
      end
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        Logger.error("X12 translation timed out after #{@timeout_ms}ms")
        {:error, "X12 translation timed out after #{div(@timeout_ms, 1000)} seconds"}
    after
      File.rm(temp_output)
    end
  end

  defp read_and_parse_json(path) do
    case File.read(path) do
      {:ok, json_string} ->
        case Jason.decode(json_string) do
          {:ok, json_data} -> {:ok, json_data}
          {:error, reason} -> {:error, "JSON parse error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read output JSON: #{inspect(reason)}"}
    end
  end
end
