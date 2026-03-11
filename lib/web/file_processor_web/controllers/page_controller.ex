defmodule FileProcessorWeb.PageController do
  use FileProcessorWeb, :controller

  @doc """
  Renders the main page with the processing form.
  """
  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Processes the uploaded files or the provided path.
  """
  def process(conn, params) do
    # Processes the file using the adapter
    case FileProcessorWeb.FileProcessingAdapter.process_from_web(params) do
      {:ok, result} ->
        conn
        |> put_flash(:info, "Processing completed successfully")
        |> render(:result, result: result)

      {:error, error_message} ->
        conn
        |> put_flash(:error, error_message)
        |> redirect(to: ~p"/")
    end
  end

  def history(conn, _params) do
    reports = FileProcessor.History.list_reports()

    render(conn, :history, reports: reports)
  end

  def history_detail(conn, %{"id" => id}) do
    report = FileProcessor.History.get_report!(id)
    atomized_data = atomize_keys(report.data)

    report_text = atomized_data[:full_text] || "Content not found"
    saved_name = atomized_data[:original_report_name]

    file_name =
      cond do
        is_binary(saved_name) ->
          saved_name

        not Enum.empty?(atomized_data[:csv_files] || []) ->
          folder =
            List.first(atomized_data[:csv_files]).path |> Path.dirname() |> Path.basename()

          "report_#{folder}.txt"

        not Enum.empty?(atomized_data[:json_files] || []) ->
          folder =
            List.first(atomized_data[:json_files]).path |> Path.dirname() |> Path.basename()

          "report_#{folder}.txt"

        not Enum.empty?(atomized_data[:log_files] || []) ->
          folder =
            List.first(atomized_data[:log_files]).path |> Path.dirname() |> Path.basename()

          "report_#{folder}.txt"

        true ->
          "report_#{report.inserted_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()}.txt"
      end

    reconstructed_result =
      if report.mode == "benchmark" do
        %{
          benchmark: true,
          results: atomized_data,
          success: true,
          input_path: ["History"]
        }
      else
        %{
          benchmark: false,
          report_data: atomized_data,
          success: true,
          mode: report.mode,
          input_path: ["Recovered from History"],
          report_path: file_name,
          report_text: report_text
        }
      end

    render(conn, :result, result: reconstructed_result)
  end

  # Processes map keys into atoms and evaluates values
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {maybe_atom(k), atomize_keys(v)}
    end)
  end

  # Iterates through lists to process each element
  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  # Evaluates strings for atom conversion
  defp atomize_keys(val) when is_binary(val) do
    maybe_atom(val)
  end

  # Handles default fallback for numbers and other unmapped types
  defp atomize_keys(other), do: other

  # Attempts to convert strings to existing atoms
  defp maybe_atom(string) when is_binary(string) do
    try do
      String.to_existing_atom(string)
    rescue
      ArgumentError -> string
    end
  end

  defp maybe_atom(other), do: other
end
