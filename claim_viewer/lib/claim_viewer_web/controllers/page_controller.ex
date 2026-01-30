defmodule ClaimViewerWeb.PageController do
  use ClaimViewerWeb, :controller

  alias ClaimViewer.Repo
  alias ClaimViewer.Claims
  alias ClaimViewer.Claims.Claim
  import Ecto.Query

  # ===== Helpers =====

  defp valid_search?(value) do
    String.length(value) >= 2
  end

  # ===== Actions =====

    def dashboard(conn, _params) do
  # Get statistics
  total_claims = Repo.aggregate(Claim, :count, :id)

  # Calculate revenue and status counts
  claims = Repo.all(Claim)

  {approved_count, approved_revenue} =
    claims
    |> Enum.filter(fn claim ->
      indicators = get_in(claim.raw_json, [Access.filter(fn s -> s["section"] == "claim" end), "data", "indicators"]) |> List.first() || %{}
      Enum.all?(Map.values(indicators), fn v -> v in ["Y", "A", "I"] end) and indicators != %{}
    end)
    |> Enum.reduce({0, 0}, fn claim, {count, revenue} ->
      charge = get_in(claim.raw_json, [Access.filter(fn s -> s["section"] == "claim" end), "data", "totalCharge"]) |> List.first() || 0
      {count + 1, revenue + charge}
    end)

  pending_count = total_claims - approved_count

# Claims over 30 days
thirty_days_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-30 * 24 * 60 * 60, :second)
old_claims = Repo.all(from c in Claim, where: c.inserted_at < ^thirty_days_ago) |> length()

# This month
# This month
now = NaiveDateTime.utc_now()
first_day = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
this_month_count = Repo.aggregate(from(c in Claim, where: c.inserted_at >= ^first_day), :count, :id)

  render(conn, :dashboard,
    total_claims: total_claims,
    approved_count: approved_count,
    approved_revenue: approved_revenue,
    pending_count: pending_count,
    old_claims: old_claims,
    this_month_count: this_month_count
  )
