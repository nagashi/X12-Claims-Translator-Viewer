defmodule ClaimViewer.X12.Transaction do
  @moduledoc "Represents the transaction set header (ST/BHT) in an X12 837."

  @enforce_keys []
  defstruct type: "",
            controlNumber: "",
            version: "",
            purpose: "",
            referenceId: "",
            date: "",
            time: ""

  @type t :: %__MODULE__{
          type: String.t(),
          controlNumber: String.t(),
          version: String.t(),
          purpose: String.t(),
          referenceId: String.t(),
          date: String.t(),
          time: String.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      type: to_string(data["type"] || ""),
      controlNumber: to_string(data["controlNumber"] || ""),
      version: to_string(data["version"] || ""),
      purpose: to_string(data["purpose"] || ""),
      referenceId: to_string(data["referenceId"] || ""),
      date: to_string(data["date"] || ""),
      time: to_string(data["time"] || "")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = t) do
    %{
      "type" => t.type,
      "controlNumber" => t.controlNumber,
      "version" => t.version,
      "purpose" => t.purpose,
      "referenceId" => t.referenceId,
      "date" => t.date,
      "time" => t.time
    }
  end
end
