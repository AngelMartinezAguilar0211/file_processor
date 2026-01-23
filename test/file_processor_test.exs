defmodule FileProcessorTest do
  use ExUnit.Case
  doctest FileProcessor
  @output "reporte_final.txt"

  setup do
    if File.exists?(@output), do: File.rm!(@output)
    :ok
  end

  # Report generation
  test "run/1 processes a valid directory and generates a report" do
    result = silent_execution(["data"])
    assert {:ok, path} = result
    assert File.exists?(path)
  end

  test "run/1 generates a report with the correct format" do
    result = silent_execution(["data"])
    assert {:ok, path} = result
    content = File.read!(path)
    assert String.contains?(content, "FILE PROCESSING REPORT")
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "ERRORS AND WARNINGS")
  end

  test "run/1 processes a mix of valid and error files" do
    result = silent_execution(["data"])
    assert {:ok, path} = result
    content = File.read!(path)

    assert String.contains?(content, "ERRORS AND WARNINGS")
    assert String.contains?(content, "ventas_corrupto.csv")
    assert String.contains?(content, "usuarios_malformado.json")
  end

  test "run/1 returns :no_supported_files when directory has no supported files" do
    result = silent_execution(["test"])
    assert {:error, errors} = result
    assert is_list(errors)
    assert length(errors) > 0

    assert Enum.any?(errors, fn e ->
             e.path == "test" and
               e.reason == :no_supported_files and
               e.details == "Directory contains no supported files."
           end)

    # Report must NOT be written when nothing is discovered/readable
    refute File.exists?("reporte_final.txt")
  end

  test "run/2 writes report to custom output path" do
    result = silent_execution(["data", @output])
    assert {:ok, path} = result
    assert path == Path.expand(@output)
    assert File.exists?(@output)
  end

  test "run/3 stores processing mode in report" do
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    {:ok, path} = FileProcessor.run("data", @output, "sequential")

    Process.group_leader(self(), original)
    File.close(devnull)
    content = File.read!(path)

    assert String.contains?(content, "Processing mode: sequential")
  end

  test "run/1 defaults to parallel mode and prints progress lines" do
    io =
      ExUnit.CaptureIO.capture_io(fn ->
        {:ok, path} = FileProcessor.run("data")
        assert File.exists?(path)

        content = File.read!(path)
        assert String.contains?(content, "Processing mode: parallel")
      end)

    # Progress is printed by FileProcessor in parallel mode
    assert String.contains?(io, "[parallel]")
    assert String.contains?(io, "processed:")
  end

  # Report format and metrics
  test "The report process all the base files in data" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "Total files processed: 8")
  end

  test "The execution calculates total sales for CSV" do
    result = silent_execution(["data/valid/ventas_enero.csv"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Total sales: $24399.93")
  end

  test "The execution calculates unique products for CSV" do
    result = silent_execution(["data/valid/ventas_enero.csv"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Unique products: 15")
  end

  test "The execution calculates best selling product for CSV" do
    result = silent_execution(["data/valid/ventas_enero.csv"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Best-selling product: Cable HDMI")
  end

  test "The execution calculates highest revenue category for CSV" do
    result = silent_execution(["data/valid/ventas_enero.csv"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Highest-revenue category: Computadoras")
  end

  test "The execution calculates Average discount for CSV" do
    result = silent_execution(["data/valid/ventas_enero.csv"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Average discount applied: 12.0%")
  end

  test "The execution displays CSV period" do
    result = silent_execution(["data/valid/ventas_enero.csv"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Period: 2024-01-02 to 2024-01-30")
  end

  test "The execution calculates total sales for all CSV files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Total sales: $51121.31")
  end

  test "The execution calculates total unique products in all CSV files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "CSV FILE METRICS")
    assert String.contains?(content, "Total unique products: 31")
  end

  test "The execution calculates registered users for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Registered users: 8")
  end

  test "The execution calculates active users for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Active users: 7")
  end

  test "The execution calculates inactive users for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Inactive users: 1")
  end

  test "The execution calculates average session duration for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Average session duration: 30.0 minutes")
  end

  test "The execution calculates total pages visited for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Total pages visited: 285")
  end

  test "The execution displays top actions for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Top actions:")
    assert String.contains?(content, "1. login (12 times)")
    assert String.contains?(content, "2. logout (12 times)")
  end

  test "The execution displays peak activity hour for JSON files" do
    result = silent_execution(["data/valid/sesiones.json"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Peak activity hour: 8:00 (2 sessions)")
  end

  test "The report excludes JSON files with errors" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "Omitted files (errors were found):")
    assert String.contains?(content, "- usuarios_malformado.json (failed)")
  end

  test "The report calculates total users for all JSON files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Total users (sum): 18")
  end

  test "The report indicates total active users for JSON files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Active (sum): 14")
  end

  test "The report indicates total active users for all JSON files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "JSON FILE METRICS")
    assert String.contains?(content, "Inactive (sum): 4")
  end

  test "The execution calculates total entries for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "Total entries: 71")
  end

  test "The execution calculates levels distribution for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "Level distribution: DEBUG=10, ERROR=8, INFO=47, WARN=6")
  end

  test "The execution calculates components with most errors for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "Components with most errors: Integration (2 errors)")
  end

  test "The execution calculates time distribution for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")

    assert String.contains?(
             content,
             "Time distribution (by hour): 8=11, 9=8, 10=9, 11=6, 12=6, 13=4, 14=6, 15=7"
           )
  end

  test "The execution displays most frequent errors for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "Most frequent errors:")
    assert String.contains?(content, "1. API externa retornó código 503 (1)")
    assert String.contains?(content, "2. Constraint violation: stock no puede ser negativo (1)")
  end

  test "The calculates time between critical errors for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")

    assert String.contains?(
             content,
             "Time between critical errors (sec): avg=3465.14, min=1, max=10754, n=7"
           )
  end

  test "The report calculates recurring error patterns for log files" do
    result = silent_execution(["data/valid/aplicacion.log"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "Recurring error patterns:")
    assert String.contains?(content, "1. API externa retornó código <num> (1)")
  end

  test "The execution calculates total entries for all the log files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")
    assert String.contains?(content, "Total entries: 143")
  end

  test "The execution calculates level distribution for all the log files" do
    result = silent_execution(["data"])
    assert {:ok, data} = result
    content = File.read!(data)
    assert String.contains?(content, "LOG FILE METRICS")

    assert String.contains?(
             content,
             "Level distribution: DEBUG=16, ERROR=17, FATAL=1, INFO=96, WARN=13"
           )
  end

  # Benchmark tests
  test "benchmark/1 prints block correctly" do
    io =
      ExUnit.CaptureIO.capture_io(fn ->
        FileProcessor.benchmark("data")
      end)

    # Console comparison block
    assert String.contains?(io, "BENCHMARK RESULTS")
    assert String.contains?(io, "Sequential:")
    assert String.contains?(io, "Parallel:")
    assert String.contains?(io, "Speedup:")
  end

  # Inner functions tests
  test "FileReceiver.obtain/1 returns only supported files for a directory with existing fixtures" do
    dir = existing_fixtures_dir!()

    {:ok, files, errors} = FileProcessor.FileReceiver.obtain(dir)

    # Directory used here is guaranteed to contain at least one supported fixture
    assert errors == []
    assert is_list(files)
    assert length(files) > 0

    supported = FileProcessor.FileReceiver.supported_exts()

    assert Enum.all?(files, fn path ->
             Path.extname(path) in supported
           end)
  end

  test "FileReceiver.obtain/1 accumulates errors for unsupported existing file and keeps valid discoveries" do
    dir = existing_fixtures_dir!()
    # This test file exists and should be unsupported (".exs")
    unsupported_existing_file = __ENV__.file

    {:ok, files, errors} =
      FileProcessor.FileReceiver.obtain([
        dir,
        unsupported_existing_file
      ])

    assert length(files) > 0

    assert Enum.any?(errors, fn e ->
             e.reason == :unsupported_format and e.input == unsupported_existing_file
           end)
  end

  test "FileReceiver.obtain/1 deduplicates repeated existing files" do
    file = existing_supported_file!()
    dir = Path.dirname(file)

    {:ok, files, errors} =
      FileProcessor.FileReceiver.obtain([
        dir,
        file,
        file
      ])

    assert errors == []

    # MapSet-based dedupe should keep a single occurrence
    assert Enum.count(files, fn p -> p == file end) == 1
  end

  test "FileReceiver.obtain/1 returns no_supported_files for an existing directory without supported files" do
    {:ok, files, errors} = FileProcessor.FileReceiver.obtain("test")

    assert files == []

    assert Enum.any?(errors, fn e ->
             e.reason == :no_supported_files and e.input == "test"
           end)
  end

  # Execution errors

  test "Error :argument_malformed" do
    response = silent_execution("data", ["reporte_final.txt"], "parallel")

    assert response ==
             {:error,
              [
                %{
                  reason: :argument_malformed,
                  path: "",
                  details:
                    "The given arguments are incorrect, the arguments must be: 1. a directory/file string path, 2. an output file string path, 3. a mode string indicator (parallel or sequential), and 4. a list of options (:max_workers, :timeout_ms and :retries)"
                }
              ]}
  end

  test "Error :directory_not_found" do
    response = silent_execution("data/invald")

    assert response ==
             {:error,
              [
                %{
                  reason: :directory_not_found,
                  path: "data/invald",
                  details: "The given path is not a directory or does not exist."
                }
              ]}
  end

  test "Error :no_successful_files" do
    response = silent_execution("data/invalid")

    assert response ==
             {:error,
              [
                %{
                  reason: :no_successful_files,
                  path: "run",
                  details:
                    "All files have errors or didn't reach status :ok (total=2, ok=0). Please check the logs for more details."
                }
              ]}
  end

  test "Error :no_supported_files" do
    response = silent_execution("test")

    assert response ==
             {:error,
              [
                %{
                  reason: :no_supported_files,
                  path: "test",
                  details: "Directory contains no supported files."
                }
              ]}
  end

  test "Error :unsupported_format" do
    response = silent_execution("mix.exs")

    assert response ==
             {:error,
              [
                %{
                  path: "mix.exs",
                  reason: :unsupported_format,
                  details: "The .exs extension is not supported."
                }
              ]}
  end

  test "Error :file_not_found" do
    response = silent_execution("mix.txt")

    assert response ==
             {:error,
              [
                %{
                  reason: :file_not_found,
                  path: "mix.txt",
                  details: "The given path is not a file or does not exist."
                }
              ]}
  end

  # -----------------------------
  # Helpers
  # -----------------------------

  defp existing_supported_file! do
    file =
      Path.wildcard("data/**/*.{csv,json,log}")
      |> Enum.find(&File.regular?/1)

    assert is_binary(file)
    file
  end

  defp existing_fixtures_dir! do
    existing_supported_file!()
    |> Path.dirname()
  end

  defp silent_execution(path), do: silent_execution(path, "reporte_final.txt", "sequential")

  defp silent_execution(path, output, mode) do
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    result = FileProcessor.run(path, output, mode)

    Process.group_leader(self(), original)
    File.close(devnull)
    result
  end
end
