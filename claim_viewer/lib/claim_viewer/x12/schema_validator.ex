defmodule ClaimViewer.X12.SchemaValidator do
  @moduledoc """
  Validates 837 claim JSON against a HIPAA-compliant JSON Schema
  using the Rust-backed ExJsonschema library.

  The schema JSON is read at compile-time. The Rust NIF reference is
  compiled once at first use and cached in `:persistent_term` for
  near-instant subsequent validations.
  """

  @schema_json File.read!(
                 Path.join(:code.priv_dir(:claim_viewer), "schemas/837_5010_schema.json")
               )

  @persistent_key {__MODULE__, :compiled_schema}

  @doc """
  Validates the given section list (the internal JSON representation of an 837 claim)
  against the compiled 837 5010 JSON Schema.

  Returns `{:ok, sections}` if valid, or `{:error, :validation_failed, errors}` if not.
  """
  @spec validate_837_json(list()) ::
          {:ok, list()} | {:error, :validation_failed, list()}
  def validate_837_json(sections) when is_list(sections) do
    compiled = get_or_compile_schema()
    json_string = Jason.encode!(sections)

    case ExJsonschema.validate(compiled, json_string) do
      :ok ->
        {:ok, sections}

      {:error, errors} ->
        {:error, :validation_failed, errors}
    end
  end

  def validate_837_json(_) do
    {:error, :validation_failed, ["Expected a list of section maps"]}
  end

  # Lazily compile the schema on first use, then cache in :persistent_term
  defp get_or_compile_schema do
    case :persistent_term.get(@persistent_key, :not_compiled) do
      :not_compiled ->
        {:ok, compiled} = ExJsonschema.compile(@schema_json)
        :persistent_term.put(@persistent_key, compiled)
        compiled

      compiled ->
        compiled
    end
  end
end
