defmodule ClaimViewer.X12.Subscriber do
  @moduledoc "Represents the subscriber/member (NM1*IL) in an X12 837."

  alias ClaimViewer.X12.Address

  @enforce_keys []
  defstruct firstName: "",
            lastName: "",
            id: "",
            dob: "",
            sex: "",
            relationship: "",
            groupNumber: "",
            planType: "",
            address: %Address{}

  @type t :: %__MODULE__{
          firstName: String.t(),
          lastName: String.t(),
          id: String.t(),
          dob: String.t(),
          sex: String.t(),
          relationship: String.t(),
          groupNumber: String.t(),
          planType: String.t(),
          address: Address.t()
        }

  @spec from_map(map() | nil) :: t()
  def from_map(nil), do: %__MODULE__{}

  def from_map(data) when is_map(data) do
    %__MODULE__{
      firstName: to_string(data["firstName"] || ""),
      lastName: to_string(data["lastName"] || ""),
      id: to_string(data["id"] || ""),
      dob: to_string(data["dob"] || ""),
      sex: to_string(data["sex"] || ""),
      relationship: to_string(data["relationship"] || ""),
      groupNumber: to_string(data["groupNumber"] || ""),
      planType: to_string(data["planType"] || ""),
      address: Address.from_map(data["address"])
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = s) do
    %{
      "firstName" => s.firstName,
      "lastName" => s.lastName,
      "id" => s.id,
      "dob" => s.dob,
      "sex" => s.sex,
      "relationship" => s.relationship,
      "groupNumber" => s.groupNumber,
      "planType" => s.planType,
      "address" => Address.to_map(s.address)
    }
  end
end
