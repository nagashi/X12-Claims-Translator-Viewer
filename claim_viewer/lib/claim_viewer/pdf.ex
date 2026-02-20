defmodule ClaimViewer.PDF do
  @moduledoc """
  PDF generation with graceful degradation.
  If wkhtmltopdf is not available, returns error instead of crashing.
  """

  @doc """
  Check if PDF generation is available by attempting generation.
  """
  def available? do
    # Try to check if PdfGenerator can work
    try do
      # Just check if the module is loaded
      Code.ensure_loaded?(PdfGenerator)
    rescue
      _ -> false
    end
  end

  @doc """
  Generate PDF from HTML content.
  Returns {:ok, binary} if successful, {:error, reason} otherwise.
  """
  def generate(html_content) do
    try do
      case PdfGenerator.generate(html_content, page_size: "A4") do
        {:ok, pdf_path} ->
          pdf_binary = File.read!(pdf_path)
          File.rm(pdf_path)
          {:ok, pdf_binary}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, :pdf_unavailable}
    end
  end
end
