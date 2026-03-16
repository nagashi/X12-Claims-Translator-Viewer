defmodule ClaimViewer.X12.Claim837 do
  @moduledoc """
  Top-level struct representing a complete X12 837 claim.
  Holds all section structs for a single transaction set.
  """

  alias ClaimViewer.X12.{
    Transaction,
    Submitter,
    Receiver,
    BillingProvider,
    PayToProvider,
    Subscriber,
    Payer,
    ClaimInfo,
    Diagnosis,
    RenderingProvider,
    ServiceFacility,
    ServiceLine
  }

  @enforce_keys []
  defstruct transaction: %Transaction{},
            submitter: %Submitter{},
            receiver: %Receiver{},
            billing_provider: %BillingProvider{},
            pay_to_provider: %PayToProvider{},
            subscriber: %Subscriber{},
            payer: %Payer{},
            claim: %ClaimInfo{},
            diagnosis: %Diagnosis{},
            rendering_provider: %RenderingProvider{},
            service_facility: %ServiceFacility{},
            service_lines: []

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          submitter: Submitter.t(),
          receiver: Receiver.t(),
          billing_provider: BillingProvider.t(),
          pay_to_provider: PayToProvider.t(),
          subscriber: Subscriber.t(),
          payer: Payer.t(),
          claim: ClaimInfo.t(),
          diagnosis: Diagnosis.t(),
          rendering_provider: RenderingProvider.t(),
          service_facility: ServiceFacility.t(),
          service_lines: [ServiceLine.t()]
        }
end
