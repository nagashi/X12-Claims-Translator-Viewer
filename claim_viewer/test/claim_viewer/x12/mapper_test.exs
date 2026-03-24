defmodule ClaimViewer.X12.MapperTest do
  use ExUnit.Case, async: true

  alias ClaimViewer.X12.Mapper

  @valid_sections [
    %{"section" => "transaction", "data" => %{"type" => "837", "controlNumber" => "0001"}},
    %{"section" => "subscriber", "data" => %{"firstName" => "Jane", "lastName" => "Doe"}},
    %{"section" => "payer", "data" => %{"name" => "BlueCross"}},
    %{"section" => "claim", "data" => %{"totalCharge" => 100.0}},
    %{
      "section" => "service_Lines",
      "data" => [
        %{
          "lineNumber" => 1,
          "procedureCode" => "99213",
          "charge" => 50.0,
          "serviceDate" => "2025-01-01"
        }
      ]
    }
  ]

  describe "from_sections/1" do
    test "maps valid sections to a Claim837 struct" do
      assert {:ok, claim} = Mapper.from_sections(@valid_sections)
      assert claim.subscriber.firstName == "Jane"
      assert claim.payer.name == "BlueCross"
      assert claim.claim.totalCharge == 100.0
      assert length(claim.service_lines) == 1
    end

    test "skips unknown section names" do
      sections = @valid_sections ++ [%{"section" => "unknown_thing", "data" => %{"foo" => "bar"}}]
      assert {:ok, _claim} = Mapper.from_sections(sections)
    end

    test "returns error for non-list input" do
      assert {:error, "Expected a list of section maps"} = Mapper.from_sections("not a list")
    end

    test "returns error when section is not a map" do
      assert {:error, msg} = Mapper.from_sections(["not a map"])
      assert msg =~ "Expected a map"
    end

    test "returns error when section key is missing" do
      assert {:error, msg} = Mapper.from_sections([%{"data" => %{}}])
      assert msg =~ "missing or invalid"
    end

    test "returns error when data key is missing" do
      assert {:error, msg} = Mapper.from_sections([%{"section" => "payer"}])
      assert msg =~ "missing \"data\""
    end

    test "returns error when data is invalid type" do
      assert {:error, msg} = Mapper.from_sections([%{"section" => "payer", "data" => "string"}])
      assert msg =~ "invalid \"data\" type"
    end
  end

  describe "to_validated_sections/1" do
    test "round-trips through structs and back to maps" do
      {:ok, claim} = Mapper.from_sections(@valid_sections)
      sections = Mapper.to_validated_sections(claim)
      assert is_list(sections)
      assert length(sections) == 12

      # Every section has the required shape
      for section <- sections do
        assert is_binary(section["section"])
        assert section["data"] != nil
      end
    end
  end
end