end

  def home(conn, params) do
    first = params |> Map.get("patient_first", "") |> String.trim()
    last = params |> Map.get("patient_last", "") |> String.trim()
    payer = params |> Map.get("payer", "") |> String.trim()
    billing_provider = params |> Map.get("billing_provider", "") |> String.trim()
    rendering_provider = params |> Map.get("rendering_provider", "") |> String.trim()
    claim_number = params |> Map.get("claim_number", "") |> String.trim()
    service_from = params |> Map.get("service_from", "") |> String.trim()
    service_to = params |> Map.get("service_to", "") |> String.trim()

    page = case Integer.parse(params |> Map.get("page", "1")) do
      {num, _} -> num
      :error -> 1
    end

    has_search? =
      valid_search?(first) or
      valid_search?(last) or
      valid_search?(payer) or
      valid_search?(billing_provider) or
      valid_search?(rendering_provider) or
      valid_search?(claim_number) or
      service_from != "" or
      service_to != ""

    per_page = 10
    offset = (page - 1) * per_page

    {claims, total_count} =
      if has_search? do
        query = from(c in Claim)
          |> maybe_full_name(first, last)
          |> maybe_like(:payer_name, payer)
          |> maybe_like(:billing_provider_name, billing_provider)
          |> maybe_exact(:rendering_provider_npi, rendering_provider)
          |> maybe_like(:clearinghouse_claim_number, claim_number)
          |> maybe_date_range(service_from, service_to)
          |> order_by([c], desc: c.inserted_at)

        total = Repo.aggregate(query, :count, :id)
        claims = query |> limit(^per_page) |> offset(^offset) |> Repo.all()

        {claims, total}
      else
        {[], 0}
      end

    total_pages = if total_count > 0, do: ceil(total_count / per_page), else: 0

    render(conn, :home,
      claims: claims,
      show_results: has_search?,
      patient_first: first,
      patient_last: last,
      payer: payer,
      billing_provider: billing_provider,
      rendering_provider: rendering_provider,
      claim_number: claim_number,
      service_from: service_from,
      service_to: service_to,
      page: page,
      total_pages: total_pages,
      total_count: total_count,
      json: nil,
      claim_id: nil
    )
  end

  def show(conn, %{"id" => id}) do
    claim = Repo.get!(Claim, id)

    render(conn, :home,
      claims: [],
      show_results: false,
      patient_first: "",
      patient_last: "",
      payer: "",
      billing_provider: "",
      rendering_provider: "",
      claim_number: "",
      service_from: "",
      service_to: "",
      page: 1,
      total_pages: 0,
      total_count: 0,
      json: claim.raw_json,
      claim_id: id
    )
  end

  def upload(conn, %{"file" => %Plug.Upload{path: path}}) do
    json =
      path
      |> File.read!()
      |> Jason.decode!()

    json =
      case json do
        [first | _] when is_list(first) -> first
        _ -> json
      end

    search_fields = Claims.extract_search_fields(json)

    date_of_service =
      try do
        Claims.extract_date_of_service(json)
      rescue
        _ -> nil
      end

    attrs =
      %{raw_json: json, date_of_service: date_of_service}
      |> Map.merge(search_fields)

    %Claim{}
    |> Claim.changeset(attrs)
    |> Repo.insert!()

    redirect(conn, to: "/")
  end

  def upload(conn, _params) do
    conn
    |> put_flash(:error, "Please select a JSON file")
    |> redirect(to: "/")
  end

  def export_pdf(conn, %{"id" => id}) do
    claim = Repo.get!(Claim, id)

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
      #{render_claim_summary(claim.raw_json)}
      #{render_claim_sections(claim.raw_json)}
    </body>
    </html>
    """

    case PdfGenerator.generate(html_content, page_size: "A4") do
      {:ok, pdf_path} ->
        pdf_binary = File.read!(pdf_path)
        File.rm(pdf_path)

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(attachment; filename="claim_#{id}.pdf"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to generate PDF: #{inspect(reason)}")
        |> redirect(to: "/claims/#{id}")
    end
  end

  # ===== Query helpers =====

  defp maybe_like(query, _field, ""), do: query
  defp maybe_like(query, field, value) do
    where(query, [c], ilike(field(c, ^field), ^"%#{value}%"))
  end

  defp maybe_exact(query, _field, ""), do: query
  defp maybe_exact(query, field, value) do
    where(query, [c], field(c, ^field) == ^value)
  end

  defp maybe_full_name(query, first, last) do
    cond do
      first != "" and last != "" ->
        where(query, [c],
          ilike(c.patient_first_name, ^"%#{first}%") and
          ilike(c.patient_last_name, ^"%#{last}%")
        )

      first != "" ->
        where(query, [c],
          ilike(c.patient_first_name, ^"%#{first}%")
        )

      last != "" ->
        where(query, [c],
          ilike(c.patient_last_name, ^"%#{last}%")
        )

      true ->
        query
    end
  end

  defp maybe_date_range(query, "", ""), do: query

  defp maybe_date_range(query, from, "") do
    case Date.from_iso8601(from) do
      {:ok, from_date} ->
        where(query, [c], c.date_of_service >= ^from_date)

      _ ->
        query
    end
  end

  defp maybe_date_range(query, "", to) do
    case Date.from_iso8601(to) do
      {:ok, to_date} ->
        where(query, [c], c.date_of_service <= ^to_date)

      _ ->
        query
    end
  end

  defp maybe_date_range(query, from, to) do
    case {Date.from_iso8601(from), Date.from_iso8601(to)} do
      {{:ok, from_date}, {:ok, to_date}} ->
        where(query, [c],
          not is_nil(c.date_of_service) and
          c.date_of_service >= ^from_date and
          c.date_of_service <= ^to_date
        )

      _ ->
        query
    end
  end

  # ===== PDF Helpers =====

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
      <div class="field"><strong>Patient:</strong> #{subscriber_data["firstName"]} #{subscriber_data["lastName"]}</div>
      <div class="field"><strong>Payer:</strong> #{payer_data["name"]}</div>
      <div class="field"><strong>Claim #:</strong> #{claim_data["clearinghouseClaimNumber"]}</div>
      <div class="field"><strong>Total Charge:</strong> $#{claim_data["totalCharge"]}</div>
    </div>
    """
  end

  defp render_claim_sections(sections) do
    sections
    |> Enum.map(fn section ->
      section_name = (section["section"] || "") |> String.replace("_", " ") |> String.upcase()
      data = section["data"] || %{}

      """
      <h2>#{section_name}</h2>
      #{render_section_data(data)}
      """
    end)
    |> Enum.join("\n")
  end

  defp render_section_data(data) when is_map(data) and data != %{} do
    data
    |> Enum.reject(fn {k, _} -> k in ["indicators"] end)
    |> Enum.map(fn {k, v} ->
      value = if is_map(v) do
        v |> Enum.map(fn {kk, vv} -> "#{kk}: #{vv}" end) |> Enum.join(", ")
      else
        v
      end
      ~s(<div class="field"><strong>#{format_label(k)}:</strong> #{value}</div>)
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
          #{keys |> Enum.map(&"<th>#{format_label(&1)}</th>") |> Enum.join("")}
        </tr>
      </thead>
      <tbody>
        #{data |> Enum.map(fn row ->
          "<tr>#{keys |> Enum.map(&"<td>#{row[&1]}</td>") |> Enum.join("")}</tr>"
        end) |> Enum.join("\n")}
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
end
