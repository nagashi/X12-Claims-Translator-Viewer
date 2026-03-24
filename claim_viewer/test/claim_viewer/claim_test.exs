defmodule ClaimViewer.Claims.ClaimTest do
  use ClaimViewer.DataCase, async: true

  alias ClaimViewer.Claims.Claim

  @valid_attrs %{
    raw_json: [%{"section" => "claim", "data" => %{"id" => "1"}}],
    billing_provider_npi: "1234567890",
    rendering_provider_npi: "0987654321"
  }

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = Claim.changeset(%Claim{}, @valid_attrs)
      assert changeset.valid?
    end

    test "raw_json is required" do
      changeset = Claim.changeset(%Claim{}, %{})
      refute changeset.valid?
      assert %{raw_json: ["can't be blank"]} = errors_on(changeset)
    end

    test "billing_provider_npi must be exactly 10 digits" do
      for bad <- ["123", "abc1234567", "12345678901", "12345-6789"] do
        changeset = Claim.changeset(%Claim{}, %{@valid_attrs | billing_provider_npi: bad})
        refute changeset.valid?, "Expected NPI '#{bad}' to be invalid"
        assert %{billing_provider_npi: _} = errors_on(changeset)
      end
    end

    test "rendering_provider_npi must be exactly 10 digits" do
      changeset = Claim.changeset(%Claim{}, %{@valid_attrs | rendering_provider_npi: "short"})
      refute changeset.valid?
      assert %{rendering_provider_npi: _} = errors_on(changeset)
    end

    test "nil NPI values are accepted (not all claims have NPIs)" do
      attrs = %{@valid_attrs | billing_provider_npi: nil, rendering_provider_npi: nil}
      changeset = Claim.changeset(%Claim{}, attrs)
      assert changeset.valid?
    end
  end
end
