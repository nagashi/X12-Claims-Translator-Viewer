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

  # ===== UPLOAD - UPDATED FOR X12 SUPPORT =====

def upload(conn, %{"file" => %Plug.Upload{path: path, filename: filename}}) do
  IO.puts("📤 UPLOAD RECEIVED: #{filename}")

  # Detect file type
  file_extension = Path.extname(filename) |> String.downcase()
  IO.puts("📂 File extension: #{file_extension}")

  case file_extension do
    # X12 files
    ext when ext in [".txt", ".edi", ".837"] ->
      IO.puts("🔄 Detected X12 file, calling handle_x12_upload...")
      handle_x12_upload(conn, path, filename)

    # JSON files (existing flow)
    ".json" ->
      IO.puts("📄 Detected JSON file")
      handle_json_upload(conn, path)

    _ ->
      IO.puts("❌ Unsupported file type: #{file_extension}")
      conn
      |> put_flash(:error, "Unsupported file type. Please upload .json, .txt, .edi, or .837 files.")
      |> redirect(to: "/")
  end
end

  def upload(conn, _params) do
    conn
    |> put_flash(:error, "Please select a file")
    |> redirect(to: "/")
  end

  # Handle X12 files
defp handle_x12_upload(conn, x12_path, filename) do
  IO.puts("🔍 Starting X12 translation for: #{filename}")

  case ClaimViewer.X12Translator.translate_x12_to_json(x12_path) do
    {:ok, json_data} ->
      IO.puts("✅ Translation successful!")
      IO.puts("📊 JSON data type: #{inspect(is_list(json_data))}")

# Fix: Flatten nested arrays from parser
json_data = case json_data do
  [first | _] when is_list(first) -> first
  _ -> json_data
end

      process_and_save_claim(conn, json_data, filename)

    {:error, reason} ->
      IO.puts("❌ Translation failed: #{reason}")
      conn
      |> put_flash(:error, "X12 translation failed: #{reason}")
      |> redirect(to: "/")
  end
end

  # Handle JSON files (existing logic)
  defp handle_json_upload(conn, json_path) do
    json_data =
      json_path
      |> File.read!()
      |> Jason.decode!()

    json_data = case json_data do
      [first | _] when is_list(first) -> first
      _ -> json_data
    end

    process_and_save_claim(conn, json_data, "uploaded.json")
  end

  # Save claim to database
  defp process_and_save_claim(conn, json_data, source_filename) do
    search_fields = Claims.extract_search_fields(json_data)

    date_of_service =
      try do
        Claims.extract_date_of_service(json_data)
      rescue
        _ -> nil
      end

    attrs =
      %{raw_json: json_data, date_of_service: date_of_service}
      |> Map.merge(search_fields)

    %Claim{}
    |> Claim.changeset(attrs)
    |> Repo.insert!()

    conn
    |> put_flash(:info, "✅ Claim uploaded successfully from #{source_filename}")
    |> redirect(to: "/")
  end

  # ===== EXPORT PDF =====

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

  case ClaimViewer.PDF.generate(html_content) do
    {:ok, pdf_binary} ->
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="claim_#{id}.pdf"))
      |> send_resp(200, pdf_binary)

    {:error, :pdf_unavailable} ->
      conn
      |> put_flash(:error, "PDF export is not available. wkhtmltopdf may not be installed or configured correctly.")
      |> redirect(to: "/claims/#{id}")

    {:error, reason} ->
      conn
      |> put_flash(:error, "Failed to generate PDF: #{inspect(reason)}")
      |> redirect(to: "/claims/#{id}")
  end
end
  # ===== EXPORT CSV =====

  def export_csv(conn, %{"id" => id}) do
    claim = Repo.get!(Claim, id)

    subscriber = Enum.find(claim.raw_json, fn s -> s["section"] == "subscriber" end) || %{}
    subscriber_data = subscriber["data"] || %{}

    payer = Enum.find(claim.raw_json, fn s -> s["section"] == "payer" end) || %{}
    payer_data = payer["data"] || %{}

    claim_section = Enum.find(claim.raw_json, fn s -> s["section"] == "claim" end) || %{}
    claim_data = claim_section["data"] || %{}

    service_lines_section = Enum.find(claim.raw_json, fn s ->
      String.downcase(s["section"] || "") |> String.contains?("service")
    end) || %{}
    service_data = service_lines_section["data"] || []

    service_dates = if is_list(service_data) and service_data != [] do
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
Patient: #{subscriber_data["firstName"]} #{subscriber_data["lastName"]} (DOB: #{format_date_plain(subscriber_data["dob"])})
Payer: #{payer_data["name"]}
Claim #: #{claim_data["clearinghouseClaimNumber"] || claim_data["id"]}
Service Dates: #{if first_date && last_date do
  if first_date == last_date do
    format_date_plain(first_date)
  else
    "#{format_date_plain(first_date)} - #{format_date_plain(last_date)}"
  end
else
  ""
end}
Total Charge: $#{format_number(claim_data["totalCharge"])}
Status: #{status}


#{build_all_sections_csv(claim.raw_json)}

Generated: #{DateTime.utc_now() |> DateTime.to_string()}
"""

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="claim_#{id}.csv"))
    |> send_resp(200, csv_content)
  end

  # ===== CSV HELPERS =====

  defp build_all_sections_csv(sections) do
    sections
    |> Enum.map(fn section ->
      section_name = (section["section"] || "") |> String.replace("_", " ") |> String.upcase()
      data = section["data"] || %{}

      section_content = """
#{section_name}
#{String.duplicate("-", String.length(section_name))}
#{render_section_csv(data)}
"""
      section_content
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
        value = case v do
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

  # ===== QUERY HELPERS =====

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

  # ===== PDF HELPERS =====

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
