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
def format_date(date_string) when is_binary(date_string) do
  case Date.from_iso8601(date_string) do
    {:ok, date} ->
      month = case date.month do
        1 -> "January"
        2 -> "February"
        3 -> "March"
        4 -> "April"
        5 -> "May"
        6 -> "June"
        7 -> "July"
        8 -> "August"
        9 -> "September"
        10 -> "October"
        11 -> "November"
        12 -> "December"
      end
      "#{month} #{date.day}, #{date.year}"
    _ ->
      date_string
  end
end

def format_date(nil), do: ""
def format_date(other), do: to_string(other)

end
