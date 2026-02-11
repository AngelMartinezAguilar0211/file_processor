defmodule API.FileProcessor.FileReceiver do
  @moduledoc """
  This module is responsible for discovering and validating input files.

  It accepts:
  - A single file path
  - A directory path
  - A list of files and/or directories

  Only files with supported extensions (.csv, .json, .log) are returned.
  All errors are collected but never stop execution.
  """

  # List of supported file extensions
  @supported_exts [".json", ".csv", ".log"]

  # Public helper to expose supported extensions
  def supported_exts, do: @supported_exts

  # Error structure returned when discovery fails
  @type receive_error :: %{
          input: String.t(),
          reason: atom(),
          details: any()
        }

  @spec obtain(String.t() | [String.t()]) ::
          {:ok, [String.t()], [receive_error()]}
  def obtain(paths) do
    paths
    |> normalize_inputs()
    |> Enum.reduce({MapSet.new(), []}, fn input, {accumulated_set, accumulated_errors} ->
      # Each input is expanded independently
      case expand_input(input) do
        {:ok, files} ->
          # Use MapSet to avoid duplicated paths
          new_set =
            Enum.reduce(files, accumulated_set, fn file, set ->
              MapSet.put(set, file)
            end)

          {new_set, accumulated_errors}

        {:error, error} ->
          # Errors are accumulated
          {accumulated_set, [error | accumulated_errors]}
      end
    end)
    |> finalize()
  end

  # Normalizes a single string into a list
  defp normalize_inputs(input) when is_binary(input), do: [input]

  # Pass-through for lists
  defp normalize_inputs(inputs) when is_list(inputs), do: inputs

  # Final formatting of discovered files and errors
  defp finalize({files_set, errors}) do
    files =
      files_set
      |> MapSet.to_list()
      |> Enum.sort()

    # Always return {:ok, files, errors}
    {:ok, files, Enum.reverse(errors)}
  end

  # Expands a single input path
  defp expand_input(input) do
    cond do
      # Case: directory
      File.dir?(input) ->
        list_supported_files_in_dir(input)

      # Case: regular file
      File.regular?(input) ->
        ext = Path.extname(input)

        if ext in @supported_exts do
          {:ok, [input]}
        else
          {:error,
           %{
             input: input,
             reason: :unsupported_format,
             details: "The #{ext} extension is not supported."
           }}
        end

      # Case: invalid path
      true ->
        if Path.extname(input) == "" do
          {:error,
           %{
             input: input,
             reason: :directory_not_found,
             details: "The given path is not a directory or does not exist."
           }}
        else
          {:error,
           %{
             input: input,
             reason: :file_not_found,
             details: "The given path is not a file or does not exist."
           }}
        end
    end
  end

  # Lists supported files inside a directory (recursive)
  defp list_supported_files_in_dir(dir) do
    dir
    |> File.ls()
    |> case do
      {:ok, _entries} ->
        # Recursively scan all entries under the directory
        pattern = Path.join([dir, "**", "*"])

        files =
          pattern
          |> Path.wildcard()
          |> Enum.filter(&File.regular?/1)
          |> Enum.filter(&supported_file?/1)

        if files == [] do
          {:error,
           %{
             input: dir,
             reason: :no_supported_files,
             details: "Directory contains no supported files."
           }}
        else
          {:ok, files}
        end

      {:error, reason} ->
        {:error, %{input: dir, reason: :directory_error, details: reason}}
    end
  end

  # Checks file extension against supported list
  defp supported_file?(file) do
    Path.extname(file) in @supported_exts
  end
end
