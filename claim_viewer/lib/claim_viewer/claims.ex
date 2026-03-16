defmodule ClaimViewer.Claims do
  @moduledoc """
  Extracts searchable fields from raw claim JSON
  """

  def extract_search_fields(sections) when is_list(sections) do
    %{
      patient_first_name: get_in_section(sections, "subscriber", ["firstName"]),
      patient_last_name: get_in_section(sections, "subscriber", ["lastName"]),
      patient_dob: get_in_section(sections, "subscriber", ["dob"]),
      payer_name: get_in_section(sections, "payer", ["name"]),
      billing_provider_name: get_in_section(sections, "billing_Provider", ["name"]),
      pay_to_provider_name: get_in_section(sections, "Pay_To_provider", ["name"]),
      rendering_provider_name: get_in_section(sections, "renderingProvider", ["firstName"]),
      rendering_provider_npi: get_in_section(sections, "renderingProvider", ["npi"]),
      clearinghouse_claim_number: get_in_section(sections, "claim", ["clearinghouseClaimNumber"])
    }
  end

  def extract_search_fields(_), do: %{}

  def extract_date_of_service(sections) do
    sections
    |> Enum.find(fn s -> get_section_name(s) == "service_Lines" end)
    |> case do
      nil ->
        nil

      s ->
        data = get_section_data(s)
        [first | _] = data
        Date.from_iso8601!(first["serviceDate"])
    end
  end

  defp get_in_section(sections, section_name, path) do
    sections
    |> Enum.find(fn s -> get_section_name(s) == section_name end)
    |> case do
      nil ->
        nil

      s ->
        data = get_section_data(s)
        get_in(data, path)
    end
  end

  # Υποστηρίζει ΚΑΙ map ΚΑΙ keyword list
  defp get_section_name(%{"section" => name}), do: name
  defp get_section_name(s) when is_list(s), do: Keyword.get(s, :section)

  defp get_section_data(%{"data" => data}), do: data
  defp get_section_data(s) when is_list(s), do: Keyword.get(s, :data)
end
