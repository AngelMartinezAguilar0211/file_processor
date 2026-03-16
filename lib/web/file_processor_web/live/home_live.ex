defmodule FileProcessorWeb.HomeLive do
  use FileProcessorWeb, :live_view

  # Imports the results component module
  import FileProcessorWeb.ResultsComponents

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

    socket =
      socket
      |> assign(form: to_form(initial_form))
      |> assign(show_all_files: false)
      |> assign(result: nil)
      |> assign(active_tab: "summary")
      |> assign(processing: false)
      |> assign(progress: 0)
      |> allow_upload(:uploaded_files, accept: ~w(.csv .json .log), max_entries: 1000)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, form: to_form(params))}
  end

  @impl true
  def handle_event("save", %{"file_path" => file_path} = form_params, socket) do
    # Consumes uploaded files and wraps them in a Plug.Upload struct for compatibility
    uploaded_plugs =
      consume_uploaded_entries(socket, :uploaded_files, fn %{path: path}, entry ->
        dest = Path.join(System.tmp_dir!(), "#{System.system_time()}-#{entry.client_name}")
        File.cp!(path, dest)

        upload_struct = %Plug.Upload{
          path: dest,
          filename: entry.client_name,
          content_type: entry.client_type
        }

        {:ok, upload_struct}
      end)

    input_info =
      if uploaded_plugs != [] do
        %{"uploaded_files" => uploaded_plugs}
      else
        %{"file_path" => file_path}
      end

    # Validates input availability based on what was provided
    validation_result = validate_input_availability(input_info)

    case validation_result do
      :ok ->
        processing_params = Map.merge(form_params, input_info)
        caller_pid = self()
        # Spawns an asynchronous task to free the LiveView process and keep UI responsive
        Task.start(fn ->
          # Confirms the task process has successfully started
          IO.puts("6. Task started successfully")

          processing_params = Map.put(processing_params, "caller_pid", caller_pid)

          # Executes the file processing pipeline
          result = FileProcessorWeb.FileProcessingAdapter.process_from_web(processing_params)
          send(caller_pid, {:processing_finished, result})
        end)

        # Sets the UI to loading mode immediately and clears previous flashes
        {:noreply, socket |> clear_flash() |> assign(processing: true, progress: 0)}

      {:error, message} ->
        # Blocks execution and shows an error if no input is provided
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :uploaded_files, ref)}
  end

  # Toggles the visibility state of the uploaded files list
  @impl true
  def handle_event("toggle-files", _params, socket) do
    {:noreply, assign(socket, show_all_files: !socket.assigns.show_all_files)}
  end

  # Handles dynamic tab switching for the results view
  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  # Listens for incremental progress updates from the background task
  @impl true
  def handle_info({:progress, percent}, socket) do
    {:noreply, assign(socket, progress: percent)}
  end

  # Handles the successful completion message from the background task
  @impl true
  def handle_info({:processing_finished, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Procesamiento completado con éxito")
     |> assign(processing: false)
     |> assign(progress: 100)
     |> assign(result: result)
     |> assign(active_tab: "summary")}
  end

  # Handles failure messages from the background task
  # Handles failure messages from the background task
  @impl true
  def handle_info({:processing_finished, {:error, reason}}, socket) do
    error_message = format_api_error(reason)

    {:noreply,
     socket
     |> put_flash(:error, error_message)
     |> assign(processing: false)
     |> assign(progress: 0)}
  end

  # Renders a single uploaded file entry to prevent code duplication
  def file_entry(assigns) do
    ~H"""
    <div style="display: flex; justify-content: space-between; align-items: center; background: #f3f4f6; padding: 8px; border-radius: 4px; margin-bottom: 5px;">
      <span style="font-size: 0.875rem; text-overflow: ellipsis; overflow: hidden; white-space: nowrap; max-width: 80%;">
        {@entry.client_name}
      </span>
      <button
        type="button"
        phx-click="cancel-upload"
        phx-value-ref={@entry.ref}
        style="color: #ef4444; font-weight: bold; background: none; border: none; cursor: pointer;"
      >
        &times;
      </button>
    </div>
    <%= for err <- upload_errors(@upload, @entry) do %>
      <p style="color: #ef4444; font-size: 0.75rem; margin-top: 2px;">{error_to_string(err)}</p>
    <% end %>
    """
  end

  # Validates that an input source is available for processing
  defp validate_input_availability(%{"uploaded_files" => files})
       when is_list(files) and length(files) > 0, do: :ok

  defp validate_input_availability(%{"file_path" => path}) when is_binary(path) and path != "",
    do: :ok

  defp validate_input_availability(_),
    do: {:error, "Debes subir archivos o ingresar una ruta válida."}

  # Formats API error structures into human-readable strings
  defp format_api_error(errors) when is_list(errors) do
    # Extracts the most relevant high-level error if present
    case Enum.find(
           errors,
           &(&1.reason in [:no_successful_files, :argument_malformed, :invalid_mode])
         ) do
      nil -> "No se encontraron archivos válidos o hubo errores de lectura. Revisa la ruta."
      main_error -> format_api_error(main_error)
    end
  end

  defp format_api_error(%{reason: :no_successful_files}) do
    "Ningún archivo pudo ser procesado con éxito. Revisa que el formato y la estructura sean correctos."
  end

  defp format_api_error(%{reason: :argument_malformed}) do
    "Los argumentos de procesamiento son inválidos."
  end

  defp format_api_error(%{reason: :invalid_mode}) do
    "El modo de procesamiento seleccionado no es válido."
  end

  defp format_api_error(msg) when is_binary(msg), do: msg

  defp format_api_error(_), do: "Ocurrió un error desconocido durante el procesamiento."
  # Translates upload errors to string messages
  defp error_to_string(:too_large), do: "El archivo es demasiado grande"
  defp error_to_string(:too_many_files), do: "Demasiados archivos seleccionados"
  defp error_to_string(:not_accepted), do: "Tipo de archivo no aceptado"
end
