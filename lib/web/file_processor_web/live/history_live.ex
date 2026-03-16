defmodule FileProcessorWeb.HistoryLive do
  use FileProcessorWeb, :live_view

  alias FileProcessor.History

  @impl true
  def mount(_params, _session, socket) do
    # Fetches all processing reports from the database
    reports = History.list_reports()
    {:ok, assign(socket, reports: reports)}
  end
end
