defmodule ClaimViewerWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use ClaimViewerWeb, :html

  embed_templates "page_html/*"

def human_label(key) do
  %{
    "controlNumber" => "Control Number",
    "referenceId" => "Reference ID",
    "payerId" => "Payer ID",
    "totalCharge" => "Total Charge",
    "serviceDate" => "Service Date",
    "firstName" => "First Name",
    "lastName" => "Last Name",
    "groupNumber" => "Group Number",
    "planType" => "Plan Type",
    "taxId" => "Tax ID",
    "clearinghouseClaimNumber" => "Claim Number",
    "dob" => "Date of Birth",
    "npi" => "NPI",
    "onsetDate" => "Onset Date",
    "placeOfService" => "Place of Service",
    "serviceType" => "Service Type",
    "unitQualifier" => "Unit Qualifier",
    "lineNumber" => "Line #",
    "procedureCode" => "Procedure Code"
  }[key] ||
    key
    |> Macro.underscore()
    |> String.replace("_"," ")
    |> String.capitalize()
end


end
