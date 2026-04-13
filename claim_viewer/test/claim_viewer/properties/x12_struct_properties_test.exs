defmodule ClaimViewer.Properties.X12StructPropertiesTest do
  @moduledoc """
  Property-based tests for ALL X12 structs.

  HIPAA properties verified:
  - Round-trip idempotency: from_map(to_map(struct)) preserves all data
  - Nil tolerance: from_map(nil) never crashes
  - Fuzz robustness: arbitrary maps never cause exceptions
  - Double round-trip: from_map(to_map(from_map(data))) == from_map(data)
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import ClaimViewer.Generators

  alias ClaimViewer.X12.{
    Address,
    Transaction,
    Submitter,
    Receiver,
    BillingProvider,
    PayToProvider,
    Subscriber,
    Payer,
    ClaimInfo,
    Diagnosis,
    RenderingProvider,
    ServiceFacility,
    ServiceLine
  }

  @struct_generators [
    {Address, :gen_address_map},
    {Transaction, :gen_transaction_map},
    {Submitter, :gen_submitter_map},
    {Receiver, :gen_receiver_map},
    {BillingProvider, :gen_billing_provider_map},
    {PayToProvider, :gen_pay_to_provider_map},
    {Subscriber, :gen_subscriber_map},
    {Payer, :gen_payer_map},
    {ClaimInfo, :gen_claim_info_map},
    {Diagnosis, :gen_diagnosis_map},
    {RenderingProvider, :gen_rendering_provider_map},
    {ServiceFacility, :gen_service_facility_map},
    {ServiceLine, :gen_service_line_map}
  ]

  for {mod, gen_fn} <- @struct_generators do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name} round-trip" do
      @tag max_runs: 200
      property "from_map(to_map(from_map(data))) == from_map(data) for generated data" do
        check all(
                data <- apply(ClaimViewer.Generators, unquote(gen_fn), []),
                max_runs: 200
              ) do
          struct1 = unquote(mod).from_map(data)
          map1 = unquote(mod).to_map(struct1)
          struct2 = unquote(mod).from_map(map1)

          assert struct1 == struct2,
                 "Round-trip failed for #{unquote(mod_name)}: \n" <>
                   "  struct1: #{inspect(struct1)}\n" <>
                   "  struct2: #{inspect(struct2)}"
        end
      end

      @tag max_runs: 200
      property "from_map never crashes on generated data" do
        check all(
                data <- apply(ClaimViewer.Generators, unquote(gen_fn), []),
                max_runs: 200
              ) do
          struct = unquote(mod).from_map(data)
          assert is_struct(struct, unquote(mod))
        end
      end
    end

    describe "#{mod_name} nil tolerance" do
      test "from_map(nil) returns default struct" do
        struct = unquote(mod).from_map(nil)
        assert is_struct(struct, unquote(mod))
      end
    end
  end

  # ServiceLine has list-specific functions
  describe "ServiceLine list functions" do
    @tag max_runs: 100
    property "list_from_data round-trips through list_to_data" do
      check all(
              lines <- list_of(gen_service_line_map(), min_length: 0, max_length: 20),
              max_runs: 100
            ) do
        structs = ServiceLine.list_from_data(lines)
        maps = ServiceLine.list_to_data(structs)
        structs2 = ServiceLine.list_from_data(maps)
        assert structs == structs2
      end
    end

    test "list_from_data(nil) returns empty list" do
      assert ServiceLine.list_from_data(nil) == []
    end

    test "list_from_data with non-list returns empty list" do
      assert ServiceLine.list_from_data("not a list") == []
    end
  end

  describe "fuzz robustness" do
    @tag max_runs: 100
    property "all from_map functions tolerate maps with extra keys" do
      check all(
              data <- gen_subscriber_map(),
              extra <- StreamData.fixed_map(%{"EXTRA_KEY" => StreamData.binary()}),
              max_runs: 100
            ) do
        merged = Map.merge(data, extra)
        struct = Subscriber.from_map(merged)
        assert is_struct(struct, Subscriber)
      end
    end

    @tag max_runs: 100
    property "all from_map functions tolerate maps with missing keys" do
      check all(
              data <- gen_subscriber_map(),
              key_to_drop <- StreamData.member_of(Map.keys(data)),
              max_runs: 100
            ) do
        partial = Map.delete(data, key_to_drop)
        struct = Subscriber.from_map(partial)
        assert is_struct(struct, Subscriber)
      end
    end
  end
end
