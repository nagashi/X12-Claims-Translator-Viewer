defmodule ClaimViewerWeb.PageController do
  use ClaimViewerWeb, :controller

  alias ClaimViewer.Repo
  alias ClaimViewer.Claims
  alias ClaimViewer.Claims.Claim
  import Ecto.Query

  def home(conn, params) do
    first = Map.get(params, "patient_first", "")
    last = Map.get(params, "patient_last", "")
    payer = Map.get(params, "payer", "")
    billing_provider = Map.get(params, "billing_provider", "")
    rendering_provider = Map.get(params, "rendering_provider", "")
    claim_number = Map.get(params, "claim_number", "")
    service_from = Map.get(params, "service_from", "")
    service_to = Map.get(params, "service_to", "")

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
    date_of_service = Claims.extract_date_of_service(json)

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

defp maybe_date_range(query, from, to) do
  {:ok, from_date} = Date.from_iso8601(from)
  {:ok, to_date} = Date.from_iso8601(to)

  where(query, [c],
    c.date_of_service >= ^from_date and
    c.date_of_service <= ^to_date
  )
end

end
