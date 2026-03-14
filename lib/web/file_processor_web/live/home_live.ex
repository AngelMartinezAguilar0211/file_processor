defmodule FileProcessorWeb.HomeLive do
  use FileProcessorWeb, :live_view

  # Initializes the state for the LiveView socket
  @impl true
  def mount(_params, _session, socket) do
    initial_form = %{
      "processing_type" => "parallel",
      "benchmark_active" => "false",
      "report_name" => "",
      "retry_count" => "",
      "max_workers" => "",
      "timeout" => "",
      "file_path" => ""
    }

    {:ok, assign(socket, form: to_form(initial_form))}
  end

  # Handles real-time validation for the form
  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, form: to_form(params))}
  end

  # Handles form submission
  @impl true
  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end
end
