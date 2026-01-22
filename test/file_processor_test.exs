defmodule FileProcessorTest do
  use ExUnit.Case
  doctest FileProcessor
  @output "reporte_final.txt"

  setup do
    if File.exists?(@output), do: File.rm!(@output)
    :ok
  end

  test "run/1 processes a valid directory and generates a report" do
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    result = FileProcessor.run("data")

    Process.group_leader(self(), original)
    File.close(devnull)
    assert {:ok, path} = result
    assert File.exists?(path)

    content = File.read!(path)
    assert String.contains?(content, "REPORTE DE PROCESAMIENTO DE ARCHIVOS")
    assert String.contains?(content, "MÉTRICAS DE ARCHIVOS CSV")
    assert String.contains?(content, "MÉTRICAS DE ARCHIVOS JSON")
    assert String.contains?(content, "MÉTRICAS DE ARCHIVOS LOG")
  end

  test "run/1 processes a mix of valid and error files" do
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    result =
      FileProcessor.run([
        "data/valid",
        "data/invalid"
      ])

    Process.group_leader(self(), original)
    File.close(devnull)

    assert {:ok, path} = result
    content = File.read!(path)

    assert String.contains?(content, "ERRORES Y ADVERTENCIAS")
    assert String.contains?(content, "ventas_corrupto.csv")
    assert String.contains?(content, "usuarios_malformado.json")
  end

  test "run/1 returns :no_supported_files when directory has no supported files" do
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    result = FileProcessor.run("test")

    Process.group_leader(self(), original)
    File.close(devnull)
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
    original = Process.group_leader()
    {:ok, devnull} = File.open("/dev/null", [:write])
    Process.group_leader(self(), devnull)

    result = FileProcessor.run("data", @output)

    Process.group_leader(self(), original)
    File.close(devnull)
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

    assert String.contains?(content, "Modo de procesamiento: sequential")
  end

  # -----------------------------
  # Delivery 2 tests
  # -----------------------------

  test "run/1 defaults to parallel mode and prints progress lines" do
    io =
      ExUnit.CaptureIO.capture_io(fn ->
        {:ok, path} = FileProcessor.run("data")
        assert File.exists?(path)

        content = File.read!(path)
        assert String.contains?(content, "Modo de procesamiento: parallel")
      end)

    # Progress is printed by FileProcessor in parallel mode
    assert String.contains?(io, "[parallel]")
    assert String.contains?(io, "processed:")
end

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
end
