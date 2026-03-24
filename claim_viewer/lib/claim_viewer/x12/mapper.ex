defmodule ClaimViewer.X12.Mapper do
  @moduledoc """
  Maps between raw JSON section maps (from the Python parser) and
  type-safe X12 structs. Ensures data type consistency through
  guard clauses in each struct's `from_map/1`.
  """

  alias ClaimViewer.X12.{
    Claim837,
    Transaction,
    Submitter,
    Receiver,
    BillingProvider,
    PayToProvider,
    Subscriber,
    Payer,
    ClaimInfo,
    Diagnosis,
    RenderingProvider,
    ServiceFacility,
    ServiceLine
  }

  @section_to_struct %{
    "transaction" => Transaction,
    "submitter" => Submitter,
    "receiver" => Receiver,
    "billing_Provider" => BillingProvider,
    "Pay_To_provider" => PayToProvider,
    "subscriber" => Subscriber,
    "payer" => Payer,
    "claim" => ClaimInfo,
    "diagnosis" => Diagnosis,
    "renderingProvider" => RenderingProvider,
    "serviceFacility" => ServiceFacility,
    "service_Lines" => ServiceLine
  }

  @section_to_field %{
    "transaction" => :transaction,
    "submitter" => :submitter,
    "receiver" => :receiver,
    "billing_Provider" => :billing_provider,
    "Pay_To_provider" => :pay_to_provider,
    "subscriber" => :subscriber,
    "payer" => :payer,
    "claim" => :claim,
    "diagnosis" => :diagnosis,
    "renderingProvider" => :rendering_provider,
    "serviceFacility" => :service_facility,
    "service_Lines" => :service_lines
  }

  @doc """
  Converts a raw list of section maps (from the Python parser) into
  a type-safe `%Claim837{}` struct.

  Returns `{:ok, %Claim837{}}` or `{:error, reason}`.
  """
  @spec from_sections(list()) :: {:ok, Claim837.t()} | {:error, String.t()}
  def from_sections(sections) when is_list(sections) do
    case validate_section_shapes(sections) do
      :ok ->
        claim837 =
          Enum.reduce(sections, %Claim837{}, fn section, acc ->
            section_name = section["section"]
            data = section["data"]

            case Map.get(@section_to_field, section_name) do
              nil ->
                # Unknown section, skip
                acc

              :service_lines ->
                lines = ServiceLine.list_from_data(data)
                %{acc | service_lines: lines}

              field ->
                struct_mod = Map.fetch!(@section_to_struct, section_name)
                struct_val = struct_mod.from_map(data)
                %{acc | field => struct_val}
            end
          end)

        {:ok, claim837}

      {:error, _} = error ->
        error
    end
  end

  def from_sections(_), do: {:error, "Expected a list of section maps"}

  defp validate_section_shapes(sections) do
    Enum.reduce_while(sections, :ok, fn section, :ok ->
      cond do
        not is_map(section) ->
          {:halt, {:error, "Expected a map for each section, got: #{inspect(section)}"}}

        not is_binary(section["section"]) ->
          {:halt,
           {:error,
            "Section missing or invalid \"section\" key: #{inspect(Map.get(section, "section"))}"}}

        is_nil(section["data"]) ->
          {:halt, {:error, "Section \"#{section["section"]}\" is missing \"data\" key"}}

        not (is_map(section["data"]) or is_list(section["data"])) ->
          {:halt,
           {:error,
            "Section \"#{section["section"]}\" has invalid \"data\" type: #{inspect(section["data"])}"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  @doc """
  Converts a `%Claim837{}` struct back into the list-of-section-maps
  format used for storage and display.

  This round-trip through structs ensures all data types are validated
  and consistent.
  """
  @spec to_validated_sections(Claim837.t()) :: [map()]
  def to_validated_sections(%Claim837{} = claim) do
    [
      %{"section" => "transaction", "data" => Transaction.to_map(claim.transaction)},
      %{"section" => "submitter", "data" => Submitter.to_map(claim.submitter)},
      %{"section" => "receiver", "data" => Receiver.to_map(claim.receiver)},
      %{
        "section" => "billing_Provider",
        "data" => BillingProvider.to_map(claim.billing_provider)
      },
      %{"section" => "Pay_To_provider", "data" => PayToProvider.to_map(claim.pay_to_provider)},
      %{"section" => "subscriber", "data" => Subscriber.to_map(claim.subscriber)},
      %{"section" => "payer", "data" => Payer.to_map(claim.payer)},
      %{"section" => "claim", "data" => ClaimInfo.to_map(claim.claim)},
      %{"section" => "diagnosis", "data" => Diagnosis.to_map(claim.diagnosis)},
      %{
        "section" => "renderingProvider",
        "data" => RenderingProvider.to_map(claim.rendering_provider)
      },
      %{
        "section" => "serviceFacility",
        "data" => ServiceFacility.to_map(claim.service_facility)
      },
      %{"section" => "service_Lines", "data" => ServiceLine.list_to_data(claim.service_lines)}
    ]
  end
end
