defmodule ClaimViewer.X12.Address do
  @moduledoc "Represents a physical address in X12 837 data."

  @enforce_keys []
  defstruct street: "", city: "", state: "", zip: ""

  @type t :: %__MODULE__{
          street: String.t(),
          city: String.t(),
          state: String.t(),
          zip: String.t()
        }

  @doc "Builds an Address struct from a map. Returns a default struct for nil/empty input."
  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      street: to_string(data["street"] || ""),
      city: to_string(data["city"] || ""),
      state: to_string(data["state"] || ""),
      zip: to_string(data["zip"] || "")
    }
  end

  def from_map(_), do: %__MODULE__{}

  @doc "Converts the struct to a plain map with string keys."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = addr) do
    %{
      "street" => addr.street,
      "city" => addr.city,
      "state" => addr.state,
      "zip" => addr.zip
    }
  end
end
