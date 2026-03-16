defmodule ClaimViewer.X12.RenderingProvider do
  @moduledoc "Represents the rendering provider (NM1*82) in an X12 837."

  @enforce_keys []
  defstruct firstName: "", lastName: "", npi: ""

  @type t :: %__MODULE__{
          firstName: String.t(),
          lastName: String.t(),
          npi: String.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      firstName: to_string(data["firstName"] || ""),
      lastName: to_string(data["lastName"] || ""),
      npi: to_string(data["npi"] || "")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = rp) do
    %{"firstName" => rp.firstName, "lastName" => rp.lastName, "npi" => rp.npi}
  end
end
