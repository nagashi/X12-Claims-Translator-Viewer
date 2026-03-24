defmodule ClaimViewer.Claims do
  @moduledoc """
  Context for claim queries, CRUD operations, dashboard statistics,
  and search-field extraction from raw claim JSON.
  """

  alias ClaimViewer.Repo
  alias ClaimViewer.Claims.Claim
  import Ecto.Query

  # ===== CRUD =====

  @doc "Fetch a single claim by ID or raise."
  def get_claim!(id), do: Repo.get!(Claim, id)

  @doc "Insert a new claim. Returns `{:ok, claim}` or `{:error, changeset}`."
  def create_claim(attrs) do
    %Claim{}
    |> Claim.changeset(attrs)
    |> Repo.insert()
  end

  # ===== Listing / Search =====

  @doc """
  List claims matching the given filters with pagination.

  `filters` is a map with optional string keys:
    "member_first", "member_last", "payer", "billing_provider",
    "rendering_provider", "claim_number", "service_from", "service_to", "status"

  `pagination` is a map with `:page` (1-based) and `:per_page`.

  Returns `{claims, %{total_count: n, total_pages: n, page: n}}`.
  """
  def list_claims(filters, %{page: page, per_page: per_page} = _pagination) do
    first = Map.get(filters, "member_first", "")
    last = Map.get(filters, "member_last", "")
    payer = Map.get(filters, "payer", "")
    billing_provider = Map.get(filters, "billing_provider", "")
    rendering_provider = Map.get(filters, "rendering_provider", "")
    claim_number = Map.get(filters, "claim_number", "")
    service_from = Map.get(filters, "service_from", "")
    service_to = Map.get(filters, "service_to", "")
    status = Map.get(filters, "status", "")

    has_search? =
      valid_search?(first) or
        valid_search?(last) or
        valid_search?(payer) or
        valid_search?(billing_provider) or
        valid_search?(rendering_provider) or
        valid_search?(claim_number) or
        service_from != "" or
        service_to != "" or
        status != ""

    if has_search? do
      start_time = System.monotonic_time()
      offset = (page - 1) * per_page

      query =
        from(c in Claim)
        |> maybe_full_name(first, last)
        |> maybe_like(:payer_name, payer)
        |> maybe_like(:billing_provider_name, billing_provider)
        |> maybe_exact(:rendering_provider_npi, rendering_provider)
        |> maybe_like(:clearinghouse_claim_number, claim_number)
        |> maybe_date_range(service_from, service_to)
        |> maybe_status(status)
        |> order_by([c], desc: c.inserted_at)

      total_count = Repo.aggregate(query, :count, :id)
      claims = query |> limit(^per_page) |> offset(^offset) |> Repo.all()
      total_pages = if total_count > 0, do: ceil(total_count / per_page), else: 0

      result = {claims, %{total_count: total_count, total_pages: total_pages, page: page}}
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:claim_viewer, :search, :stop],
        %{duration: duration},
        %{total_count: total_count}
      )

      result
    else
      {[], %{total_count: 0, total_pages: 0, page: page}}
    end
  end

  defp valid_search?(value), do: String.length(value) >= 2

  # ===== Dashboard Stats =====

  @doc """
  Returns dashboard statistics computed via SQL aggregates.

  Keys: `:total_claims`, `:approved_count`, `:approved_revenue`,
  `:pending_count`, `:old_claims`, `:this_month_count`.
  """
  def dashboard_stats do
    total_claims = Repo.aggregate(Claim, :count, :id)

    # Approved: all indicators are Y/A/I (reuses the SQL fragment from maybe_status)
    approved_query =
      from(c in Claim,
        where:
          fragment(
            """
            EXISTS (
              SELECT 1
              FROM jsonb_array_elements(?::jsonb) AS elem,
                   jsonb_each_text(elem->'data'->'indicators') AS ind
              WHERE elem->>'section' = 'claim'
                AND jsonb_typeof(elem->'data'->'indicators') = 'object'
              GROUP BY elem
              HAVING COUNT(*) > 0
                AND COUNT(*) FILTER (WHERE ind.value IN ('Y', 'A', 'I')) = COUNT(*)
            )
            """,
            c.raw_json
          )
      )

    approved_count = Repo.aggregate(approved_query, :count, :id)

    # Revenue for approved claims — sum totalCharge from the claim section JSON
    approved_revenue =
      Repo.one(
        from(c in approved_query,
          select:
            coalesce(
              fragment(
                """
                (SELECT SUM((elem->'data'->>'totalCharge')::numeric)
                 FROM jsonb_array_elements(?::jsonb) AS elem
                 WHERE elem->>'section' = 'claim')
                """,
                c.raw_json
              ),
              0
            )
        )
      ) || 0

    pending_count = total_claims - approved_count

    thirty_days_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-30 * 24 * 60 * 60, :second)

    old_claims =
      Repo.aggregate(from(c in Claim, where: c.inserted_at < ^thirty_days_ago), :count, :id)

    now = NaiveDateTime.utc_now()
    first_day = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    this_month_count =
      Repo.aggregate(from(c in Claim, where: c.inserted_at >= ^first_day), :count, :id)

    %{
      total_claims: total_claims,
      approved_count: approved_count,
      approved_revenue: approved_revenue,
      pending_count: pending_count,
      old_claims: old_claims,
      this_month_count: this_month_count
    }
  end

  # ===== Search field extraction =====

  def extract_search_fields(sections) when is_list(sections) do
    %{
      member_first_name: get_in_section(sections, "subscriber", ["firstName"]),
      member_last_name: get_in_section(sections, "subscriber", ["lastName"]),
      member_dob: get_in_section(sections, "subscriber", ["dob"]),
      payer_name: get_in_section(sections, "payer", ["name"]),
      billing_provider_name: get_in_section(sections, "billing_Provider", ["name"]),
      pay_to_provider_name: get_in_section(sections, "Pay_To_provider", ["name"]),
      rendering_provider_name: get_in_section(sections, "renderingProvider", ["firstName"]),
      rendering_provider_npi: get_in_section(sections, "renderingProvider", ["npi"]),
      clearinghouse_claim_number: get_in_section(sections, "claim", ["clearinghouseClaimNumber"])
    }
  end

  def extract_search_fields(_), do: %{}

  @doc """
  Extract the date of service from the first service line.
  Returns `{:ok, date}` or `{:error, reason}`.
  """
  def extract_date_of_service(sections) do
    sections
    |> Enum.find(fn s -> get_section_name(s) == "service_Lines" end)
    |> case do
      nil ->
        {:error, :no_service_lines}

      s ->
        data = get_section_data(s)

        case data do
          [first | _] ->
            case Date.from_iso8601(first["serviceDate"] || "") do
              {:ok, date} -> {:ok, date}
              {:error, _} -> {:error, :invalid_date}
            end

          _ ->
            {:error, :empty_service_lines}
        end
    end
  end

  # ===== Private Helpers =====

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

  defp get_section_name(%{"section" => name}), do: name
  defp get_section_name(s) when is_list(s), do: Keyword.get(s, :section)

  defp get_section_data(%{"data" => data}), do: data
  defp get_section_data(s) when is_list(s), do: Keyword.get(s, :data)

  # ===== Query Helpers =====

  defp sanitize_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp maybe_like(query, _field, ""), do: query

  defp maybe_like(query, field, value) do
    sanitized = sanitize_like(value)
    where(query, [c], ilike(field(c, ^field), ^"%#{sanitized}%"))
  end

  defp maybe_exact(query, _field, ""), do: query

  defp maybe_exact(query, field, value) do
    where(query, [c], field(c, ^field) == ^value)
  end

  defp maybe_full_name(query, first, last) do
    cond do
      first != "" and last != "" ->
        sf = sanitize_like(first)
        sl = sanitize_like(last)

        where(
          query,
          [c],
          ilike(c.member_first_name, ^"%#{sf}%") and
            ilike(c.member_last_name, ^"%#{sl}%")
        )

      first != "" ->
        sf = sanitize_like(first)
        where(query, [c], ilike(c.member_first_name, ^"%#{sf}%"))

      last != "" ->
        sl = sanitize_like(last)
        where(query, [c], ilike(c.member_last_name, ^"%#{sl}%"))

      true ->
        query
    end
  end

  defp maybe_date_range(query, "", ""), do: query

  defp maybe_date_range(query, from, "") do
    case Date.from_iso8601(from) do
      {:ok, from_date} -> where(query, [c], c.date_of_service >= ^from_date)
      _ -> query
    end
  end

  defp maybe_date_range(query, "", to) do
    case Date.from_iso8601(to) do
      {:ok, to_date} -> where(query, [c], c.date_of_service <= ^to_date)
      _ -> query
    end
  end

  defp maybe_date_range(query, from, to) do
    case {Date.from_iso8601(from), Date.from_iso8601(to)} do
      {{:ok, from_date}, {:ok, to_date}} ->
        where(
          query,
          [c],
          not is_nil(c.date_of_service) and
            c.date_of_service >= ^from_date and
            c.date_of_service <= ^to_date
        )

      _ ->
        query
    end
  end

  defp maybe_status(query, ""), do: query

  defp maybe_status(query, "approved") do
    from(c in query,
      where:
        fragment(
          """
          EXISTS (
            SELECT 1
            FROM jsonb_array_elements(?::jsonb) AS elem,
                 jsonb_each_text(elem->'data'->'indicators') AS ind
            WHERE elem->>'section' = 'claim'
              AND jsonb_typeof(elem->'data'->'indicators') = 'object'
            GROUP BY elem
            HAVING COUNT(*) > 0
              AND COUNT(*) FILTER (WHERE ind.value IN ('Y', 'A', 'I')) = COUNT(*)
          )
          """,
          c.raw_json
        )
    )
  end

  defp maybe_status(query, "pending") do
    from(c in query,
      where:
        fragment(
          """
          NOT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(?::jsonb) AS elem,
                 jsonb_each_text(elem->'data'->'indicators') AS ind
            WHERE elem->>'section' = 'claim'
              AND jsonb_typeof(elem->'data'->'indicators') = 'object'
            GROUP BY elem
            HAVING COUNT(*) > 0
              AND COUNT(*) FILTER (WHERE ind.value IN ('Y', 'A', 'I')) = COUNT(*)
          )
          """,
          c.raw_json
        )
    )
  end

  defp maybe_status(query, _), do: query
end
