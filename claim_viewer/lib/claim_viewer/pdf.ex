defmodule ClaimViewer.PDF do
  @moduledoc """
  PDF generation using ChromicPDF (Chrome headless).
  """

  @doc """
  Generate PDF from HTML content.
  Returns {:ok, binary} if successful, {:error, reason} otherwise.
  """
  def generate(html_content) do
    case ChromicPDF.print_to_pdf({:html, html_content},
           print_to_pdf: %{paperWidth: 8.5, paperHeight: 11, marginTop: 0.4, marginBottom: 0.4},
           timeout: 30_000
         ) do
      {:ok, blob} ->
        {:ok, Base.decode64!(blob)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
