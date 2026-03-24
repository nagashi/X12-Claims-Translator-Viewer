defmodule ClaimViewer.Claims.Ingestion do
  @moduledoc """
  Orchestrates the X12 file ingestion pipeline:

    validate → translate → map to structs → schema validate → save

  No controller dependency. Callable from IEx, tests, or background jobs.
  """

  require Logger

  alias ClaimViewer.Claims
  alias ClaimViewer.X12.{Mapper, SchemaValidator}

  @type result :: %{
          success_count: non_neg_integer(),
          total: non_neg_integer(),
          failures: [String.t()]
        }

  @doc """
  Ingest an X12 file end-to-end.

  Returns `{:ok, result}` with success/failure counts,
  or `{:error, reason}` if the file itself is invalid.
  """
  @spec ingest_file(String.t(), String.t()) :: {:ok, result()} | {:error, String.t()}
  def ingest_file(path, filename) do
    start_time = System.monotonic_time()

    result =
      with {:ok, tx_set_count} <- ClaimViewer.X12Validator.validate_file_content(path),
           _ = Logger.info("Valid X12 837 file: #{filename} (#{tx_set_count} transaction set(s))"),
           {:ok, json_data} <- ClaimViewer.X12Translator.translate_x12_to_json(path) do
        transaction_sets = normalize_transaction_sets(json_data)

        results =
          transaction_sets
          |> Enum.with_index(1)
          |> Enum.map(fn {sections, idx} ->
            process_transaction_set(sections, idx)
          end)

        {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))
        success_count = length(successes)
        total = length(results)

        save_errors =
          Enum.flat_map(successes, fn {:ok, validated_sections} ->
            case save_claim(validated_sections) do
              {:ok, _claim} -> []
              {:error, reason} -> [reason]
            end
          end)

        actual_success = success_count - length(save_errors)
        failure_msgs = extract_failure_messages(failures) ++ save_errors

        Logger.info("X12 ingestion complete",
          filename: filename,
          transaction_sets: total,
          succeeded: actual_success
        )

        {:ok, %{success_count: actual_success, total: total, failures: failure_msgs}}
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:claim_viewer, :ingestion, :stop],
      %{duration: duration},
      %{filename: filename, result: elem(result, 0)}
    )

    result
  end

  # ===== Private =====

  defp normalize_transaction_sets(json_data) do
    case json_data do
      [first | _] when is_list(first) -> json_data
      sections when is_list(sections) -> [sections]
      _ -> []
    end
  end

  defp process_transaction_set(sections, index) do
    with {:ok, claim_struct} <- Mapper.from_sections(sections),
         validated_sections = Mapper.to_validated_sections(claim_struct),
         {:ok, validated_sections} <- SchemaValidator.validate_837_json(validated_sections) do
      {:ok, validated_sections}
    else
      {:error, :validation_failed, errors} ->
        {:error, "Transaction set ##{index} failed schema validation: #{inspect(errors)}"}

      {:error, reason} ->
        {:error, "Transaction set ##{index}: #{reason}"}
    end
  end

  defp save_claim(json_data) do
    search_fields = Claims.extract_search_fields(json_data)

    date_of_service =
      case Claims.extract_date_of_service(json_data) do
        {:ok, date} -> date
        {:error, _} -> nil
      end

    attrs =
      %{raw_json: json_data, date_of_service: date_of_service}
      |> Map.merge(search_fields)

    case Claims.create_claim(attrs) do
      {:ok, claim} ->
        {:ok, claim}

      {:error, changeset} ->
        Logger.warning("Failed to save claim: #{inspect(changeset.errors)}")
        {:error, "Database save failed: #{inspect(changeset.errors)}"}
    end
  end

  defp extract_failure_messages(failures) do
    Enum.map(failures, fn {:error, msg} -> msg end)
  end
end
