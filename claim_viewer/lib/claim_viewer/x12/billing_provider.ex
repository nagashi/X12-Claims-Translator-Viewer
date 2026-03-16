defmodule ClaimViewer.X12.BillingProvider do
  @moduledoc "Represents the billing provider (NM1*85) in an X12 837."

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
  def to_map(%__MODULE__{} = bp) do
    %{
      "name" => bp.name,
      "taxId" => bp.taxId,
      "npi" => bp.npi,
      "address" => Address.to_map(bp.address)
    }
  end
end
