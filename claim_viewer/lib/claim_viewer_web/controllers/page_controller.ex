defmodule ClaimViewerWeb.PageController do
  use ClaimViewerWeb, :controller

  alias ClaimViewer.Repo
  alias ClaimViewer.Claims
  alias ClaimViewer.Claims.Claim
  import Ecto.Query

  def home(conn, params) do
first = params |> Map.get("patient_first", "") |> String.trim()
last = params |> Map.get("patient_last", "") |> String.trim()
payer = params |> Map.get("payer", "") |> String.trim()
billing_provider = params |> Map.get("billing_provider", "") |> String.trim()
rendering_provider = params |> Map.get("rendering_provider", "") |> String.trim()
claim_number = params |> Map.get("claim_number", "") |> String.trim()
service_from = params |> Map.get("service_from", "") |> String.trim()
service_to = params |> Map.get("service_to", "") |> String.trim()


    has_search? =
      first != "" or last != "" or payer != "" or
        billing_provider != "" or rendering_provider != "" or
        claim_number != "" or service_from != "" or service_to != ""

    claims =
      if has_search? do
        from(c in Claim)
        |> maybe_like(:patient_first_name, first)
        |> maybe_like(:patient_last_name, last)
        |> maybe_like(:payer_name, payer)
        |> maybe_like(:billing_provider_name, billing_provider)
        |> maybe_like(:rendering_provider_npi, rendering_provider)
        |> maybe_like(:clearinghouse_claim_number, claim_number)
        |> maybe_date_range(service_from, service_to)
        |> order_by([c], desc: c.inserted_at)
        |> Repo.all()
      else
        []
      end

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
      json: nil
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
      json: claim.raw_json
    )
  end

  def upload(conn, %{"file" => %Plug.Upload{path: path}}) do
    json =
      path
      |> File.read!()
      |> Jason.decode!()

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

  defp maybe_like(query, _field, ""), do: query
  defp maybe_like(query, field, value) do
    where(query, [c], ilike(field(c, ^field), ^"%#{value}%"))
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


end
