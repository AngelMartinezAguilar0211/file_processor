defmodule API.FileProcessor.CLI do
  @moduledoc false

  # Entry point for escript.
  # Parses CLI arguments and delegates to FileProcessor.run/4.
  @spec main([String.t()]) :: no_return()
  def main(argv) when is_list(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [
          output: :string,
          mode: :string,
          max_workers: :string,
          timeout_ms: :string,
          retries: :string,
          error_log_path: :string,
          help: :boolean
        ],
        aliases: [
          o: :output,
          m: :mode,
          h: :help
        ]
      )

    cond do
      opts[:help] == true ->
        print_help()
        System.halt(0)

      invalid != [] ->
        IO.puts("Invalid options: #{inspect(invalid)}\n")
        print_help()
        System.halt(1)

      args == [] ->
        IO.puts("Missing input path(s).\n")
        print_help()
        System.halt(1)

      true ->
        run_with_args(opts, args)
    end
  end

  # Runs the processor using parsed args.
  @spec run_with_args([String.t()], String.t()) :: no_return()
  defp run_with_args(opts, args) do
    # Inputs can be a single path or multiple paths.
    input =
      case args do
        [one] -> one
        many -> many
      end

    out_path = opts[:output] || "reporte_final.txt"
    mode = normalize_mode(opts[:mode] || "parallel")

    run_opts =
      []
      |> maybe_put(:max_workers, parse_int_or_infinity(opts[:max_workers]))
      |> maybe_put(:timeout_ms, parse_int_or_infinity(opts[:timeout_ms]))
      |> maybe_put(:retries, parse_nonneg_int(opts[:retries]))
      |> maybe_put(:error_log_path, opts[:error_log_path])

    case API.FileProcessor.run(input, out_path, mode, run_opts) do
      {:ok, report_path} ->
        IO.puts("OK: #{report_path}")
        System.halt(0)

      {:error, errors} when is_list(errors) ->
        IO.puts("ERROR: #{length(errors)} issue(s)")
        Enum.each(errors, &print_error/1)
        System.halt(1)
    end
  end

  # Adds a keyword option only when value is not nil.
  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, value), do: Keyword.put(acc, key, value)

  # Normalizes mode values.
  defp normalize_mode("parallel"), do: "parallel"
  defp normalize_mode("sequential"), do: "sequential"
  defp normalize_mode(other), do: other

  # Parses integer or the literal "infinity" -> :infinity.
  defp parse_int_or_infinity(nil), do: nil
  defp parse_int_or_infinity("infinity"), do: :infinity
  defp parse_int_or_infinity("Infinity"), do: :infinity
  defp parse_int_or_infinity("INFINITY"), do: :infinity

  defp parse_int_or_infinity(str) when is_binary(str) do
    case Integer.parse(str) do
      {v, ""} when v > 0 -> v
      _ -> nil
    end
  end

  # Parses a non-negative integer (e.g., retries).
  defp parse_nonneg_int(nil), do: nil

  defp parse_nonneg_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {v, ""} when v >= 0 -> v
      _ -> nil
    end
  end

  # Prints one error item
  defp print_error(%{path: path, reason: reason, details: details}) do
    IO.puts(" - #{inspect(path)}: #{inspect(reason)} (#{inspect(details)})")
  end

  defp print_error(%{path: path, error: error}) do
    IO.puts(" - #{inspect(path)}: #{inspect(error)}")
  end

  defp print_error(other) do
    IO.puts(" - #{inspect(other)}")
  end

  # Help/usage text.
  defp print_help do
    IO.puts("""
    FileProcessor (escript)

    Usage:
      file_processor <input...> [options]

    Inputs:
      <input...> one or more paths (files and/or directories)

    Options:
      -o, --output <path>             Output report path (default: reporte_final.txt)
      -m, --mode <parallel|sequential> Processing mode (default: parallel)

          --max-workers <N|infinity>  Max concurrent workers (parallel only)
          --timeout-ms <N|infinity>   Per-worker timeout in ms (parallel only)
          --retries <N>               Retry attempts per file (parallel only)
          --error-log-path <path>     Detailed error log path (optional)
      -h, --help                      Show this help
    """)
  end
end
