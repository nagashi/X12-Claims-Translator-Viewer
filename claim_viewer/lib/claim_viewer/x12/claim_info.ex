defmodule ClaimViewer.X12.ClaimInfo do
  @moduledoc "Represents the claim section (CLM segment) in an X12 837."

  @enforce_keys []
  defstruct id: "",
            totalCharge: 0.0,
            placeOfService: "",
            serviceType: "",
            indicators: %{},
            onsetDate: "",
            clearinghouseClaimNumber: ""

  @type t :: %__MODULE__{
          id: String.t(),
          totalCharge: number(),
          placeOfService: String.t(),
          serviceType: String.t(),
          indicators: map(),
          onsetDate: String.t(),
          clearinghouseClaimNumber: String.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      id: to_string(data["id"] || ""),
      totalCharge: ensure_number(data["totalCharge"]),
      placeOfService: to_string(data["placeOfService"] || ""),
      serviceType: to_string(data["serviceType"] || ""),
      indicators: ensure_map(data["indicators"]),
      onsetDate: to_string(data["onsetDate"] || ""),
      clearinghouseClaimNumber: to_string(data["clearinghouseClaimNumber"] || "")
    }
  end

  defp ensure_number(val) when is_number(val), do: val

  defp ensure_number(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> 0.0
    end
  end

  defp ensure_number(_), do: 0.0

  defp ensure_map(val) when is_map(val), do: val
  defp ensure_map(_), do: %{}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{
      "id" => c.id,
      "totalCharge" => c.totalCharge,
      "placeOfService" => c.placeOfService,
      "serviceType" => c.serviceType,
      "indicators" => c.indicators,
      "onsetDate" => c.onsetDate,
      "clearinghouseClaimNumber" => c.clearinghouseClaimNumber
    }
  end
end
