defmodule FileProcessorWeb.PageController do
  use FileProcessorWeb, :controller

  @doc """
  Renderiza la página principal con el formulario de procesamiento.
  """
  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Procesa los archivos subidos o la ruta proporcionada.

  Recibe los parámetros del formulario:
  - archivo_subido: archivo subido por el usuario
  - ruta_archivo: ruta local del archivo/directorio
  - processing_type: "secuencial" o "paralelo"
  - benchmark_active: "true" si está activado el benchmark
  - report_name: nombre personalizado del reporte
  - retry_count: número de reintentos
  - max_workers: número máximo de workers
  - timeout: timeout en milisegundos
  """
  def procesar(conn, params) do
    # Loguear los parámetros recibidos para debugging
    IO.inspect(params, label: "PARAMS RECIBIDOS")

    # Procesar el archivo usando el adaptador
    case FileProcessorWeb.FileProcessingAdapter.procesar_desde_web(params) do
      {:ok, resultado} ->
        # Éxito: renderizar página de resultados
        IO.puts("Procesamiento exitoso, renderizando resultados...")

        conn
        |> put_flash(:info, "Procesamiento completado exitosamente")
        |> render(:resultado, resultado: resultado)

      {:error, mensaje_error} when is_binary(mensaje_error) ->
        # Error con mensaje string: volver al formulario
        IO.puts("Error durante procesamiento: #{mensaje_error}")

        conn
        |> put_flash(:error, mensaje_error)
        |> redirect(to: ~p"/")

      {:error, errores} when is_list(errores) ->
        # Error con lista de errores: formatear y mostrar
        IO.puts("Múltiples errores durante procesamiento")
        IO.inspect(errores, label: "ERRORES")

        mensaje = formatear_errores(errores)

        conn
        |> put_flash(:error, mensaje)
        |> redirect(to: ~p"/")
    end
  end

  # Formatea una lista de errores en un mensaje legible
  defp formatear_errores(errores) when is_list(errores) do
    errores
    # Mostrar máximo 5 errores
    |> Enum.take(5)
    |> Enum.map(fn
      %{path: path, reason: reason, details: details} ->
        "• #{path}: #{reason} - #{inspect(details)}"

      %{path: path, error: error} ->
        "• #{path}: #{error}"

      otro ->
        "• #{inspect(otro)}"
    end)
    |> Enum.join("\n")
    |> then(fn msg ->
      if length(errores) > 5 do
        msg <> "\n... y #{length(errores) - 5} errores más"
      else
        msg
      end
    end)
  end

  def historial(conn, _params) do
    reportes = FileProcessor.History.list_reports()

    render(conn, :historial, reportes: reportes)
  end
end
