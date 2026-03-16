defmodule ClaimViewer.X12.Submitter do
  @moduledoc "Represents the submitter (NM1*41) in an X12 837."

  @enforce_keys []
  defstruct name: "", id: "", contact: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          id: String.t(),
          contact: map()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: to_string(data["name"] || ""),
      id: to_string(data["id"] || ""),
      contact: ensure_contact_map(data["contact"])
    }
  end

  defp ensure_contact_map(nil), do: %{}

  defp ensure_contact_map(contact) when is_map(contact) do
    %{
      "name" => to_string(contact["name"] || ""),
      "phone" => to_string(contact["phone"] || ""),
      "extension" => to_string(contact["extension"] || "")
    }
  end

  defp ensure_contact_map(_), do: %{}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = s) do
    %{"name" => s.name, "id" => s.id, "contact" => s.contact}
  end
end
