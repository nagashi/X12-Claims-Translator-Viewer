defmodule ClaimViewerWeb.PageController do
  use ClaimViewerWeb, :controller

  alias ClaimViewer.Claims

  # ===== Actions =====

  def dashboard(conn, _params) do
    stats = Claims.dashboard_stats()
    render(conn, :dashboard, Map.to_list(stats))
  end

  def home(conn, params) do
    filters = trim_filters(params)
    page = parse_page(params)
    per_page = 10

    {claims, meta} = Claims.list_claims(filters, %{page: page, per_page: per_page})

    render(conn, :home,
      claims: claims,
      show_results: meta.total_count > 0 or has_search?(filters),
      member_first: filters["member_first"],
      member_last: filters["member_last"],
      payer: filters["payer"],
      billing_provider: filters["billing_provider"],
      rendering_provider: filters["rendering_provider"],
      claim_number: filters["claim_number"],
      service_from: filters["service_from"],
      service_to: filters["service_to"],
      page: meta.page,
      total_pages: meta.total_pages,
      total_count: meta.total_count,
      json: nil,
      status: filters["status"],
      claim_id: nil
    )
  end

  def show(conn, %{"id" => id}) do
    claim = Claims.get_claim!(id)

    render(conn, :home,
      claims: [],
      show_results: false,
      member_first: "",
      member_last: "",
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
      status: "",
      claim_id: id
    )
  end

  # ===== Upload =====

  def upload(conn, %{"file" => %Plug.Upload{path: path, filename: filename}}) do
    case Claims.Ingestion.ingest_file(path, filename) do
      {:ok, result} ->
        conn
        |> build_upload_flash(filename, result)
        |> redirect(to: "/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Upload failed: #{reason}")
        |> redirect(to: "/")
    end
  end

  def upload(conn, _params) do
    conn
    |> put_flash(:error, "No file selected. Please choose an X12 claim file to upload.")
    |> redirect(to: "/")
  end

  # ===== Export =====

  def export_pdf(conn, %{"id" => id}) do
    claim = Claims.get_claim!(id)

    case ClaimViewer.Export.PDF.render(claim) do
      {:ok, pdf_binary} ->
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

  def export_csv(conn, %{"id" => id}) do
    claim = Claims.get_claim!(id)
    {:ok, csv_content} = ClaimViewer.Export.CSV.render(claim)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="claim_#{id}.csv"))
    |> send_resp(200, csv_content)
  end

  # ===== Private Helpers =====

  @filter_keys ~w(member_first member_last payer billing_provider
                  rendering_provider claim_number service_from service_to status)

  defp trim_filters(params) do
    Map.new(@filter_keys, fn key ->
      {key, params |> Map.get(key, "") |> String.trim()}
    end)
  end

  defp parse_page(params) do
    case Integer.parse(Map.get(params, "page", "1")) do
      {num, _} -> num
      :error -> 1
    end
  end

  defp has_search?(filters) do
    Enum.any?(@filter_keys, fn key ->
      val = filters[key]
      val != "" and (String.length(val) >= 2 or key in ~w(service_from service_to status))
    end)
  end

  defp build_upload_flash(conn, filename, %{success_count: sc, total: total, failures: failures}) do
    cond do
      sc == total and total == 1 ->
        put_flash(conn, :info, "Claim uploaded successfully from #{filename}")

      sc == total ->
        put_flash(conn, :info, "All #{sc} claims uploaded successfully from #{filename}")

      sc > 0 ->
        error_msgs = Enum.join(failures, "; ")

        conn
        |> put_flash(:info, "#{sc} of #{total} claims saved from #{filename}")
        |> put_flash(:error, "Failed claims: #{error_msgs}")

      true ->
        error_msgs = Enum.join(failures, "; ")
        put_flash(conn, :error, "All #{total} claims failed from #{filename}: #{error_msgs}")
    end
  end
end
