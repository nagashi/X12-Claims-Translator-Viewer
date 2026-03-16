defmodule ClaimViewer.X12.ServiceFacility do
  @moduledoc "Represents the service facility (NM1*77) in an X12 837."

  alias ClaimViewer.X12.Address

  @enforce_keys []
  defstruct name: "", taxId: "", address: %Address{}

  @type t :: %__MODULE__{
          name: String.t(),
          taxId: String.t(),
          address: Address.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: to_string(data["name"] || ""),
      taxId: to_string(data["taxId"] || ""),
      address: Address.from_map(data["address"])
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = sf) do
    %{
      "name" => sf.name,
      "taxId" => sf.taxId,
      "address" => Address.to_map(sf.address)
    }
  end
end
