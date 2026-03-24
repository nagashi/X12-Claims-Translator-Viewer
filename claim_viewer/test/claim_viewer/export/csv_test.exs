defmodule ClaimViewer.Export.CSVTest do
  use ExUnit.Case, async: true

  alias ClaimViewer.Export.CSV

  @sample_claim %{
    raw_json: [
      %{
        "section" => "subscriber",
        "data" => %{"firstName" => "Jane", "lastName" => "Doe", "dob" => "1990-01-15"}
      },
      %{"section" => "payer", "data" => %{"name" => "BlueCross"}},
      %{
        "section" => "claim",
        "data" => %{
          "clearinghouseClaimNumber" => "CLM-001",
          "totalCharge" => 150.00,
          "indicators" => %{"a" => "Y", "b" => "A"}
        }
      },
      %{
        "section" => "service_Lines",
        "data" => [
          %{
            "serviceDate" => "2025-06-15",
            "procedureCode" => "99213",
            "charge" => 75.0,
            "lineNumber" => 1
          }
        ]
      }
    ]
  }

  describe "render/1" do
    test "returns {:ok, string} with claim summary" do
      assert {:ok, content} = CSV.render(@sample_claim)
      assert is_binary(content)
      assert content =~ "CLAIM SUMMARY"
      assert content =~ "Jane"
      assert content =~ "Doe"
      assert content =~ "BlueCross"
      assert content =~ "CLM-001"
      assert content =~ "150.00"
    end

    test "includes section headers" do
      {:ok, content} = CSV.render(@sample_claim)
      assert content =~ "SUBSCRIBER"
      assert content =~ "PAYER"
      assert content =~ "CLAIM"
    end

    test "shows Approved status when all indicators are Y/A/I" do
      {:ok, content} = CSV.render(@sample_claim)
      assert content =~ "Approved"
    end

    test "shows Pending Review when indicators are empty" do
      pending_claim = %{
        raw_json: [
          %{"section" => "subscriber", "data" => %{"firstName" => "Bob"}},
          %{"section" => "claim", "data" => %{"totalCharge" => 50.0, "indicators" => %{}}}
        ]
      }

      {:ok, content} = CSV.render(pending_claim)
      assert content =~ "Pending Review"
    end

    test "formats dates as human readable" do
      {:ok, content} = CSV.render(@sample_claim)
      assert content =~ "June 15 2025"
    end

    test "includes Generated timestamp" do
      {:ok, content} = CSV.render(@sample_claim)
      assert content =~ "Generated:"
    end
  end
end
