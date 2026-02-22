defmodule FileProcessorWeb.FileProcessingAdapter do
  @moduledoc """
  Adaptador que conecta la aplicación web Phoenix con el sistema de procesamiento
  de archivos. Maneja archivos subidos (Plug.Upload) y rutas de archivos locales.
  """

  @doc """
  Procesa archivos subidos a través del formulario web.

  Acepta:
  - archivo_subido: %Plug.Upload{} - archivo subido por el usuario
  - ruta_archivo: String - ruta local de archivo
  - opciones: Map con configuración de procesamiento

  Retorna:
  - {:ok, resultado} - con la ruta del reporte y datos para mostrar
  - {:error, razón} - en caso de error
  """
  def procesar_desde_web(params) do
    # 1. Determinar la fuente del archivo (upload o ruta)
    # Retorna {path, filename_original} o {path, nil}
    input_info = obtener_ruta_entrada(params)

    # 2. Validar que tenemos un archivo válido
    case validar_entrada(input_info) do
      :ok ->
        {input_path, _filename} = input_info

        # 3. Determinar modo de procesamiento
        modo = determinar_modo(params)

        # 4. Generar nombre de archivo de salida
        output_path = generar_nombre_salida(params)

        # 5. Extraer opciones de procesamiento (incluyendo error_log_path correcto)
        opciones = construir_opciones_con_log(params, output_path)

        # 6. Ejecutar procesamiento según el modo
        ejecutar_procesamiento(input_path, output_path, modo, opciones, params)

      {:error, mensaje} ->
        {:error, mensaje}
    end
  end

  # Obtiene la ruta de entrada del archivo desde los parámetros
  # Retorna {path_or_paths, filename_original} para poder validar la extensión correctamente
  defp obtener_ruta_entrada(%{"archivos_subidos" => archivos}) when is_list(archivos) do
    # Múltiples archivos subidos
    IO.puts("📤 Procesando #{length(archivos)} archivo(s) subido(s)...")

    # Generar un ID de lote único para esta ejecución (servirá como nombre de la subcarpeta)
    batch_id = System.system_time(:millisecond)

    # Copiar todos los archivos y recolectar sus rutas
    rutas_permanentes =
      archivos
      |> Enum.map(fn upload ->
        # Ahora pasamos el batch_id como segundo argumento
        case copiar_archivo_subido(upload, batch_id) do
          {:ok, ruta} -> ruta
          {:error, _} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    if rutas_permanentes == [] do
      {nil, nil}
    else
      # Retornar lista de rutas
      {rutas_permanentes, nil}
    end
  end

  # También actualizamos la versión para un solo archivo por consistencia
  defp obtener_ruta_entrada(%{"archivos_subidos" => upload}) when is_map(upload) do
    batch_id = System.system_time(:millisecond)

    case copiar_archivo_subido(upload, batch_id) do
      {:ok, ruta_permanente} ->
        {ruta_permanente, upload.filename}

      {:error, _reason} ->
        {nil, nil}
    end
  end

  defp obtener_ruta_entrada(%{"archivos_subidos" => upload}) when is_map(upload) do
    batch_id = System.system_time(:millisecond)

    case copiar_archivo_subido(upload, batch_id) do
      {:ok, ruta_permanente} ->
        {ruta_permanente, upload.filename}

      {:error, _reason} ->
        {nil, nil}
    end
  end

  defp obtener_ruta_entrada(%{"ruta_archivo" => ruta}) when is_binary(ruta) and ruta != "" do
    # Si se proporcionó una ruta de archivo, el filename es nil (usaremos la ruta para la extensión)
    {String.trim(ruta), nil}
  end

  defp obtener_ruta_entrada(_params) do
    {nil, nil}
  end

  # Copia el archivo subido a una ubicación permanente dentro de una carpeta de lote
  defp copiar_archivo_subido(%Plug.Upload{path: temp_path, filename: filename}, batch_id) do
    # Crear subdirectorio único para este lote
    upload_dir = Path.join("priv/static/uploads", to_string(batch_id))
    File.mkdir_p!(upload_dir)

    # El archivo conserva su nombre original exacto
    destino = Path.join(upload_dir, filename)

    case File.cp(temp_path, destino) do
      :ok ->
        IO.puts("Archivo copiado: #{filename} -> #{destino}")
        {:ok, destino}

      {:error, reason} ->
        IO.puts("❌ Error al copiar archivo subido: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Valida que la entrada sea válida
  # Ahora recibe {path_or_paths, filename} en lugar de solo path
  defp validar_entrada({nil, _}) do
    {:error, "Debes subir uno o más archivos, o proporcionar una ruta válida"}
  end

  defp validar_entrada({paths, _filename}) when is_list(paths) do
    # Lista de archivos - validar que todos existan
    if Enum.all?(paths, &File.regular?/1) do
      :ok
    else
      archivos_faltantes = Enum.filter(paths, fn p -> not File.regular?(p) end)
      {:error, "Algunos archivos no existen: #{inspect(archivos_faltantes)}"}
    end
  end

  defp validar_entrada({path, filename}) when is_binary(path) do
    cond do
      not File.exists?(path) ->
        {:error, "El archivo o directorio no existe: #{path}"}

      File.dir?(path) ->
        # Es un directorio, validar que contenga archivos soportados
        case tiene_archivos_soportados?(path) do
          true -> :ok
          false -> {:error, "El directorio no contiene archivos CSV, JSON o LOG"}
        end

      File.regular?(path) ->
        # Es un archivo, validar extensión
        # Si tenemos filename (Plug.Upload), usar ese para la extensión
        # Si no, usar el path directamente
        ext = if is_binary(filename), do: Path.extname(filename), else: Path.extname(path)

        if ext in [".csv", ".json", ".log"] do
          :ok
        else
          {:error,
           "Formato de archivo no soportado. Use CSV, JSON o LOG (extensión detectada: #{ext})"}
        end

      true ->
        {:error, "Ruta inválida"}
    end
  end

  # Verifica si un directorio contiene archivos soportados
  defp tiene_archivos_soportados?(dir) do
    Path.wildcard(Path.join([dir, "**", "*"]))
    |> Enum.any?(fn file ->
      File.regular?(file) and Path.extname(file) in [".csv", ".json", ".log"]
    end)
  end

  # Construye las opciones de procesamiento desde los parámetros del formulario
  defp construir_opciones(params) do
    opciones = []

    # Max workers
    opciones =
      case params["max_workers"] do
        "" ->
          opciones

        nil ->
          opciones

        value ->
          case parse_number_or_infinity(value) do
            nil -> opciones
            parsed -> Keyword.put(opciones, :max_workers, parsed)
          end
      end

    # Timeout
    opciones =
      case params["timeout"] do
        "" ->
          opciones

        nil ->
          opciones

        value ->
          case parse_number_or_infinity(value) do
            nil -> opciones
            parsed -> Keyword.put(opciones, :timeout_ms, parsed)
          end
      end

    # Retries
    opciones =
      case params["retry_count"] do
        "" ->
          opciones

        nil ->
          opciones

        value ->
          case Integer.parse(value) do
            {num, ""} when num >= 0 -> Keyword.put(opciones, :retries, num)
            _ -> opciones
          end
      end

    opciones
  end

  # Construye las opciones de procesamiento incluyendo error_log_path
  defp construir_opciones_con_log(params, output_path) do
    opciones = construir_opciones(params)

    # Agregar error_log_path basado en el nombre del reporte
    # Esto evita el bug del default que incluye toda la ruta
    File.mkdir_p!("logs")
    base_name = output_path |> Path.basename() |> Path.rootname()
    error_log = "logs/#{base_name}_errors.log"

    Keyword.put(opciones, :error_log_path, error_log)
  end

  # Parsea un número o la palabra "infinity"
  defp parse_number_or_infinity("infinity"), do: :infinity
  defp parse_number_or_infinity("Infinity"), do: :infinity
  defp parse_number_or_infinity("INFINITY"), do: :infinity

  defp parse_number_or_infinity(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, ""} when num > 0 -> num
      _ -> nil
    end
  end

  # Determina el modo de procesamiento
  defp determinar_modo(%{"processing_type" => "paralelo"}), do: "parallel"
  defp determinar_modo(%{"processing_type" => "secuencial"}), do: "sequential"
  # Default
  defp determinar_modo(_), do: "parallel"

  # Genera el nombre del archivo de salida
  defp generar_nombre_salida(%{"report_name" => nombre})
       when is_binary(nombre) and nombre != "" do
    # Sanitizar el nombre del archivo
    nombre_limpio =
      nombre
      |> String.trim()
      |> String.replace(~r/[^\w\s-]/, "")
      |> String.replace(~r/\s+/, "_")

    # Asegurar que termine en .txt
    if String.ends_with?(nombre_limpio, ".txt") do
      "priv/static/reports/#{nombre_limpio}"
    else
      "priv/static/reports/#{nombre_limpio}.txt"
    end
  end

  defp generar_nombre_salida(_params) do
    # Generar nombre con timestamp
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_unix()

    "priv/static/reports/reporte_#{timestamp}.txt"
  end

  # Ejecuta el procesamiento según el modo seleccionado
  defp ejecutar_procesamiento(input_path, output_path, modo, opciones, params) do
    # Asegurar que existe el directorio de reportes
    File.mkdir_p!("priv/static/reports")

    # Verificar si está activado el benchmark
    # Los checkboxes HTML envían "on" cuando están marcados, o nada cuando no lo están
    benchmark_activo? = params["benchmark_active"] in ["true", "on"]

    resultado =
      if benchmark_activo? do
        ejecutar_benchmark(input_path, opciones)
      else
        ejecutar_procesamiento_normal(input_path, output_path, modo, opciones)
      end

    # Limpiar archivo temporal si fue un archivo subido (está en priv/static/uploads)
    limpiar_archivo_temporal(input_path)

    guardar_en_historial(resultado)
  end

  # Handles both a single path (binary) and a list of paths.
  defp limpiar_archivo_temporal(paths) when is_list(paths) do
    # 1. Borrar cada archivo individualmente
    Enum.each(paths, &limpiar_archivo_temporal/1)

    # 2. Borrar los directorios vacíos que quedaron
    paths
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
    |> Enum.each(fn dir ->
      # Asegurarnos de que estamos borrando solo dentro de uploads
      if String.starts_with?(dir, "priv/static/uploads/") and dir != "priv/static/uploads" do
        # rmdir es seguro, solo borra la carpeta si ya no tiene archivos
        File.rmdir(dir)
      end
    end)

    :ok
  end

  defp limpiar_archivo_temporal(path) when is_binary(path) do
    # Only remove files that are inside the uploads directory
    if String.starts_with?(path, "priv/static/uploads/") do
      case File.rm(path) do
        :ok ->
          :ok

        {:error, reason} ->
          IO.puts("Advertencia: No se pudo eliminar archivo temporal #{path}: #{inspect(reason)}")
          :ok
      end
    else
      # Do not remove files provided by the user via external/local path
      :ok
    end
  end

  # Safety fallback for unexpected inputs (nil, maps, etc.)
  defp limpiar_archivo_temporal(_), do: :ok

  # Ejecuta el procesamiento normal
  defp ejecutar_procesamiento_normal(input_path, output_path, modo, opciones) do
    case API.FileProcessor.run(input_path, output_path, modo, opciones) do
      {:ok, report_path, report_data} ->
        # Leer el contenido del reporte para mostrarlo
        contenido = File.read!(report_path)

        # Extraer métricas clave del reporte para la vista
        metricas = extraer_metricas_del_reporte(contenido)

        {:ok,
         %{
           ruta_reporte: report_path,
           contenido: contenido,
           metricas: metricas,
           report_data: report_data,
           modo: modo,
           exito: true
         }}

      {:error, errores} when is_list(errores) ->
        mensaje_error = formatear_errores(errores)
        {:error, mensaje_error}
    end
  end

  # Ejecuta el benchmark
  defp ejecutar_benchmark(input_path, opciones) do
    try do
      {:ok, resultados} = API.FileProcessor.benchmark(input_path, opciones)

      {:ok,
       %{
         benchmark: true,
         resultados: resultados,
         exito: true
       }}
    rescue
      e ->
        {:error, "Error en benchmark: #{Exception.message(e)}"}
    end
  end

  # Extrae métricas clave del contenido del reporte
  defp extraer_metricas_del_reporte(contenido) do
    # Extraer información básica usando expresiones regulares
    %{
      archivos_procesados: extraer_numero(contenido, ~r/Total files processed:\s*(\d+)/),
      archivos_csv: extraer_numero(contenido, ~r/CSV files:\s*(\d+)/),
      archivos_json: extraer_numero(contenido, ~r/JSON files:\s*(\d+)/),
      archivos_log: extraer_numero(contenido, ~r/LOG files:\s*(\d+)/),
      tiempo_procesamiento:
        extraer_tiempo(contenido, ~r/Total processing time:\s*([\d.]+)\s*seconds/),
      tasa_exito: extraer_porcentaje(contenido, ~r/Success rate:\s*([\d.]+)%/)
    }
  end

  # Extrae un número del texto usando regex
  defp extraer_numero(texto, regex) do
    case Regex.run(regex, texto) do
      [_, numero] -> String.to_integer(numero)
      _ -> 0
    end
  end

  # Extrae un tiempo del texto usando regex
  defp extraer_tiempo(texto, regex) do
    case Regex.run(regex, texto) do
      [_, tiempo] -> String.to_float(tiempo)
      _ -> 0.0
    end
  end

  # Extrae un porcentaje del texto usando regex
  defp extraer_porcentaje(texto, regex) do
    case Regex.run(regex, texto) do
      [_, porcentaje] -> String.to_float(porcentaje)
      _ -> 0.0
    end
  end

  defp formatear_errores(errores) when is_list(errores) do
    errores
    |> Enum.map(fn
      %{reason: :no_successful_files} ->
        "No se pudo procesar ningún archivo. Todos los documentos presentaban errores críticos o su formato era inválido."

      %{path: path, reason: reason, details: details} ->
        "• #{Path.basename(path)}: #{reason} - #{inspect(details)}"

      %{path: path, error: error} ->
        "• #{Path.basename(path)}: #{error}"

      otro ->
        "• #{inspect(otro)}"
    end)
    |> Enum.join("\n")
  end

  defp guardar_en_historial({:ok, %{benchmark: true} = res}) do
    attrs = %{
      mode: "benchmark",
      total_files: 2,
      success_rate: 100.0,
      execution_time_ms: (res.resultados.sequential_time + res.resultados.parallel_time) * 1000,
      data: res.resultados
    }

    FileProcessor.History.create_report(attrs)
    {:ok, res}
  end

  defp guardar_en_historial({:ok, res}) do
    total = res.report_data.counts.total
    exitosos = res.report_data.counts.ok
    tasa = if total > 0, do: exitosos * 100.0 / total, else: 0.0

    data_limpia = limpiar_para_json(res.report_data)

    attrs = %{
      mode: res.modo,
      total_files: total,
      success_rate: tasa,
      execution_time_ms: res.report_data.elapsed_seconds * 1000,
      data: data_limpia
    }

    FileProcessor.History.create_report(attrs)
    {:ok, res}
  end

  defp guardar_en_historial(error), do: error

  defp limpiar_para_json(%MapSet{} = data) do
    data |> MapSet.to_list() |> Enum.map(&limpiar_para_json/1)
  end

  defp limpiar_para_json(%{__struct__: _} = data), do: data

  defp limpiar_para_json(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, limpiar_para_json(v)} end)
  end

  defp limpiar_para_json(data) when is_list(data) do
    Enum.map(data, &limpiar_para_json/1)
  end

  defp limpiar_para_json(data) when is_tuple(data) do
    data |> Tuple.to_list() |> Enum.map(&limpiar_para_json/1)
  end

  defp limpiar_para_json(data), do: data
end
