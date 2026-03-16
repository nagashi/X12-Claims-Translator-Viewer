defmodule ClaimViewer.X12Validator do
  @moduledoc """
  Validates that a file contains valid X12 837 content by inspecting
  the interchange envelope structure (ISA/IEA, GS/GE, ST/SE).

  File extensions are irrelevant — only the content matters.
  A single interchange can contain multiple transaction sets.
  """

  @doc """
  Validates file content is a valid X12 837 interchange.

  Returns `{:ok, transaction_set_count}` on success, where
  `transaction_set_count` is the number of ST*837 transaction sets found.

  Returns `{:error, reason}` if the file is not valid X12 837 content.
  """
  @spec validate_file_content(String.t()) :: {:ok, pos_integer()} | {:error, String.t()}
  def validate_file_content(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        validate_content(content)

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  end

  defp validate_content(content) do
    content = String.trim(content)

    with :ok <- validate_isa_header(content),
         {:ok, segment_terminator} <- detect_segment_terminator(content),
         segments = split_segments(content, segment_terminator),
         :ok <- validate_iea_trailer(segments),
         :ok <- validate_gs_ge_envelopes(segments),
         {:ok, count} <- validate_st_se_transaction_sets(segments) do
      {:ok, count}
    end
  end

  # ISA segment is always exactly 106 characters (fixed-length) and starts with "ISA"
  defp validate_isa_header(content) do
    if String.starts_with?(content, "ISA") do
      :ok
    else
      {:error, "Not a valid X12 file: missing ISA interchange header"}
    end
  end

  # The segment terminator is the character at position 105 of the ISA segment
  # (ISA is always 106 chars including the terminator)
  defp detect_segment_terminator(content) do
    if String.length(content) >= 106 do
      # Element separator is at position 3, sub-element separator at 104,
      # segment terminator at 105
      terminator = String.at(content, 105)
      {:ok, terminator}
    else
      {:error, "File too short to be a valid X12 interchange"}
    end
  end

  defp split_segments(content, terminator) do
    content
    |> String.split(terminator)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp validate_iea_trailer(segments) do
    last_segment = List.last(segments)

    if last_segment && String.starts_with?(last_segment, "IEA") do
      :ok
    else
      {:error, "Missing IEA interchange trailer"}
    end
  end

  defp validate_gs_ge_envelopes(segments) do
    gs_count = Enum.count(segments, &String.starts_with?(&1, "GS"))
    ge_count = Enum.count(segments, &String.starts_with?(&1, "GE"))

    cond do
      gs_count == 0 ->
        {:error, "Missing GS functional group header"}

      gs_count != ge_count ->
        {:error, "Mismatched GS/GE functional group envelopes (#{gs_count} GS, #{ge_count} GE)"}

      true ->
        :ok
    end
  end

  defp validate_st_se_transaction_sets(segments) do
    st_segments = Enum.filter(segments, &String.starts_with?(&1, "ST"))
    se_segments = Enum.filter(segments, &String.starts_with?(&1, "SE"))

    st_count = length(st_segments)
    se_count = length(se_segments)

    cond do
      st_count == 0 ->
        {:error, "No ST transaction set headers found"}

      st_count != se_count ->
        {:error, "Mismatched ST/SE transaction set envelopes (#{st_count} ST, #{se_count} SE)"}

      true ->
        # Verify each ST segment is for an 837 transaction set
        # ST segment format: ST*837*control_number*version
        non_837 =
          st_segments
          |> Enum.reject(fn st ->
            elements = String.split(st, "*")
            length(elements) >= 2 and Enum.at(elements, 1) == "837"
          end)

        if non_837 == [] do
          {:ok, st_count}
        else
          types =
            non_837
            |> Enum.map(fn st ->
              elements = String.split(st, "*")
              if length(elements) >= 2, do: Enum.at(elements, 1), else: "unknown"
            end)
            |> Enum.join(", ")

          {:error,
           "File contains non-837 transaction sets (types: #{types}). Only 837 claim files are accepted."}
        end
    end
  end
end
