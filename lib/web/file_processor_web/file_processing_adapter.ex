defmodule FileProcessorWeb.FileProcessingAdapter do
  @moduledoc """
  Adapter that connects the Phoenix web application with the file processing system.
  Handles uploaded files (Plug.Upload) and local file paths.
  """

  @doc """
  Processes files uploaded through the web form.

  Accepts:
  - params: Map with processing configuration and file inputs

  Returns:
  - {:ok, result} - with the report path and data for display
  - {:error, reason} - in case of failure
  """
  def process_from_web(params) do
    input_info = get_input_path(params)

    case validate_input(input_info) do
      :ok ->
        {input_path, _filename} = input_info

        mode = determine_mode(params)
        output_path = generate_output_name(params)
        options = build_options_with_log(params, output_path)

        execute_processing(input_path, output_path, mode, options, params)

      {:error, message} ->
        {:error, message}
    end
  end

  # Retrieves the file input path from the parameters
  # Returns {path_or_paths, original_filename} to validate the extension properly
  defp get_input_path(%{"uploaded_files" => files}) when is_list(files) do
    IO.puts("📤 Processing #{length(files)} uploaded file(s)...")

    batch_id = System.system_time(:millisecond)

    permanent_paths =
      files
      |> Enum.map(fn upload ->
        case copy_uploaded_file(upload, batch_id) do
          {:ok, path} -> path
          {:error, _} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    if permanent_paths == [] do
      {nil, nil}
    else
      {permanent_paths, nil}
    end
  end

  # Handles a single uploaded file
  defp get_input_path(%{"uploaded_files" => upload}) when is_map(upload) do
    batch_id = System.system_time(:millisecond)

    case copy_uploaded_file(upload, batch_id) do
      {:ok, permanent_path} ->
        {permanent_path, upload.filename}

      {:error, _reason} ->
        {nil, nil}
    end
  end

  # Handles a local file path provided as a string
  defp get_input_path(%{"file_path" => path}) when is_binary(path) and path != "" do
    {String.trim(path), nil}
  end

  # Fallback for empty or invalid input
  defp get_input_path(_params) do
    {nil, nil}
  end

  # Copies the uploaded file to a permanent location within a batch folder
  defp copy_uploaded_file(%Plug.Upload{path: temp_path, filename: filename}, batch_id) do
    upload_dir = Path.join("priv/static/uploads", to_string(batch_id))
    File.mkdir_p!(upload_dir)

    destination = Path.join(upload_dir, filename)

    case File.cp(temp_path, destination) do
      :ok ->
        IO.puts("File copied: #{filename} -> #{destination}")
        {:ok, destination}

      {:error, reason} ->
        IO.puts("❌ Error copying uploaded file: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Validates that the input is a valid file, directory, or list of files
  defp validate_input({nil, _}) do
    {:error, "You must upload one or more files, or provide a valid path"}
  end

  defp validate_input({paths, _filename}) when is_list(paths) do
    if Enum.all?(paths, &File.regular?/1) do
      :ok
    else
      missing_files = Enum.filter(paths, fn p -> not File.regular?(p) end)
      {:error, "Some files do not exist: #{inspect(missing_files)}"}
    end
  end

  defp validate_input({path, filename}) when is_binary(path) do
    cond do
      not File.exists?(path) ->
        {:error, "The file or directory does not exist: #{path}"}

      File.dir?(path) ->
        case has_supported_files?(path) do
          true -> :ok
          false -> {:error, "The directory does not contain CSV, JSON, or LOG files"}
        end

      File.regular?(path) ->
        ext = if is_binary(filename), do: Path.extname(filename), else: Path.extname(path)

        if ext in [".csv", ".json", ".log"] do
          :ok
        else
          {:error, "Unsupported file format. Use CSV, JSON, or LOG (detected extension: #{ext})"}
        end

      true ->
        {:error, "Invalid path"}
    end
  end

  # Checks if a directory contains supported files
  defp has_supported_files?(dir) do
    Path.wildcard(Path.join([dir, "**", "*"]))
    |> Enum.any?(fn file ->
      File.regular?(file) and Path.extname(file) in [".csv", ".json", ".log"]
    end)
  end

  # Builds processing options from form parameters
  defp build_options(params) do
    options = []

    options =
      case params["max_workers"] do
        "" ->
          options

        nil ->
          options

        value ->
          case parse_number_or_infinity(value) do
            nil -> options
            parsed -> Keyword.put(options, :max_workers, parsed)
          end
      end

    options =
      case params["timeout"] do
        "" ->
          options

        nil ->
          options

        value ->
          case parse_number_or_infinity(value) do
            nil -> options
            parsed -> Keyword.put(options, :timeout_ms, parsed)
          end
      end

    options =
      case params["retry_count"] do
        "" ->
          options

        nil ->
          options

        value ->
          case Integer.parse(value) do
            {num, ""} when num >= 0 -> Keyword.put(options, :retries, num)
            _ -> options
          end
      end

    # Obtains LiveView PID to send progress updates
    options =
      case params["caller_pid"] do
        pid when is_pid(pid) -> Keyword.put(options, :caller_pid, pid)
        _ -> options
      end

    options
  end

  # Builds processing options including error_log_path
  defp build_options_with_log(params, output_path) do
    options = build_options(params)

    File.mkdir_p!("logs")
    base_name = output_path |> Path.basename() |> Path.rootname()
    error_log = "logs/#{base_name}_errors.log"

    Keyword.put(options, :error_log_path, error_log)
  end

  # Parses a number or the word "infinity"
  defp parse_number_or_infinity("infinity"), do: :infinity
  defp parse_number_or_infinity("Infinity"), do: :infinity
  defp parse_number_or_infinity("INFINITY"), do: :infinity

  defp parse_number_or_infinity(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, ""} when num > 0 -> num
      _ -> nil
    end
  end

  # Determines the processing mode
  defp determine_mode(%{"processing_type" => "parallel"}), do: "parallel"
  defp determine_mode(%{"processing_type" => "sequential"}), do: "sequential"
  defp determine_mode(_), do: "parallel"

  # Generates the output file name
  defp generate_output_name(%{"report_name" => name})
       when is_binary(name) and name != "" do
    clean_name =
      name
      |> String.trim()
      |> String.replace(~r/[^\w\s-]/, "")
      |> String.replace(~r/\s+/, "_")

    if String.ends_with?(clean_name, ".txt") do
      "priv/static/reports/#{clean_name}"
    else
      "priv/static/reports/#{clean_name}.txt"
    end
  end

  defp generate_output_name(_params) do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_unix()

    "priv/static/reports/report_#{timestamp}.txt"
  end

  # Executes processing based on the selected mode
  defp execute_processing(input_path, output_path, mode, options, params) do
    File.mkdir_p!("priv/static/reports")

    benchmark_active? = params["benchmark_active"] in ["true", "on"]

    result =
      if benchmark_active? do
        execute_benchmark(input_path, options)
      else
        execute_normal_processing(input_path, output_path, mode, options)
      end

    clean_temp_file(input_path)
    save_to_history(result)
  end

  # Handles cleaning up temporal files from the uploads directory
  defp clean_temp_file(paths) when is_list(paths) do
    Enum.each(paths, &clean_temp_file/1)

    paths
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
    |> Enum.each(fn dir ->
      if String.starts_with?(dir, "priv/static/uploads/") and dir != "priv/static/uploads" do
        File.rmdir(dir)
      end
    end)

    :ok
  end

  defp clean_temp_file(path) when is_binary(path) do
    if String.starts_with?(path, "priv/static/uploads/") do
      case File.rm(path) do
        :ok ->
          :ok

        {:error, reason} ->
          IO.puts("Warning: Could not remove temporary file #{path}: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end

  defp clean_temp_file(_), do: :ok

  # Executes normal processing and parses result metrics
  defp execute_normal_processing(input_path, output_path, mode, options) do
    case API.FileProcessor.run(input_path, output_path, mode, options) do
      {:ok, report_path, report_data} ->
        content = File.read!(report_path)
        metrics = extract_metrics_from_report(content)

        {:ok,
         %{
           report_path: report_path,
           content: content,
           metrics: metrics,
           report_data: report_data,
           mode: mode,
           success: true
         }}

      {:error, errors} when is_list(errors) ->
        error_message = format_errors(errors)
        {:error, error_message}
    end
  end

  # Executes benchmark mode
  defp execute_benchmark(input_path, options) do
    try do
      total_files =
        cond do
          is_list(input_path) ->
            length(input_path)

          is_binary(input_path) and File.dir?(input_path) ->
            case File.ls(input_path) do
              {:ok, files} -> length(files)
              {:error, _} -> 0
            end

          is_binary(input_path) and File.regular?(input_path) ->
            1

          true ->
            0
        end

      {:ok, results} = API.FileProcessor.benchmark(input_path, options)

      {:ok,
       %{
         benchmark: true,
         results: results,
         success: true,
         total_files: total_files
       }}
    rescue
      e ->
        {:error, "Benchmark error: #{Exception.message(e)}"}
    end
  end

  # Extracts key metrics from the report content
  defp extract_metrics_from_report(content) do
    %{
      processed_files: extract_number(content, ~r/Total files processed:\s*(\d+)/),
      csv_files: extract_number(content, ~r/CSV files:\s*(\d+)/),
      json_files: extract_number(content, ~r/JSON files:\s*(\d+)/),
      log_files: extract_number(content, ~r/LOG files:\s*(\d+)/),
      processing_time: extract_time(content, ~r/Total processing time:\s*([\d.]+)\s*seconds/),
      success_rate: extract_percentage(content, ~r/Success rate:\s*([\d.]+)%/)
    }
  end

  # Extracts a number from text using regex
  defp extract_number(text, regex) do
    case Regex.run(regex, text) do
      [_, number] -> String.to_integer(number)
      _ -> 0
    end
  end

  # Extracts a time value from text using regex
  defp extract_time(text, regex) do
    case Regex.run(regex, text) do
      [_, time] -> String.to_float(time)
      _ -> 0.0
    end
  end

  # Extracts a percentage from text using regex
  defp extract_percentage(text, regex) do
    case Regex.run(regex, text) do
      [_, percentage] -> String.to_float(percentage)
      _ -> 0.0
    end
  end

  # Formats a list of errors into a readable string
  defp format_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(fn
      %{reason: :no_successful_files} ->
        "No files could be processed. All documents had critical errors or invalid formats."

      %{path: path, reason: reason, details: details} ->
        "• #{Path.basename(path)}: #{reason} - #{inspect(details)}"

      %{path: path, error: error} ->
        "• #{Path.basename(path)}: #{error}"

      other ->
        "• #{inspect(other)}"
    end)
    |> Enum.join("\n")
  end

  # Saves benchmark results to history
  defp save_to_history({:ok, %{benchmark: true} = res}) do
    attrs = %{
      mode: "benchmark",
      total_files: res.total_files,
      success_rate: 100.0,
      execution_time_ms: (res.results.sequential_time + res.results.parallel_time) * 1000,
      data: res.results
    }

    FileProcessor.History.create_report(attrs)
    {:ok, res}
  end

  # Saves normal processing results to history
  defp save_to_history({:ok, res}) do
    text_content =
      if Map.has_key?(res, :report_path) and File.exists?(res.report_path) do
        File.read!(res.report_path)
      else
        "No text report available."
      end

    file_name =
      if Map.has_key?(res, :report_path) and res.report_path do
        Path.basename(res.report_path)
      else
        nil
      end

    report_data_with_text =
      res.report_data
      |> Map.put(:full_text, text_content)
      |> Map.put(:original_report_name, file_name)

    cleaned_data = clean_for_json(report_data_with_text)

    total = res.report_data.counts.total
    successful = res.report_data.counts.ok
    rate = if total > 0, do: successful * 100.0 / total, else: 0.0

    attrs = %{
      mode: res.mode,
      total_files: total,
      success_rate: rate,
      execution_time_ms: res.report_data.elapsed_seconds * 1000,
      data: cleaned_data
    }

    FileProcessor.History.create_report(attrs)
    {:ok, res}
  end

  defp save_to_history(error), do: error

  # Cleans data structures so they can be properly encoded to JSON
  defp clean_for_json(%MapSet{} = data) do
    data |> MapSet.to_list() |> Enum.map(&clean_for_json/1)
  end

  defp clean_for_json(%{__struct__: _} = data), do: data

  defp clean_for_json(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, clean_for_json(v)} end)
  end

  defp clean_for_json(data) when is_list(data) do
    Enum.map(data, &clean_for_json/1)
  end

  defp clean_for_json(data) when is_tuple(data) do
    data |> Tuple.to_list() |> Enum.map(&clean_for_json/1)
  end

  defp clean_for_json(data), do: data
end
