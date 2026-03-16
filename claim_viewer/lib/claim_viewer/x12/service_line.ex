defmodule ClaimViewer.X12.ServiceLine do
  @moduledoc "Represents a single service line (LX/SV1/DTP) in an X12 837."

  @enforce_keys []
  defstruct lineNumber: 0,
            codeQualifier: "",
            procedureCode: "",
            charge: 0.0,
            unitQualifier: "",
            units: 0.0,
            diagnosisPointer: "",
            emergencyIndicator: "",
            serviceDate: "",
            placeOfService: ""

  @type t :: %__MODULE__{
          lineNumber: integer(),
          codeQualifier: String.t(),
          procedureCode: String.t(),
          charge: number(),
          unitQualifier: String.t(),
          units: number(),
          diagnosisPointer: String.t() | integer(),
          emergencyIndicator: String.t(),
          serviceDate: String.t(),
          placeOfService: String.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      lineNumber: ensure_integer(data["lineNumber"]),
      codeQualifier: to_string(data["codeQualifier"] || ""),
      procedureCode: to_string(data["procedureCode"] || ""),
      charge: ensure_number(data["charge"]),
      unitQualifier: to_string(data["unitQualifier"] || ""),
      units: ensure_number(data["units"]),
      diagnosisPointer: data["diagnosisPointer"] || "",
      emergencyIndicator: to_string(data["emergencyIndicator"] || ""),
      serviceDate: to_string(data["serviceDate"] || ""),
      placeOfService: to_string(data["placeOfService"] || "")
    }
  end

  defp ensure_integer(val) when is_integer(val), do: val

  defp ensure_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp ensure_integer(val) when is_float(val), do: round(val)
  defp ensure_integer(_), do: 0

  defp ensure_number(val) when is_number(val), do: val

  defp ensure_number(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> 0.0
    end
  end

  defp ensure_number(_), do: 0.0

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = sl) do
    %{
      "lineNumber" => sl.lineNumber,
      "codeQualifier" => sl.codeQualifier,
      "procedureCode" => sl.procedureCode,
      "charge" => sl.charge,
      "unitQualifier" => sl.unitQualifier,
      "units" => sl.units,
      "diagnosisPointer" => sl.diagnosisPointer,
      "emergencyIndicator" => sl.emergencyIndicator,
      "serviceDate" => sl.serviceDate,
      "placeOfService" => sl.placeOfService
    }
  end

  @spec list_from_data(list() | nil) :: [t()]
  def list_from_data(nil), do: []
  def list_from_data(data) when is_list(data), do: Enum.map(data, &from_map/1)
  def list_from_data(_), do: []

  @spec list_to_data([t()]) :: [map()]
  def list_to_data(lines) when is_list(lines), do: Enum.map(lines, &to_map/1)
end
