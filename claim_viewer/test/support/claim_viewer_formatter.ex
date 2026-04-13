defmodule ClaimViewer.TestFormatter do
  @moduledoc """
  Custom ExUnit formatter producing QuickCheck-style grouped output.

  Property tests display inline with `...` indicators.
  Unit tests display one per line with `... OK` indicators.
  Results are grouped by module and describe block.
  """
  use GenServer

  # ── GenServer callbacks ─────────────────────────────────

  @impl true
  def init(opts) do
    {:ok,
     %{
       seed: opts[:seed],
       tests: [],
       excluded: 0,
       skipped: 0
     }}
  end

  @impl true
  def handle_cast({:suite_started, _opts}, state), do: {:noreply, state}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _}}}, state) do
    {:noreply, %{state | excluded: state.excluded + 1}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:skipped, _}}}, state) do
    {:noreply, %{state | skipped: state.skipped + 1}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:invalid, _}}}, state) do
    {:noreply, state}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    {:noreply, %{state | tests: [test | state.tests]}}
  end

  # Handle both old (3-tuple) and new (map) suite_finished formats
  def handle_cast({:suite_finished, run_us, _load_us}, state) when is_integer(run_us) do
    do_suite_finished(state, run_us)
  end

  def handle_cast({:suite_finished, %{run: run_us}}, state) do
    do_suite_finished(state, run_us)
  end

  def handle_cast({:suite_finished, _times}, state) do
    do_suite_finished(state, 0)
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  defp do_suite_finished(state, run_us) do
    tests = Enum.reverse(state.tests)
    render(tests, run_us, state)
    {:noreply, state}
  end

  # ── Main render ─────────────────────────────────────────

  defp render(tests, run_us, state) do
    {prop_tests, unit_tests} = Enum.split_with(tests, &property_module?/1)

    if prop_tests != [], do: render_property_suite(prop_tests)
    if unit_tests != [], do: render_unit_suite(unit_tests)

    failed = Enum.filter(tests, &failed?/1)
    if failed != [], do: render_failures(failed)

    render_footer(prop_tests, unit_tests, run_us, state)
  end

  # ── Property Suite ──────────────────────────────────────

  defp render_property_suite(tests) do
    header = "ClaimViewer — Property Suite"
    IO.puts("")
    IO.puts(bold(header))
    IO.puts(String.duplicate("=", max(String.length(header), 40)))

    # Group by module first, then by describe within each module
    tests
    |> Enum.group_by(& &1.module)
    |> Enum.sort_by(fn {mod, _} -> module_sort_key(mod) end)
    |> Enum.each(fn {_mod, mod_tests} ->
      for {section_header, section_tests} <- group_by_section(mod_tests) do
        IO.puts("")
        IO.puts(bold(section_header))
        IO.puts(String.duplicate("-", max(String.length(section_header), 40)))

        {props, units} = Enum.split_with(section_tests, &property_test?/1)
        if props != [], do: render_properties_inline(props)
        Enum.each(units, &render_unit_line/1)

        render_section_summary(section_tests)
      end

      render_module_subtotal(mod_tests)
    end)

    total = length(tests)
    failures = Enum.count(tests, &failed?/1)
    IO.puts("")
    IO.puts("Property-based testing: #{total} ran, #{failures} failures")
  end

  defp render_module_subtotal(module_tests) do
    props = Enum.filter(module_tests, &property_test?/1)
    prop_count = length(props)

    if prop_count > 0 do
      parameterized =
        Enum.reduce(props, 0, fn test, acc ->
          acc + (test.tags[:max_runs] || 100)
        end)

      max_runs_values = Enum.map(props, fn t -> t.tags[:max_runs] || 100 end)

      runs_label =
        if length(Enum.uniq(max_runs_values)) == 1 do
          "#{hd(max_runs_values)} runs"
        else
          "mixed runs"
        end

      failed_count = Enum.count(props, &failed?/1)
      status = if failed_count == 0, do: "✓", else: "✗"

      line =
        "  #{prop_count} properties × #{runs_label} = #{format_number(parameterized)} #{status}"

      IO.puts("")
      IO.puts("  ─────────────────────────────────────")

      if failed_count == 0, do: IO.puts(green(line)), else: IO.puts(red(line))

      IO.puts("  ─────────────────────────────────────")
    end
  end

  # ── Unit Suite ──────────────────────────────────────────

  defp render_unit_suite(tests) do
    header = "ClaimViewer — Unit Tests"
    IO.puts("")
    IO.puts(bold(header))
    IO.puts(String.duplicate("=", max(String.length(header), 40)))

    for {section_header, section_tests} <- group_by_section(tests) do
      IO.puts("")
      IO.puts(bold(section_header))
      IO.puts(String.duplicate("-", max(String.length(section_header), 40)))

      Enum.each(section_tests, &render_unit_line/1)

      render_section_summary(section_tests)
    end

    total = length(tests)
    failures = Enum.count(tests, &failed?/1)
    IO.puts("")
    IO.puts("Unit testing: #{total} ran, #{failures} failures")
  end

  # ── Section summary ─────────────────────────────────────

  defp render_section_summary(section_tests) do
    total = length(section_tests)
    passed = Enum.count(section_tests, &(not failed?(&1)))
    failed_count = total - passed

    summary =
      if failed_count == 0 do
        green("  #{total} ran, 0 failed")
      else
        red("  #{total} ran, #{failed_count} failed")
      end

    IO.puts(summary)
  end

  # ── Line rendering ──────────────────────────────────────

  defp render_properties_inline(tests) do
    parts =
      Enum.map(tests, fn test ->
        name = display_name(test)
        if failed?(test), do: "#{name} " <> red("✗"), else: "#{name} " <> green("...")
      end)

    IO.puts("  " <> Enum.join(parts, "   "))
  end

  defp render_unit_line(test) do
    name = display_name(test)
    status = if failed?(test), do: red("FAIL"), else: green("OK")
    IO.puts("  #{name} ... #{status}")
  end

  # ── Failure details ─────────────────────────────────────

  defp render_failures(failed) do
    IO.puts("")
    IO.puts(red("────── Failures ──────"))

    failed
    |> Enum.with_index(1)
    |> Enum.each(fn {test, counter} ->
      IO.puts("")
      label = full_test_label(test)
      IO.puts("  #{counter}) #{label}")
      IO.puts(faint("     #{test.tags.file}:#{test.tags.line}"))

      case test.state do
        {:failed, failures} ->
          for {kind, reason, stack} <- failures do
            banner = Exception.format_banner(kind, reason, stack)

            banner
            |> String.split("\n")
            |> Enum.each(fn line -> IO.puts("     " <> red(line)) end)

            stack
            |> Enum.take(5)
            |> Enum.each(fn entry ->
              IO.puts(faint("       " <> Exception.format_stacktrace_entry(entry)))
            end)
          end

        _ ->
          :ok
      end
    end)
  end

  defp full_test_label(test) do
    name = display_name(test)
    desc = test.tags[:describe]
    mod = module_short_name(test.module)
    parts = [mod, desc, name] |> Enum.reject(&is_nil/1)
    Enum.join(parts, " — ")
  end

  # ── Footer ──────────────────────────────────────────────

  defp render_footer(prop_tests, unit_tests, run_us, state) do
    {io_props, pure_props} = Enum.split_with(prop_tests, &io_test?/1)
    {io_units, pure_units} = Enum.split_with(unit_tests, &io_test?/1)
    _io_checks = io_props ++ io_units

    all_tests = prop_tests ++ unit_tests
    total_failures = Enum.count(all_tests, &failed?/1)

    categories =
      [
        {"Properties", pure_props},
        {"Prop. IO", io_props},
        {"Unit", pure_units},
        {"Unit IO", io_units}
      ]
      |> Enum.reject(fn {_, tests} -> tests == [] end)

    label_width =
      categories
      |> Enum.map(fn {label, _} -> String.length(label) end)
      |> Enum.max(fn -> 5 end)
      |> max(String.length("Total"))

    separator = "────────────────────────────────────────"

    IO.puts("")
    IO.puts(bold("Summary"))
    IO.puts(separator)

    for {label, tests} <- categories, do: render_summary_line(label, tests, label_width)
    render_summary_line("Total", all_tests, label_width)

    IO.puts(separator)

    # Parameterized test depth — computed from @tag max_runs on each property
    all_props = Enum.filter(prop_tests, &property_test?/1)
    prop_count = length(all_props)

    parameterized_total =
      Enum.reduce(all_props, 0, fn test, acc ->
        acc + (test.tags[:max_runs] || 100)
      end)

    if prop_count > 0 do
      IO.puts(
        "#{prop_count} properties | #{format_number(parameterized_total)} parameterized tests"
      )
    end

    if total_failures == 0 do
      IO.puts(green("All tests passed. ✓"))
    else
      IO.puts(red("One or more tests FAILED. ✗"))
    end

    seconds = Float.round(run_us / 1_000_000, 1)
    IO.puts("")
    IO.puts("Finished in #{seconds}s")

    if state.excluded > 0, do: IO.puts("#{state.excluded} excluded")
    if state.skipped > 0, do: IO.puts("#{state.skipped} skipped")

    IO.puts("Randomized with seed #{state.seed}")
  end

  defp render_summary_line(label, tests, label_width) do
    passed = Enum.count(tests, &(not failed?(&1)))
    failed_count = Enum.count(tests, &failed?/1)
    padded = String.pad_trailing(label, label_width)
    line = "#{padded} : #{passed} passed, #{failed_count} failed"

    if failed_count == 0, do: IO.puts(green(line)), else: IO.puts(red(line))
  end

  # ── Grouping helpers ────────────────────────────────────

  defp group_by_section(tests) do
    tests
    |> Enum.group_by(fn t -> {t.module, t.tags[:describe]} end)
    |> Enum.sort_by(fn {{mod, desc}, _} -> {module_sort_key(mod), desc || ""} end)
    |> Enum.map(fn {{mod, desc}, items} ->
      header =
        case desc do
          nil -> module_short_name(mod)
          d -> "#{module_short_name(mod)}: #{title_case(d)}"
        end

      {header, items}
    end)
  end

  defp module_sort_key(mod), do: mod |> Module.split() |> Enum.join(".")

  defp module_short_name(module) do
    raw =
      module
      |> Module.split()
      |> List.last()
      |> String.replace_suffix("Test", "")
      |> String.replace_suffix("Properties", "")
      |> String.trim()

    name = if raw == "", do: module |> Module.split() |> List.last(), else: raw
    humanize_camel(name)
  end

  defp humanize_camel(str) do
    str
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1 \\2")
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1 \\2")
  end

  defp title_case(str) do
    str
    |> String.split(~r/[\s_]+/)
    |> Enum.map_join(" ", fn
      "" -> ""
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
    end)
  end

  # ── Predicates ──────────────────────────────────────────

  defp property_module?(test) do
    test.module |> Module.split() |> Enum.any?(&(&1 == "Properties"))
  end

  defp property_test?(test), do: test.tags[:property] == true

  defp io_test?(test), do: test.tags[:io] == true

  defp failed?(test), do: match?({:failed, _}, test.state)

  defp display_name(test) do
    full = Atom.to_string(test.name)

    stripped =
      cond do
        String.starts_with?(full, "property ") -> String.slice(full, 9..-1//1)
        String.starts_with?(full, "test ") -> String.slice(full, 5..-1//1)
        true -> full
      end

    case test.tags[:describe] do
      nil -> stripped
      desc -> String.replace_prefix(stripped, desc <> " ", "")
    end
  end

  # ── ANSI colors ─────────────────────────────────────────

  defp green(t), do: colorize(IO.ANSI.green(), t)
  defp red(t), do: colorize(IO.ANSI.red(), t)
  defp bold(t), do: colorize(IO.ANSI.bright(), t)
  defp faint(t), do: colorize(IO.ANSI.faint(), t)

  defp colorize(code, text) do
    if IO.ANSI.enabled?() do
      code <> text <> IO.ANSI.reset()
    else
      text
    end
  end

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
