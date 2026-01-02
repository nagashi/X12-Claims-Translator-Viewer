defmodule ClaimViewerWeb.PageController do
  use ClaimViewerWeb, :controller

  alias ClaimViewer.Repo
  alias ClaimViewer.Claims
  alias ClaimViewer.Claims.Claim
  import Ecto.Query

  # SEARCH PAGE
  def home(conn, params) do
    first = Map.get(params, "patient_first", "")
    last = Map.get(params, "patient_last", "")
    payer = Map.get(params, "payer", "")
    billing_provider = Map.get(params, "billing_provider", "")
    rendering_provider = Map.get(params, "rendering_provider", "")
    claim_number = Map.get(params, "claim_number", "")

    has_search? =
      first != "" or last != "" or payer != "" or
        billing_provider != "" or rendering_provider != "" or
        claim_number != ""

    claims =
      if has_search? do
        from(c in Claim)
        |> maybe_like(:patient_first_name, first)
        |> maybe_like(:patient_last_name, last)
        |> maybe_like(:payer_name, payer)
        |> maybe_like(:billing_provider_name, billing_provider)
        |> maybe_like(:rendering_provider_npi, rendering_provider)
        |> maybe_like(:clearinghouse_claim_number, claim_number)
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
      json: nil
    )
  end

  # SHOW SINGLE CLAIM
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
      json: claim.raw_json
    )
  end

  # UPLOAD
  def upload(conn, %{"file" => %Plug.Upload{path: path}}) do
    json =
      path
      |> File.read!()
      |> Jason.decode!()

    search_fields = Claims.extract_search_fields(json)

    %Claim{}
    |> Claim.changeset(Map.merge(%{raw_json: json}, search_fields))
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
end
