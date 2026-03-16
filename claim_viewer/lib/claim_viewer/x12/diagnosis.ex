defmodule ClaimViewer.X12.Diagnosis do
  @moduledoc "Represents the diagnosis section (HI segment) in an X12 837."

  @enforce_keys []
  defstruct primary: "", secondary: []

  @type t :: %__MODULE__{
          primary: String.t(),
          secondary: [String.t()]
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      primary: to_string(data["primary"] || ""),
      secondary: ensure_string_list(data["secondary"])
    }
  end

  defp ensure_string_list(nil), do: []
  defp ensure_string_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp ensure_string_list(_), do: []

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = d) do
    %{"primary" => d.primary, "secondary" => d.secondary}
  end
end
