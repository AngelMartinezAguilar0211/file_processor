defmodule FileProcessorWeb.HistoryDetailLive do
  use FileProcessorWeb, :live_view

  alias FileProcessor.History
  import FileProcessorWeb.ResultsComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Fetches the specific report by its ID
    report = History.get_report!(id)

    # Safely converts string keys to atoms
    atomized_data = atomize_keys(report.data)

    # Retrieves text content and file name for the report wrapper
    report_text = atomized_data[:full_text] || "Content not found"
    saved_name = atomized_data[:original_report_name]

    # Determines the appropriate file name
    file_name =
      cond do
        is_binary(saved_name) ->
          saved_name

        not Enum.empty?(atomized_data[:csv_files] || []) ->
          folder = List.first(atomized_data[:csv_files]).path |> Path.dirname() |> Path.basename()
          "report_#{folder}.txt"

        not Enum.empty?(atomized_data[:json_files] || []) ->
          folder =
            List.first(atomized_data[:json_files]).path |> Path.dirname() |> Path.basename()

          "report_#{folder}.txt"

        not Enum.empty?(atomized_data[:log_files] || []) ->
          folder = List.first(atomized_data[:log_files]).path |> Path.dirname() |> Path.basename()
          "report_#{folder}.txt"

        true ->
          "report_#{report.inserted_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()}.txt"
      end

    # Wraps the data into the exact structure expected by the ResultsComponent
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

    {:ok,
     socket
     |> assign(report: report)
     |> assign(result: reconstructed_result)
     |> assign(active_tab: "summary")}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  # Recursively transforms maps and lists strings into atoms safely
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {maybe_atom(k), atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(val) when is_binary(val) do
    maybe_atom(val)
  end

  defp atomize_keys(other), do: other

  # Attempts to safely convert a string to an existing atom without exhausting memory
  defp maybe_atom(string) when is_binary(string) do
    try do
      String.to_existing_atom(string)
    rescue
      ArgumentError -> string
    end
  end

  defp maybe_atom(other), do: other
end
