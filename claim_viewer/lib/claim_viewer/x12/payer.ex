defmodule ClaimViewer.X12.Payer do
  @moduledoc "Represents the payer (NM1*PR) in an X12 837."

  @enforce_keys []
  defstruct name: "", payerId: ""

  @type t :: %__MODULE__{name: String.t(), payerId: String.t()}

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: to_string(data["name"] || ""),
      payerId: to_string(data["payerId"] || "")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p) do
    %{"name" => p.name, "payerId" => p.payerId}
  end
end
