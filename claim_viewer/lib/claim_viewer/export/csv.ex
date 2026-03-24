defmodule ClaimViewer.Export.CSV do
  @moduledoc """
  Renders a claim as a plain-text CSV/summary export.
  """

  @doc """
  Render a claim record to a CSV string.
  Returns `{:ok, string}`.
  """
  @spec render(%ClaimViewer.Claims.Claim{}) :: {:ok, String.t()}
  def render(%{raw_json: sections} = _claim) do
    subscriber = Enum.find(sections, fn s -> s["section"] == "subscriber" end) || %{}
    subscriber_data = subscriber["data"] || %{}

    payer = Enum.find(sections, fn s -> s["section"] == "payer" end) || %{}
    payer_data = payer["data"] || %{}

    claim_section = Enum.find(sections, fn s -> s["section"] == "claim" end) || %{}
    claim_data = claim_section["data"] || %{}

    service_lines_section =
      Enum.find(sections, fn s ->
        String.downcase(s["section"] || "") |> String.contains?("service")
      end) || %{}

    service_data = service_lines_section["data"] || []

    service_dates =
      if is_list(service_data) and service_data != [] do
        service_data |> Enum.map(fn line -> line["serviceDate"] end) |> Enum.reject(&is_nil/1)
      else
        []
      end

    first_date = if service_dates != [], do: Enum.min(service_dates), else: nil
    last_date = if service_dates != [], do: Enum.max(service_dates), else: nil

    indicators = claim_data["indicators"] || %{}
    all_approved = Enum.all?(Map.values(indicators), fn v -> v in ["Y", "A", "I"] end)
    status = if all_approved and indicators != %{}, do: "Approved", else: "Pending Review"

    csv_content = """
    CLAIM SUMMARY
    =============
    Member: #{subscriber_data["firstName"]} #{subscriber_data["lastName"]} (DOB: #{format_date_plain(subscriber_data["dob"])})
    Payer: #{payer_data["name"]}
    Claim #: #{claim_data["clearinghouseClaimNumber"] || claim_data["id"]}
    Service Dates: #{format_service_date_range(first_date, last_date)}
    Total Charge: $#{format_number(claim_data["totalCharge"])}
    Status: #{status}


    #{build_all_sections_csv(sections)}

    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    """

    :telemetry.execute(
      [:claim_viewer, :export, :stop],
      %{duration: 0},
      %{format: :csv}
    )

    {:ok, csv_content}
  end

  # ===== Private =====

  defp format_service_date_range(nil, _), do: ""
  defp format_service_date_range(_, nil), do: ""

  defp format_service_date_range(first, last) do
    if first == last do
      format_date_plain(first)
    else
      "#{format_date_plain(first)} - #{format_date_plain(last)}"
    end
  end

  defp build_all_sections_csv(sections) do
    sections
    |> Enum.map(fn section ->
      section_name = (section["section"] || "") |> String.replace("_", " ") |> String.upcase()
      data = section["data"] || %{}

      """
      #{section_name}
      #{String.duplicate("-", String.length(section_name))}
      #{render_section_csv(data)}
      """
    end)
    |> Enum.join("\n")
  end

  defp render_section_csv(data) when is_map(data) and data != %{} do
    data
    |> Map.to_list()
    |> Enum.reject(fn {k, _} -> k in ["indicators"] end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} ->
      label = format_label_nice(k)
      value = format_value_plain(v)
      "#{label}: #{value}"
    end)
    |> Enum.join("\n")
  end

  defp render_section_csv(data) when is_list(data) and data != [] do
    data
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {row, idx} ->
      ["Line #{idx}:"] ++
        (row
         |> Enum.reject(fn {k, _} -> k == "lineNumber" end)
         |> Enum.map(fn {k, v} ->
           label = format_label_nice(k)

           value =
             case v do
               nil -> ""
               vv when is_binary(vv) and k == "serviceDate" -> format_date_plain(vv)
               vv when is_number(vv) -> to_string(vv)
               vv -> to_string(vv)
             end

           "  #{label}: #{value}"
         end)) ++ [""]
    end)
    |> Enum.join("\n")
  end

  defp render_section_csv(_), do: ""

  defp format_label_nice(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_label_nice(key), do: to_string(key)

  defp format_value_plain(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> "  #{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp format_value_plain(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> format_date_plain(date)
      _ -> value
    end
  end

  defp format_value_plain(value), do: to_string(value)

  defp format_date_plain(nil), do: ""

  defp format_date_plain(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> format_date_plain(d)
      _ -> date
    end
  end

  defp format_date_plain(%Date{} = date) do
    Calendar.strftime(date, "%B %d %Y")
  end

  defp format_number(nil), do: "0.00"

  defp format_number(num) when is_number(num) do
    :erlang.float_to_binary(num * 1.0, decimals: 2)
  end

  defp format_number(num), do: to_string(num)
end
