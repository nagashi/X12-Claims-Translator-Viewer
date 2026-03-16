defmodule ClaimViewer.X12.PayToProvider do
  @moduledoc "Represents the pay-to provider (NM1*87) in an X12 837."

  alias ClaimViewer.X12.Address

  @enforce_keys []
  defstruct name: "", taxId: "", npi: "", address: %Address{}

  @type t :: %__MODULE__{
          name: String.t(),
          taxId: String.t(),
          npi: String.t(),
          address: Address.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: to_string(data["name"] || ""),
      taxId: to_string(data["taxId"] || ""),
      npi: to_string(data["npi"] || ""),
      address: Address.from_map(data["address"])
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p) do
    %{
      "name" => p.name,
      "taxId" => p.taxId,
      "npi" => p.npi,
      "address" => Address.to_map(p.address)
    }
  end
end
