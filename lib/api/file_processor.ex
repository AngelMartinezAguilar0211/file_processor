defmodule API.FileProcessor do
  @moduledoc """
  Main entry point for the FileProcessor system.

  This module:
  - Discovers input files
  - Reads file contents
  - Delegates parsing and metric extraction
  - Generates a unified text report

  Only CSV, JSON and LOG files are supported.
  """
  # Output error structure
  @type read_error :: %{
          path: String.t(),
          reason: atom(),
          details: any()
        }

  # Output structure to return
  @type read_result :: %{
          path: String.t(),
          ext: String.t(),
          bytes: non_neg_integer(),
          content: binary()
        }
  #
  # ------------------------------------------------------ MAIN PROCESS SECTION (RUN) ------------------------------------------------------
  # This section contains run function and its implementations to catch errors and parameters.
  #
  @doc """
  Runs the file processor.

  Default mode is parallel.

  Accepts:
  - A directory path
  - A file path
  - A list of files/directories paths

  Generates a text report and returns its absolute path.

  ## Examples

      iex> {:ok, path} = API.FileProcessor.run("data", "reporte_final.txt", "sequential")
      iex> is_binary(path)
      true

  """
  # Overload allowing custom output path
  def run(input) when is_bitstring(input) or is_list(input),
    do: run(input, "reporte_final.txt", "parallel", [])

  def run(_input), do: run(0, 0, 0, 0)

  def run(input, out_path)
      when is_bitstring(out_path) and (is_bitstring(input) or is_list(input)),
      do: run(input, out_path, "parallel", [])

  def run(_input, _out_path), do: run(0, 0, 0, 0)

  @doc """
  Runs the file processor with a specific mode. Needs to be called with a custom output path.

  Modes:
  - "parallel"   -> parallel processing
  - "sequential" -> sequential processing
  """
  # Backwards-compatible arity that uses default parallel options
  def run(input, out_path, mode)
      when mode in ["parallel", "sequential"] and is_bitstring(out_path) and
             (is_bitstring(input) or is_list(input)),
      do: run(input, out_path, mode, [])

  def run(_input, _out_path, _mode), do: run(0, 0, 0, 0)

  @doc """
  Runs the file processor with mode and parallel options.

  Parallel options (only applied when mode == "parallel"):
  - :max_workers (integer | :infinity) -> maximum number of concurrent workers
  - :timeout_ms (positive_integer | :infinity) -> per-worker timeout in milliseconds
  - :retries (non_neg_integer) -> automatic retries per file on failure

  Notes:
  - Defaults options are:
    - max_workers: :infinity (effectively one worker per file)
    - timeout_ms: :infinity (no timeout)
    - retries: 0 (no retries)

  Error logging option:
  - :error_log_path (binary | nil | :none) -> path for a detailed error log file
  """
  # Core execution function
  def run(input, out_path, mode, opts) when is_list(opts) do
    # Detect directory only if input is a directory path
    directory =
      if is_binary(input) and File.dir?(input) do
        input
      else
        nil
      end

    # Resolve the error log path (nil disables logging)
    error_log_path = resolve_error_log_path(out_path, opts)

    # Build report_data using the selected pipeline
    case mode do
      "parallel" ->
        # Parallel mode: only discover paths in the parent, do file reads inside workers
        {:ok, discover_result} = discover_only(input)

        # If no valid supported paths were discovered, return collected errors
        if discover_result.paths == [] do
          log_errors(error_log_path, discover_result.errors, mode)
          {:error, discover_result.errors}
        else
          {report_data, read_ok_count, raw_errors} =
            build_report_data_parallel(discover_result, directory, mode, opts, error_log_path)

          # Match sequential semantics: if nothing was readable, do not write a report
          if read_ok_count == 0 do
            log_errors(error_log_path, raw_errors, mode)
            {:error, raw_errors}
          else
            # If nothing was successfully processed (status :ok), do not write a report
            if report_data.counts.ok == 0 do
              log_errors(error_log_path, report_data.errors, mode)
              {:error, no_successful_files_error(report_data)}
            else
              # Persist only the consolidated report errors (discovery/read/parse/timeout/crash)
              log_errors(error_log_path, report_data.errors, mode)
              write_report(out_path, report_data)
            end
          end
        end

      "sequential" ->
        # Sequential mode: read in parent, process one-by-one
        {:ok, read_result} = read(input)

        # If no readable files were found, return collected errors
        if read_result.files == [] do
          log_errors(error_log_path, read_result.errors, mode)
          {:error, read_result.errors}
        else
          report_data = build_report_data(read_result, directory, mode)

          # If nothing was successfully processed (status :ok), do not write a report
          if report_data.counts.ok == 0 do
            log_errors(error_log_path, report_data.errors, mode)
            {:error, no_successful_files_error(report_data)}
          else
            log_errors(error_log_path, report_data.errors, mode)
            write_report(out_path, report_data)
          end
        end

      invalid_mode ->
        # Invalid mode: return a normalized error
        errors = [
          %{
            path: "mode",
            reason: :invalid_mode,
            details:
              "Unsupported mode: #{inspect(invalid_mode)}. Try allowed modes: \"parallel\", \"sequential\"."
          }
        ]

        log_errors(error_log_path, errors, "invalid_mode")
        {:error, errors}
    end
  end

  # Argument errors
  def run(_input, _out_path, _mode, _opts) do
    {:error,
     [
       %{
         path: "",
         reason: :argument_malformed,
         details:
           "The given arguments are incorrect, the arguments must be: 1. a directory/file string path, 2. an output file string path, 3. a mode string indicator (parallel or sequential), and 4. a list of options (:max_workers, :timeout_ms and :retries)"
       }
     ]}
  end

  defp build_report_data(read_result, directory, mode) do
    # Capture start time
    start_us = System.monotonic_time(:microsecond)

    # Process files one-by-one and accumulate per-type results and parse errors
    {csv_files, json_files, log_files, parse_errors} =
      Enum.reduce(read_result.files, {[], [], [], []}, fn file,
                                                          {csv_acc, json_acc, log_acc, err_acc} ->
        # Branch based on extension
        case file.ext do
          ".csv" ->
            {item, errs} = process_csv(file)
            partial_errs = partial_errors_from_item(item)
            {[item | csv_acc], json_acc, log_acc, err_acc ++ errs ++ partial_errs}

          ".json" ->
            {item, errs} = process_json(file)
            partial_errs = partial_errors_from_item(item)
            {csv_acc, [item | json_acc], log_acc, err_acc ++ errs ++ partial_errs}

          ".log" ->
            {item, errs} = process_log(file)
            partial_errs = partial_errors_from_item(item)
            {csv_acc, json_acc, [item | log_acc], err_acc ++ errs ++ partial_errs}
        end
      end)

    # Reverse to preserve original processing order
    csv_files = Enum.reverse(csv_files)
    json_files = Enum.reverse(json_files)
    log_files = Enum.reverse(log_files)

    # Compute elapsed time in seconds
    elapsed_us = System.monotonic_time(:microsecond) - start_us
    elapsed_seconds = elapsed_us / 1_000_000.0

    counts = %{
      csv: length(csv_files),
      json: length(json_files),
      log: length(log_files)
    }

    # Total discovered paths
    total_count = read_result.discovered

    # Count ok items based on status
    ok_count =
      Enum.count(csv_files, &(&1.status == :ok)) +
        Enum.count(json_files, &(&1.status == :ok)) +
        Enum.count(log_files, &(&1.status == :ok))

    failed_count = total_count - ok_count

    # Convert read/discovery errors into report-friendly errors.
    receiver_and_read_errors = Enum.map(read_result.errors, &normalize_read_error/1)

    # Build the full report_data map
    %{
      directory: directory,
      mode: mode,
      elapsed_seconds: elapsed_seconds,
      counts: %{
        total: total_count,
        ok: ok_count,
        failed: failed_count,
        csv: counts.csv,
        json: counts.json,
        log: counts.log
      },
      csv_files: csv_files,
      json_files: json_files,
      log_files: log_files,
      csv_totals: consolidate_csv(csv_files),
      json_totals: consolidate_json(json_files),
      log_totals: consolidate_log(log_files),
      errors: receiver_and_read_errors ++ parse_errors
    }
  end

  defp build_report_data_parallel(read_result, directory, mode, opts, error_log_path) do
    # Capture start time
    start_us = System.monotonic_time(:microsecond)

    # Store parent pid so workers can send results
    parent = self()

    total_jobs = length(read_result.paths)

    # Resolve parallel options while preserving previous defaults
    {max_workers, timeout_ms, retries} = normalize_parallel_opts(opts, total_jobs)

    # Prepare a job queue with stable ordering and retry budget per file
    job_queue =
      read_result.paths
      |> Enum.with_index()
      |> Enum.map(fn {path, idx} ->
        %{
          idx: idx,
          path: path,
          ext: Path.extname(path),
          bytes: 0,
          retries_left: retries
        }
      end)

    # Start the initial pool of workers
    {queue_after_start, pid_map} =
      start_parallel_workers(job_queue, %{}, parent, max_workers, timeout_ms)

    # Collect results while scheduling new workers up to max_workers
    {csv_pairs, json_pairs, log_pairs, global_errors, read_ok_count, read_errors_raw} =
      collect_parallel_results(
        queue_after_start,
        pid_map,
        parent,
        max_workers,
        timeout_ms,
        error_log_path,
        mode,
        total_jobs,
        0,
        [],
        [],
        [],
        [],
        0,
        []
      )

    # Sort by original index
    csv_files = csv_pairs |> Enum.sort_by(fn {idx, _item} -> idx end) |> Enum.map(&elem(&1, 1))
    json_files = json_pairs |> Enum.sort_by(fn {idx, _item} -> idx end) |> Enum.map(&elem(&1, 1))
    log_files = log_pairs |> Enum.sort_by(fn {idx, _item} -> idx end) |> Enum.map(&elem(&1, 1))

    # Compute elapsed time in seconds
    elapsed_us = System.monotonic_time(:microsecond) - start_us
    elapsed_seconds = elapsed_us / 1_000_000.0

    counts = %{
      csv: length(csv_files),
      json: length(json_files),
      log: length(log_files)
    }

    total_count = read_result.discovered

    ok_count =
      Enum.count(csv_files, &(&1.status == :ok)) +
        Enum.count(json_files, &(&1.status == :ok)) +
        Enum.count(log_files, &(&1.status == :ok))

    failed_count = total_count - ok_count

    # Convert discovery errors into report-friendly errors
    discovery_errors_norm = Enum.map(read_result.errors, &normalize_read_error/1)

    # Convert worker read failures into report-friendly errors
    worker_read_errors_norm = Enum.map(read_errors_raw, &normalize_read_error/1)

    # Build the full report_data map
    report_data = %{
      directory: directory,
      mode: mode,
      elapsed_seconds: elapsed_seconds,
      counts: %{
        total: total_count,
        ok: ok_count,
        failed: failed_count,
        csv: counts.csv,
        json: counts.json,
        log: counts.log
      },
      csv_files: csv_files,
      json_files: json_files,
      log_files: log_files,
      csv_totals: consolidate_csv(csv_files),
      json_totals: consolidate_json(json_files),
      log_totals: consolidate_log(log_files),
      errors: discovery_errors_norm ++ worker_read_errors_norm ++ global_errors
    }

    # Return report_data plus read stats for run/4 to decide whether to write the report
    {report_data, read_ok_count, read_result.errors ++ read_errors_raw}
  end

  #
  # ------------------------------------------------------ MAIN PROCESS SECTION (BENCHMARK) ------------------------------------------------------
  # This section contains benchmark function and its implementations to catch errors and parameters.
  #
  @doc """
  Benchmark function.

  It runs both pipelines independently:
  - sequential run
  - parallel run

  Then prints a comparison to the console.
  """
  def benchmark(input), do: benchmark(input, [])

  def benchmark(input, options) when is_list(options) do
    # Output file for sequential benchmark run
    sequential_out = "benchmark_sequential.txt"

    # Output file for parallel benchmark run
    parallel_out = "benchmark_parallel.txt"

    # Silence stdout
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    # Measure sequential runtime in microseconds
    {seq_us, seq_result} =
      :timer.tc(fn ->
        run(input, sequential_out, "sequential")
      end)

    # Measure parallel runtime in microseconds
    {par_us, par_result} =
      :timer.tc(fn ->
        run(input, parallel_out, "parallel", options)
      end)

    # Convert microseconds to seconds
    seq_s = seq_us / 1_000_000.0
    par_s = par_us / 1_000_000.0

    # Compute speedup factor
    speedup =
      if par_s > 0.0 do
        seq_s / par_s
      else
        0.0
      end

    # Restore stdout
    Process.group_leader(self(), original)
    File.close(devnull)

    # Delete benchmark reports and logs
    case File.rm("benchmark_parallel.txt") do
      :ok -> :ok
      {:error, reason} -> IO.puts("Could not delete benchmark_parallel.txt: #{inspect(reason)}")
    end

    case File.rm("benchmark_sequential.txt") do
      :ok -> :ok
      {:error, reason} -> IO.puts("Could not delete benchmark_sequential.txt: #{inspect(reason)}")
    end

    case File.rm("logs/benchmark_parallel_errors.log") do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts("Could not delete logs/benchmark_parallel_errors.log: #{inspect(reason)}")
    end

    case File.rm("logs/benchmark_sequential_errors.log") do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts("Could not delete logs/benchmark_sequential_errors.log: #{inspect(reason)}")
    end

    # Print comparison block to the console
    IO.puts("""
    BENCHMARK RESULTS
    Sequential:
      - Time (s): #{Float.round(seq_s, 6)}
      - Result: #{format_benchmark_result(seq_result)}

    Parallel:
      - Time (s): #{Float.round(par_s, 6)}
      - Result: #{format_benchmark_result(par_result)}

    Speedup: #{Float.round(speedup, 3)}x
    """)
  end

  # Special function to catch bad arguments given to the benchmark functions
  def benchmark(_input, _options) do
    {:error,
     [
       %{
         path: "",
         reason: :argument_malformed,
         details:
           "The given arguments are incorrect, the arguments must be: A directory/file string path and a list of options (:max_workers, :timeout_ms and :retries)"
       }
     ]}
  end

  # Formats run results for benchmark printing
  defp format_benchmark_result({:ok, _path}), do: "OK"
  defp format_benchmark_result({:error, errors}), do: "error (#{length(errors)} issues)"
  defp format_benchmark_result(other), do: inspect(other)
  #
  # ------------------------------------------------------ SEQUENTIAL/PARALLEL FUNCTIONS ------------------------------------------------------
  # In this section we define the functions write_report, discover_files and read that are used by both modes to don´t need to repeat code.
  #

  # Writes a report using the shared ReportGenerator and returns the absolute path
  defp write_report(out_path, report_data) do
    # Build the report content (same generator used by both modes)
    content = API.FileProcessor.ReportGenerator.build(report_data)

    # Write the report to disk and return its absolute path
    final_path = API.FileProcessor.ReportGenerator.write!(out_path, content)

    # Success tuple with report path
    {:ok, final_path, report_data}
  end

  # Discovers files delegating the process to FileReceiver files
  @spec discover_files(String.t() | [String.t()]) ::
          {:ok, [String.t()], [map()]}
  defp discover_files(inputs) do
    # Delegate discovery and validation to FileReceiver
    API.FileProcessor.FileReceiver.obtain(inputs)
  end

  # Discovers supported file paths and aggregates discovery errors without reading contents
  @spec discover_only(String.t() | [String.t()]) ::
          {:ok, %{paths: [String.t()], errors: [read_error()], discovered: non_neg_integer()}}
  defp discover_only(inputs) do
    {:ok, paths, discovery_errors} = discover_files(inputs)

    # Normalize discovery errors into the same shape used by read/1
    all_errors =
      discovery_errors
      |> Enum.map(fn e -> %{path: e.input, reason: e.reason, details: e.details} end)

    {:ok, %{paths: paths, errors: all_errors, discovered: length(paths)}}
  end

  # Reads file contents and aggregates errors
  @spec read(String.t() | [String.t()]) ::
          {:ok, %{files: [read_result()], errors: [read_error()], discovered: non_neg_integer()}}
  defp read(inputs) do
    {:ok, paths, discovery_errors} = discover_files(inputs)

    # Read each discovered path and split between ok and error results
    {ok_results, read_errors} =
      paths
      |> Enum.map(&read_one/1)
      |> Enum.split_with(fn
        # Keep successful reads on the left
        {:ok, _} -> true
        # Keep failed reads on the right
        {:error, _} -> false
      end)

    # Extract only the read_result maps from ok tuples
    files = Enum.map(ok_results, fn {:ok, result} -> result end)

    # Extract only the error maps from error tuples
    errors = Enum.map(read_errors, fn {:error, err} -> err end)

    # Merge discovery errors into the same shape as read errors
    all_errors =
      discovery_errors
      |> Enum.map(fn e -> %{path: e.input, reason: e.reason, details: e.details} end)
      |> Kernel.++(errors)

    {:ok, %{files: files, errors: all_errors, discovered: length(paths)}}
  end

  # Reads a single file, used by sequential mode with one single file and parallel mode with every process.
  defp read_one(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok,
         %{
           path: path,
           ext: Path.extname(path),
           bytes: byte_size(content),
           content: content
         }}

      {:error, reason} ->
        # Convert file read error into a error object
        {:error, %{path: path, reason: :read_failed, details: reason}}
    end
  end

  #
  # ------------------------------------------------------ WORKERS FUNCTIONS ------------------------------------------------------
  # In this section we define the functions where workers are started and managed.
  #

  # Starts as many workers as possible up to max_workers and returns the remaining queue and pid map
  defp start_parallel_workers(queue, pid_map, parent, max_workers, timeout_ms) do
    capacity = max_workers - map_size(pid_map)

    cond do
      capacity <= 0 ->
        {queue, pid_map}

      queue == [] ->
        {queue, pid_map}

      true ->
        {to_start, rest} = Enum.split(queue, capacity)

        pid_map2 =
          Enum.reduce(to_start, pid_map, fn job, acc ->
            {pid, monitor_ref, timer_ref} = spawn_worker_for_job(job, parent, timeout_ms)

            meta = %{
              pid: pid,
              monitor_ref: monitor_ref,
              timer_ref: timer_ref,
              idx: job.idx,
              path: job.path,
              ext: job.ext,
              bytes: job.bytes,
              retries_left: job.retries_left,
              job: job
            }

            Map.put(acc, pid, meta)
          end)

        {rest, pid_map2}
    end
  end

  # Spawns a worker for a given job and schedules a timeout message
  defp spawn_worker_for_job(job, parent, timeout_ms) do
    pid =
      spawn(fn ->
        # Read inside the worker using the existing read_one/1 helper
        case read_one(job.path) do
          {:ok, file} ->
            # Process the file using existing parsing/metrics logic
            result =
              case file.ext do
                ".csv" ->
                  {item, errs} = process_csv(file)
                  {:ok, :csv, item, errs}

                ".json" ->
                  {item, errs} = process_json(file)
                  {:ok, :json, item, errs}

                ".log" ->
                  {item, errs} = process_log(file)
                  {:ok, :log, item, errs}
              end

            # Send back the result using pid for identification and idx for stable ordering
            send(parent, {:worker_result, self(), job.idx, file.path, result})

          {:error, err} ->
            # Send back a read failure in the same raw error shape used by read/1
            send(parent, {:worker_read_error, self(), job.idx, job.path, err})
        end
      end)

    # Detect crashes
    monitor_ref = Process.monitor(pid)

    # Optional per-worker timeout
    timer_ref =
      case timeout_ms do
        :infinity ->
          nil

        ms when is_integer(ms) and ms > 0 ->
          Process.send_after(parent, {:worker_timeout, pid}, ms)
      end

    {pid, monitor_ref, timer_ref}
  end

  # Cancels timeout timer and removes monitor to avoid duplicate :DOWN handling
  defp cleanup_worker(meta) do
    if is_reference(meta.timer_ref) do
      Process.cancel_timer(meta.timer_ref)
    end

    Process.demonitor(meta.monitor_ref, [:flush])
    :ok
  end

  # Collect results from workers while enforcing max_workers, timeout and retries
  defp collect_parallel_results(
         queue,
         pid_map,
         _parent,
         _max_workers,
         _timeout_ms,
         _error_log_path,
         _mode,
         _total,
         _done,
         csv_acc,
         json_acc,
         log_acc,
         err_acc,
         read_ok_count,
         read_err_acc
       )
       when queue == [] and map_size(pid_map) == 0 do
    # When all jobs are done, return accumulated results
    {Enum.reverse(csv_acc), Enum.reverse(json_acc), Enum.reverse(log_acc), Enum.reverse(err_acc),
     read_ok_count, Enum.reverse(read_err_acc)}
  end

  # Loop function to collect results from workers
  defp collect_parallel_results(
         queue,
         pid_map,
         parent,
         max_workers,
         timeout_ms,
         error_log_path,
         mode,
         total,
         done,
         csv_acc,
         json_acc,
         log_acc,
         err_acc,
         read_ok_count,
         read_err_acc
       ) do
    receive do
      # Worker sent its successful processing result (read ok)
      {:worker_result, pid, idx, path, {:ok, type, item, parse_errs}} ->
        case Map.fetch(pid_map, pid) do
          :error ->
            # Pid already consumed; keep waiting for other results
            collect_parallel_results(
              queue,
              pid_map,
              parent,
              max_workers,
              timeout_ms,
              error_log_path,
              mode,
              total,
              done,
              csv_acc,
              json_acc,
              log_acc,
              err_acc,
              read_ok_count,
              read_err_acc
            )

          {:ok, meta} ->
            cleanup_worker(meta)

            new_done = done + 1
            new_read_ok_count = read_ok_count + 1

            print_parallel_progress(new_done, total, path, item.status)

            {csv_acc2, json_acc2, log_acc2} =
              case type do
                :csv -> {[{idx, item} | csv_acc], json_acc, log_acc}
                :json -> {csv_acc, [{idx, item} | json_acc], log_acc}
                :log -> {csv_acc, json_acc, [{idx, item} | log_acc]}
              end

            # Accumulate parse errors
            err_acc2 = Enum.reduce(parse_errs, err_acc, fn e, a -> [e | a] end)

            # Include partial per-file errors in the global error list (report + log)
            err_acc3 =
              item
              |> partial_errors_from_item()
              |> Enum.reduce(err_acc2, fn e, a -> [e | a] end)

            # Remove the pid
            pid_map2 = Map.delete(pid_map, pid)

            # Schedule more workers if capacity is available
            {queue2, pid_map3} =
              start_parallel_workers(queue, pid_map2, parent, max_workers, timeout_ms)

            collect_parallel_results(
              queue2,
              pid_map3,
              parent,
              max_workers,
              timeout_ms,
              error_log_path,
              mode,
              total,
              new_done,
              csv_acc2,
              json_acc2,
              log_acc2,
              err_acc3,
              new_read_ok_count,
              read_err_acc
            )
        end

      # Worker sent a read failure (read failed before parsing)
      {:worker_read_error, pid, _idx, _path,
       %{path: _p, reason: :read_failed, details: details} = err} ->
        case Map.fetch(pid_map, pid) do
          :error ->
            collect_parallel_results(
              queue,
              pid_map,
              parent,
              max_workers,
              timeout_ms,
              error_log_path,
              mode,
              total,
              done,
              csv_acc,
              json_acc,
              log_acc,
              err_acc,
              read_ok_count,
              read_err_acc
            )

          {:ok, meta} ->
            cleanup_worker(meta)
            pid_map2 = Map.delete(pid_map, pid)

            # Retry logic: re-enqueue the job if budget remains
            if meta.retries_left > 0 do
              log_event(error_log_path, mode, meta.path, :retry_started, %{
                cause: :read_failed,
                details: details,
                retries_left_before: meta.retries_left,
                retries_left_after: meta.retries_left - 1
              })

              job2 = %{meta.job | retries_left: meta.retries_left - 1}
              queue2 = queue ++ [job2]

              {queue3, pid_map3} =
                start_parallel_workers(queue2, pid_map2, parent, max_workers, timeout_ms)

              collect_parallel_results(
                queue3,
                pid_map3,
                parent,
                max_workers,
                timeout_ms,
                error_log_path,
                mode,
                total,
                done,
                csv_acc,
                json_acc,
                log_acc,
                err_acc,
                read_ok_count,
                read_err_acc
              )
            else
              new_done = done + 1
              print_parallel_progress(new_done, total, meta.path, :failed)

              # Build a failed item structure consistent with the report format
              {type, failed_item} =
                failed_item_from_meta(meta, "read_failed: #{inspect(details)}")

              # Accumulate into the correct type list
              {csv_acc2, json_acc2, log_acc2} =
                case type do
                  :csv -> {[{meta.idx, failed_item} | csv_acc], json_acc, log_acc}
                  :json -> {csv_acc, [{meta.idx, failed_item} | json_acc], log_acc}
                  :log -> {csv_acc, json_acc, [{meta.idx, failed_item} | log_acc]}
                end

              # Keep raw read errors so run/4 can return {:error, errors} if nothing was readable
              read_err_acc2 = [err | read_err_acc]

              {queue2, pid_map3} =
                start_parallel_workers(queue, pid_map2, parent, max_workers, timeout_ms)

              collect_parallel_results(
                queue2,
                pid_map3,
                parent,
                max_workers,
                timeout_ms,
                error_log_path,
                mode,
                total,
                new_done,
                csv_acc2,
                json_acc2,
                log_acc2,
                err_acc,
                read_ok_count,
                read_err_acc2
              )
            end
        end

      # Per-worker timeout fired
      {:worker_timeout, pid} ->
        case Map.fetch(pid_map, pid) do
          :error ->
            collect_parallel_results(
              queue,
              pid_map,
              parent,
              max_workers,
              timeout_ms,
              error_log_path,
              mode,
              total,
              done,
              csv_acc,
              json_acc,
              log_acc,
              err_acc,
              read_ok_count,
              read_err_acc
            )

          {:ok, meta} ->
            cleanup_worker(meta)

            # Log that the timeout was reached (even if a retry will happen)
            log_event(error_log_path, mode, meta.path, :timeout_fired, %{
              timeout_ms: timeout_ms,
              pid: pid,
              retries_left: meta.retries_left
            })

            # Kill the worker to enforce the timeout
            Process.exit(pid, :kill)

            pid_map2 = Map.delete(pid_map, pid)

            # Retry logic: re-enqueue the job if budget remains
            if meta.retries_left > 0 do
              log_event(error_log_path, mode, meta.path, :retry_started, %{
                cause: :timeout,
                timeout_ms: timeout_ms,
                retries_left_before: meta.retries_left,
                retries_left_after: meta.retries_left - 1
              })

              job2 = %{meta.job | retries_left: meta.retries_left - 1}
              queue2 = queue ++ [job2]

              {queue3, pid_map3} =
                start_parallel_workers(queue2, pid_map2, parent, max_workers, timeout_ms)

              collect_parallel_results(
                queue3,
                pid_map3,
                parent,
                max_workers,
                timeout_ms,
                error_log_path,
                mode,
                total,
                done,
                csv_acc,
                json_acc,
                log_acc,
                err_acc,
                read_ok_count,
                read_err_acc
              )
            else
              new_done = done + 1

              print_parallel_progress(new_done, total, meta.path, :failed)

              # Build a failed item structure consistent with the report format
              {type, failed_item} =
                failed_item_from_meta(meta, "timeout: #{inspect(timeout_ms)}")

              timeout_error = %{path: meta.path, error: "timeout: #{inspect(timeout_ms)}"}
              raw_timeout_error = %{path: meta.path, reason: :timeout, details: timeout_ms}

              # Accumulate into the correct type list
              {csv_acc2, json_acc2, log_acc2} =
                case type do
                  :csv -> {[{meta.idx, failed_item} | csv_acc], json_acc, log_acc}
                  :json -> {csv_acc, [{meta.idx, failed_item} | json_acc], log_acc}
                  :log -> {csv_acc, json_acc, [{meta.idx, failed_item} | log_acc]}
                end

              read_err_acc2 = [raw_timeout_error | read_err_acc]

              {queue2, pid_map3} =
                start_parallel_workers(queue, pid_map2, parent, max_workers, timeout_ms)

              collect_parallel_results(
                queue2,
                pid_map3,
                parent,
                max_workers,
                timeout_ms,
                error_log_path,
                mode,
                total,
                new_done,
                csv_acc2,
                json_acc2,
                log_acc2,
                [timeout_error | err_acc],
                read_ok_count,
                read_err_acc2
              )
            end
        end

      # Normal DOWN messages arrive after successful completion; ignore them to prevent duplicates
      {:DOWN, _ref, :process, _pid, :normal} ->
        collect_parallel_results(
          queue,
          pid_map,
          parent,
          max_workers,
          timeout_ms,
          error_log_path,
          mode,
          total,
          done,
          csv_acc,
          json_acc,
          log_acc,
          err_acc,
          read_ok_count,
          read_err_acc
        )

      # Abnormal DOWN: worker crashed before producing a valid result
      {:DOWN, _ref, :process, pid, reason} ->
        case Map.fetch(pid_map, pid) do
          :error ->
            # Pid already consumed; ignore
            collect_parallel_results(
              queue,
              pid_map,
              parent,
              max_workers,
              timeout_ms,
              error_log_path,
              mode,
              total,
              done,
              csv_acc,
              json_acc,
              log_acc,
              err_acc,
              read_ok_count,
              read_err_acc
            )

          {:ok, meta} ->
            cleanup_worker(meta)
            pid_map2 = Map.delete(pid_map, pid)

            # Retry logic: re-enqueue the job if budget remains
            if meta.retries_left > 0 do
              log_event(error_log_path, mode, meta.path, :retry_started, %{
                cause: :worker_crashed,
                crash_reason: reason,
                retries_left_before: meta.retries_left,
                retries_left_after: meta.retries_left - 1
              })

              job2 = %{meta.job | retries_left: meta.retries_left - 1}
              queue2 = queue ++ [job2]

              {queue3, pid_map3} =
                start_parallel_workers(queue2, pid_map2, parent, max_workers, timeout_ms)

              collect_parallel_results(
                queue3,
                pid_map3,
                parent,
                max_workers,
                timeout_ms,
                error_log_path,
                mode,
                total,
                done,
                csv_acc,
                json_acc,
                log_acc,
                err_acc,
                read_ok_count,
                read_err_acc
              )
            else
              new_done = done + 1

              # Print progress line for crash
              print_parallel_progress(new_done, total, meta.path, :failed)

              # Build a failed item structure consistent with the report format
              {type, failed_item} =
                failed_item_from_meta(meta, "worker_crashed: #{inspect(reason)}")

              # Add an error line in report (printable format)
              crash_error = %{path: meta.path, error: "worker_crashed: #{inspect(reason)}"}

              raw_crash_error = %{path: meta.path, reason: :worker_crashed, details: reason}

              # Accumulate into the correct type list
              {csv_acc2, json_acc2, log_acc2} =
                case type do
                  :csv -> {[{meta.idx, failed_item} | csv_acc], json_acc, log_acc}
                  :json -> {csv_acc, [{meta.idx, failed_item} | json_acc], log_acc}
                  :log -> {csv_acc, json_acc, [{meta.idx, failed_item} | log_acc]}
                end

              read_err_acc2 = [raw_crash_error | read_err_acc]

              {queue2, pid_map3} =
                start_parallel_workers(queue, pid_map2, parent, max_workers, timeout_ms)

              collect_parallel_results(
                queue2,
                pid_map3,
                parent,
                max_workers,
                timeout_ms,
                error_log_path,
                mode,
                total,
                new_done,
                csv_acc2,
                json_acc2,
                log_acc2,
                [crash_error | err_acc],
                read_ok_count,
                read_err_acc2
              )
            end
        end
    end
  end

  #
  # ------------------------------------------------------ ERRORS/LOGS FUNCTIONS ------------------------------------------------------
  # In this section we define the functions that give format to errors for the reports
  #
  defp no_successful_files_error(report_data) do
    [
      %{
        path: "run",
        reason: :no_successful_files,
        details:
          "All files have errors or didn't reach status :ok (total=#{report_data.counts.total}, ok=#{report_data.counts.ok}). Please check the logs for more details."
      }
    ]
  end

  # Converts internal read errors into printable report errors
  defp normalize_read_error(%{path: path, reason: reason, details: details}) do
    %{path: path, error: "#{reason}: #{inspect(details)}"}
  end

  # Normalizes per-file partial errors (row/line errors) into report/log errors.
  defp partial_errors_from_item(%{status: :partial, path: path, errors: errs})
       when is_binary(path) and is_list(errs) do
    Enum.map(errs, fn e ->
      line = Map.get(e, :line)
      msg = Map.get(e, :error, inspect(e))

      text =
        cond do
          is_integer(line) -> "partial: line #{line}: #{msg}"
          true -> "partial: #{msg}"
        end

      %{path: path, error: text}
    end)
  end

  defp partial_errors_from_item(_), do: []

  # Logs a structured event line into the error log file (if enabled).
  defp log_event(error_log_path, mode, path, reason, details) do
    log_errors(error_log_path, [%{path: path, reason: reason, details: details}], mode)
  end

  # Builds a report-compatible "failed file item" when a worker crashes or a file is unsupported
  defp failed_item_from_meta(meta, message) do
    type =
      case meta.ext do
        ".csv" -> :csv
        ".json" -> :json
        ".log" -> :log
        _ -> :log
      end

    item =
      case type do
        :csv ->
          %{
            path: meta.path,
            bytes: meta.bytes,
            status: :failed,
            metrics: empty_csv_metrics(),
            products_set: MapSet.new(),
            errors: [%{line: 1, error: message}]
          }

        :json ->
          %{
            path: meta.path,
            bytes: meta.bytes,
            status: :failed,
            metrics: empty_json_metrics(),
            errors: [%{line: 1, error: message}]
          }

        :log ->
          %{
            path: meta.path,
            bytes: meta.bytes,
            status: :failed,
            metrics: empty_log_metrics(),
            errors: [%{line: 1, error: message}]
          }
      end

    {type, item}
  end

  # Resolves the error log path from options; nil disables logging
  defp resolve_error_log_path(out_path, opts) do
    case Keyword.get(opts, :error_log_path, :default) do
      :default -> default_error_log_path(out_path)
      :none -> nil
      nil -> nil
      path when is_binary(path) -> path
      _ -> default_error_log_path(out_path)
    end
  end

  # Derives a stable default log file name from the report output path
  defp default_error_log_path(out_path) do
    # Creates a single directory (fails if parent dirs don't exist)
    case File.mkdir("logs") do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, reason} -> {:error, reason}
    end

    filename = Path.basename(out_path)
    Path.rootname("logs/#{filename}") <> "_errors.log"
  end

  # Writes errors to a log file, appending lines and creating the file lazily
  defp log_errors(nil, _errors, _mode), do: :ok
  defp log_errors(_path, [], _mode), do: :ok

  defp log_errors(path, errors, _mode) when is_binary(path) and is_list(errors) do
    File.write!(
      path,
      "--------------------------------------------------------------------------------\nExecution started at #{utc_timestamp()}\n--------------------------------------------------------------------------------\n",
      [:append]
    )

    Enum.each(errors, fn e ->
      File.write!(path, format_log_line(e), [:append])
    end)

    File.write!(
      path,
      "--------------------------------------------------------------------------------\nExecution finished at #{utc_timestamp()}\n--------------------------------------------------------------------------------\n",
      [:append]
    )

    :ok
  end

  #
  # ------------------------------------------------------ CSV FUNCTIONS ------------------------------------------------------
  # This section contains only functions related to CSV processing
  #
  # Uses CSVParser to process CSV files
  defp process_csv(file) do
    case API.FileProcessor.Parsers.CSVParser.parse(file.content) do
      {:ok, %{rows: rows, errors: row_errors}} ->
        metrics = API.FileProcessor.Metrics.CSVMetrics.compute(rows)

        products_set =
          rows
          |> Enum.map(& &1.product)
          |> MapSet.new()

        status =
          cond do
            length(rows) == 0 and length(row_errors) > 0 -> :failed
            length(row_errors) > 0 -> :partial
            true -> :ok
          end

        {%{
           path: file.path,
           bytes: file.bytes,
           status: status,
           metrics: metrics,
           products_set: products_set,
           errors: row_errors
         }, []}

      {:error, reason} ->
        {%{
           path: file.path,
           bytes: file.bytes,
           status: :failed,
           metrics: empty_csv_metrics(),
           products_set: MapSet.new(),
           errors: []
         }, [%{path: file.path, error: reason}]}
    end
  end

  # Calculates total sales and unique products from a list of CSV files.
  # Only status == :ok files are included to avoid partial/failed data.
  defp consolidate_csv(files) do
    ok_files = Enum.filter(files, &(&1.status == :ok))

    total_sales =
      Enum.reduce(ok_files, 0.0, fn f, acc ->
        acc + f.metrics.total_sales
      end)

    products_union =
      Enum.reduce(ok_files, MapSet.new(), fn f, acc ->
        cond do
          match?(%MapSet{}, Map.get(f, :products_set)) ->
            MapSet.union(acc, f.products_set)

          match?(%MapSet{}, Map.get(f.metrics, :products)) ->
            MapSet.union(acc, f.metrics.products)

          true ->
            acc
        end
      end)

    %{
      total_sales: total_sales,
      unique_products: MapSet.size(products_union)
    }
  end

  # Assigns default values for CSV metrics in case of an error
  defp empty_csv_metrics do
    %{
      total_sales: 0.0,
      unique_products: 0,
      top_product: nil,
      top_category: nil,
      avg_discount_pct: 0.0,
      date_range: {nil, nil}
    }
  end

  # ------------------------------------------------------ JSON FUNCTIONS ------------------------------------------------------
  # This section contains only functions related to JSON processing
  #
  # Uses JSONParser to process JSON files
  defp process_json(file) do
    case API.FileProcessor.Parsers.JSONParser.parse(file.content) do
      {:ok, json} ->
        metrics = API.FileProcessor.Metrics.JSONMetrics.compute(json)
        {%{path: file.path, bytes: file.bytes, status: :ok, metrics: metrics, errors: []}, []}

      {:error, reason} ->
        {%{
           path: file.path,
           bytes: file.bytes,
           status: :failed,
           metrics: empty_json_metrics(),
           errors: []
         }, [%{path: file.path, error: reason}]}
    end
  end

  # Sums total, active and inactive users.
  # Only status == :ok files are included to avoid partial/failed data.
  defp consolidate_json(files) do
    ok_files = Enum.filter(files, &(&1.status == :ok))

    Enum.reduce(ok_files, %{total_users: 0, active_users: 0, inactive_users: 0}, fn f, acc ->
      %{
        total_users: acc.total_users + f.metrics.total_users,
        active_users: acc.active_users + f.metrics.active_users,
        inactive_users: acc.inactive_users + f.metrics.inactive_users
      }
    end)
  end

  # Assigns default values for JSON metrics in case of an error
  defp empty_json_metrics do
    %{
      total_users: 0,
      active_users: 0,
      inactive_users: 0,
      avg_session_seconds: 0.0,
      total_pages: 0,
      top_actions: [],
      peak_hour: nil
    }
  end

  # ------------------------------------------------------ LOG FUNCTIONS ------------------------------------------------------
  # This section contains only functions related to log processing
  #

  # Uses LogParser to process log files
  defp process_log(file) do
    case API.FileProcessor.Parsers.LogParser.parse(file.content) do
      {:ok, %{entries: entries, errors: parse_errors}} ->
        metrics = API.FileProcessor.Metrics.LogMetrics.compute(entries)

        status =
          cond do
            length(entries) == 0 and length(parse_errors) > 0 -> :failed
            length(parse_errors) > 0 -> :partial
            true -> :ok
          end

        {%{
           path: file.path,
           bytes: file.bytes,
           status: status,
           metrics: metrics,
           errors: parse_errors
         }, []}

      {:error, reason} ->
        {%{
           path: file.path,
           bytes: file.bytes,
           status: :failed,
           metrics: empty_log_metrics(),
           errors: []
         }, [%{path: file.path, error: reason}]}
    end
  end

  # Sums total entries and fuses maps.
  # Only status == :ok files are included to avoid partial/failed data.
  defp consolidate_log(files) do
    ok_files = Enum.filter(files, &(&1.status == :ok))

    total_entries = Enum.reduce(ok_files, 0, fn f, acc -> acc + f.metrics.total_entries end)

    by_level =
      Enum.reduce(ok_files, %{}, fn f, acc ->
        Enum.reduce(f.metrics.by_level, acc, fn {level, count}, a ->
          Map.update(a, level, count, &(&1 + count))
        end)
      end)

    %{total_entries: total_entries, by_level: by_level}
  end

  # Assigns default values for log metrics in case of an error
  defp empty_log_metrics do
    %{
      total_entries: 0,
      by_level: %{},
      by_hour: %{},
      top_error_messages: [],
      top_error_component: nil,
      critical_error_gaps_seconds: %{count: 0, avg: 0.0, min: nil, max: nil},
      recurrent_error_patterns: []
    }
  end

  # ------------------------------------------------------ HELPERS ------------------------------------------------------
  # This section contains utility functions
  #
  # Formats a consistent timestamp
  defp utc_timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
    |> Kernel.<>("Z")
  end

  # Formats error lines for both shapes used in this project:
  # - %{path, reason, details}
  # - %{path, error}
  defp format_log_line(%{path: path, reason: reason, details: details}) do
    ts = utc_timestamp()
    "[#{ts}] path=#{inspect(path)} reason=#{inspect(reason)} details=#{inspect(details)}\n"
  end

  defp format_log_line(%{path: path, error: error}) do
    ts = utc_timestamp()
    "[#{ts}] path=#{inspect(path)} error=#{inspect(error)}\n"
  end

  defp format_log_line(other) do
    timestamp = utc_timestamp()
    "[#{timestamp}] error=#{inspect(other)}\n"
  end

  # Prints a single progress line for parallel processing
  defp print_parallel_progress(done, total, path, status) do
    filename = Path.basename(path)
    IO.puts("[parallel] #{done}/#{total} processed: #{filename} (#{status})")
  end

  # Resolves parallel execution options with safe defaults that preserve previous behavior
  defp normalize_parallel_opts(opts, total_jobs) do
    max_workers_raw = Keyword.get(opts, :max_workers, :infinity)

    max_workers =
      cond do
        max_workers_raw == :infinity ->
          total_jobs

        is_integer(max_workers_raw) and max_workers_raw > 0 ->
          min(max_workers_raw, total_jobs)

        true ->
          total_jobs
      end

    timeout_raw = Keyword.get(opts, :timeout_ms, :infinity)

    timeout_ms =
      cond do
        timeout_raw == :infinity ->
          :infinity

        is_integer(timeout_raw) and timeout_raw > 0 ->
          timeout_raw

        true ->
          :infinity
      end

    retries_raw = Keyword.get(opts, :retries, 0)

    retries =
      cond do
        is_integer(retries_raw) and retries_raw >= 0 -> retries_raw
        true -> 0
      end

    {max_workers, timeout_ms, retries}
  end
end
