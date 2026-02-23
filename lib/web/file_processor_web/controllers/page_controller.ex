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

      {:error, mensaje_error} ->
        # Atrapa cualquier error y lo muestra
        IO.puts("Error durante procesamiento: #{mensaje_error}")

        conn
        |> put_flash(:error, mensaje_error)
        |> redirect(to: ~p"/")
    end
  end

  def historial(conn, _params) do
    reportes = FileProcessor.History.list_reports()

    render(conn, :historial, reportes: reportes)
  end

  def detalle_historial(conn, %{"id" => id}) do
    reporte = FileProcessor.History.get_report!(id)
    datos_atomizados = atomize_keys(reporte.data)

    texto_reporte = datos_atomizados[:texto_completo] || "Contenido no encontrado"
    nombre_guardado = datos_atomizados[:nombre_reporte_original]

    nombre_archivo =
      cond do
        is_binary(nombre_guardado) ->
          nombre_guardado

        not Enum.empty?(datos_atomizados[:csv_files] || []) ->
          carpeta =
            List.first(datos_atomizados[:csv_files]).path |> Path.dirname() |> Path.basename()

          "reporte_#{carpeta}.txt"

        not Enum.empty?(datos_atomizados[:json_files] || []) ->
          carpeta =
            List.first(datos_atomizados[:json_files]).path |> Path.dirname() |> Path.basename()

          "reporte_#{carpeta}.txt"

        not Enum.empty?(datos_atomizados[:log_files] || []) ->
          carpeta =
            List.first(datos_atomizados[:log_files]).path |> Path.dirname() |> Path.basename()

          "reporte_#{carpeta}.txt"

        true ->
          "reporte_#{reporte.inserted_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()}.txt"
      end

    resultado_reconstruido =
      if reporte.mode == "benchmark" do
        %{
          benchmark: true,
          resultados: datos_atomizados,
          exito: true,
          input_path: ["Historial"]
        }
      else
        %{
          benchmark: false,
          report_data: datos_atomizados,
          exito: true,
          modo: reporte.mode,
          input_path: ["Recuperado del Historial"],
          ruta_reporte: nombre_archivo,
          texto_reporte: texto_reporte
        }
      end

    render(conn, :resultado, resultado: resultado_reconstruido)
  end

  # 1. Para Mapas: atomizamos llaves y procesamos valores
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {maybe_atom(k), atomize_keys(v)}
    end)
  end

  # 2. Para Listas: procesamos cada elemento
  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  # 3. Para Valores de Texto: intentamos convertirlos a átomos (ej: "ok" -> :ok)
  defp atomize_keys(val) when is_binary(val) do
    maybe_atom(val)
  end

  # Caso base para números y otros tipos
  defp atomize_keys(other), do: other

  # Función de apoyo para no repetir código
  defp maybe_atom(string) when is_binary(string) do
    try do
      String.to_existing_atom(string)
    rescue
      # Si es una ruta o mensaje largo, se queda como texto
      ArgumentError -> string
    end
  end

  defp maybe_atom(other), do: other
end
