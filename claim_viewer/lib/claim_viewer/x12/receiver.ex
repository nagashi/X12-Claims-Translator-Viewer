defmodule ClaimViewer.X12.Receiver do
  @moduledoc "Represents the receiver (NM1*40) in an X12 837."

  @enforce_keys []
  defstruct name: "", id: ""

  @type t :: %__MODULE__{name: String.t(), id: String.t()}

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: to_string(data["name"] || ""),
      id: to_string(data["id"] || "")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = r) do
    %{"name" => r.name, "id" => r.id}
  end
end
