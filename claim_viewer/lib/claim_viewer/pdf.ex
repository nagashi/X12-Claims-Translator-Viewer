defmodule ClaimViewer.PDF do
  @moduledoc """
  PDF generation with graceful degradation.
  If wkhtmltopdf is not available, returns error instead of crashing.
  """

  @doc """
  Check if wkhtmltopdf executable exists on the system.
  """
  def available? do
    System.find_executable("wkhtmltopdf") != nil
  end

  @doc """
  Generate PDF from HTML content.
  Returns {:ok, binary} if successful, {:error, reason} otherwise.
  """
  def generate(html_content) do
    if not available?() do
      {:error, :pdf_unavailable}
    else
      # Only start pdf_generator if wkhtmltopdf exists
      Application.ensure_all_started(:pdf_generator)

      case PdfGenerator.generate(html_content, page_size: "A4") do
        {:ok, pdf_path} ->
          pdf_binary = File.read!(pdf_path)
          File.rm(pdf_path)
          {:ok, pdf_binary}

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    _ -> {:error, :pdf_unavailable}
  end
end
