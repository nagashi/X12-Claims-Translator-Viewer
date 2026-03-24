defmodule ClaimViewer.Export.PDF do
  @moduledoc """
  Renders a claim as a styled HTML document and generates a PDF binary.
  All interpolated values are HTML-escaped to prevent XSS.
  """

  @doc """
  Render a claim record to a PDF binary.
  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  @spec render(%ClaimViewer.Claims.Claim{}) :: {:ok, binary()} | {:error, term()}
  def render(%{raw_json: sections} = _claim) do
    start_time = System.monotonic_time()

    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: Arial, sans-serif; padding: 30px; color: #333; }
        h1 { color: #38bdf8; border-bottom: 3px solid #38bdf8; padding-bottom: 10px; }
        h2 { color: #38bdf8; font-size: 18px; margin-top: 30px; border-bottom: 1px solid #ccc; padding-bottom: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; font-size: 13px; }
        th { background: #f0f0f0; font-weight: bold; }
        .field { margin: 8px 0; }
        .field strong { color: #555; }
        .summary { background: #f9f9f9; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
      </style>
    </head>
    <body>
      <h1>CLAIM REPORT</h1>
      #{render_claim_summary(sections)}
      #{render_claim_sections(sections)}
    </body>
    </html>
    """

    result = ClaimViewer.PDF.generate(html_content)
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:claim_viewer, :export, :stop],
      %{duration: duration},
      %{format: :pdf}
    )

    result
  end

  # ===== Private =====

  defp render_claim_summary(sections) do
    subscriber = Enum.find(sections, fn s -> s["section"] == "subscriber" end) || %{}
    subscriber_data = subscriber["data"] || %{}

    payer = Enum.find(sections, fn s -> s["section"] == "payer" end) || %{}
    payer_data = payer["data"] || %{}

    claim = Enum.find(sections, fn s -> s["section"] == "claim" end) || %{}
    claim_data = claim["data"] || %{}

    """
    <div class="summary">
      <h2 style="margin-top:0;">CLAIM SUMMARY</h2>
      <div class="field"><strong>Member:</strong> #{esc(subscriber_data["firstName"])} #{esc(subscriber_data["lastName"])}</div>
      <div class="field"><strong>Payer:</strong> #{esc(payer_data["name"])}</div>
      <div class="field"><strong>Claim #:</strong> #{esc(claim_data["clearinghouseClaimNumber"])}</div>
      <div class="field"><strong>Total Charge:</strong> $#{esc(claim_data["totalCharge"])}</div>
    </div>
    """
  end

  defp render_claim_sections(sections) do
    sections
    |> Enum.map(fn section ->
      section_name = (section["section"] || "") |> String.replace("_", " ") |> String.upcase()
      data = section["data"] || %{}

      """
      <h2>#{esc(section_name)}</h2>
      #{render_section_data(data)}
      """
    end)
    |> Enum.join("\n")
  end

  defp render_section_data(data) when is_map(data) and data != %{} do
    data
    |> Enum.reject(fn {k, _} -> k in ["indicators"] end)
    |> Enum.map(fn {k, v} ->
      value =
        if is_map(v) do
          v |> Enum.map(fn {kk, vv} -> "#{esc(kk)}: #{esc(vv)}" end) |> Enum.join(", ")
        else
          esc(v)
        end

      ~s(<div class="field"><strong>#{esc(format_label(k))}:</strong> #{value}</div>)
    end)
    |> Enum.join("\n")
  end

  defp render_section_data(data) when is_list(data) and data != [] do
    first = List.first(data)
    keys = Map.keys(first)

    """
    <table>
      <thead>
        <tr>
          #{keys |> Enum.map(&"<th>#{esc(format_label(&1))}</th>") |> Enum.join("")}
        </tr>
      </thead>
      <tbody>
        #{data |> Enum.map(fn row -> "<tr>#{keys |> Enum.map(&"<td>#{esc(row[&1])}</td>") |> Enum.join("")}</tr>" end) |> Enum.join("\n")}
      </tbody>
    </table>
    """
  end

  defp render_section_data(_), do: ""

  defp format_label(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_label(key), do: to_string(key)

  defp esc(nil), do: ""

  defp esc(val) when is_binary(val),
    do: Plug.HTML.html_escape_to_iodata(val) |> IO.iodata_to_binary()

  defp esc(val), do: val |> to_string() |> esc()
end
