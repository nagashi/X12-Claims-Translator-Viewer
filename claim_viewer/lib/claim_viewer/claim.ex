defmodule ClaimViewer.Claims.Claim do
  use Ecto.Schema
  import Ecto.Changeset

schema "claims" do
  field :raw_json, {:array, :map}


  # SEARCHABLE FIELDS
  field :patient_first_name, :string
  field :patient_last_name, :string
  field :patient_dob, :date

  field :payer_name, :string

  field :billing_provider_name, :string
  field :billing_provider_npi, :string

  field :pay_to_provider_name, :string
  field :pay_to_provider_npi, :string

  field :rendering_provider_name, :string
  field :rendering_provider_npi, :string

  field :clearinghouse_claim_number, :string

  timestamps()
end


def changeset(claim, attrs) do
  claim
  |> cast(attrs, [
    :raw_json,

    :patient_first_name,
    :patient_last_name,
    :patient_dob,

    :payer_name,

    :billing_provider_name,
    :billing_provider_npi,

    :pay_to_provider_name,
    :pay_to_provider_npi,

    :rendering_provider_name,
    :rendering_provider_npi,

    :clearinghouse_claim_number
  ])
end
def extract_search_fields(sections) do
  get = fn name ->
    Enum.find(sections, &(&1["section"] == name))
  end

  subscriber = get.("subscriber")["data"] || %{}
  payer = get.("payer")["data"] || %{}
  billing = get.("billing_Provider")["data"] || %{}
  pay_to = get.("Pay_To_provider")["data"] || %{}
  rendering = get.("renderingProvider")["data"] || %{}
  claim = get.("claim")["data"] || %{}

  %{
    patient_first_name: subscriber["firstName"],
    patient_last_name: subscriber["lastName"],
    patient_dob: subscriber["dob"],
    payer_name: payer["name"],
    billing_provider_name: billing["name"],
    pay_to_provider_name: pay_to["name"],
    rendering_provider_npi: rendering["npi"],
    clearinghouse_claim_number: claim["clearinghouseClaimNumber"]
  }
end


end
