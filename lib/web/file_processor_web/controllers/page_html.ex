defmodule FileProcessorWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FileProcessorWeb, :html

  embed_templates "page_html/*"

  @doc """
  Extrae la sección de resumen ejecutivo del contenido del reporte.
  """
  def extraer_seccion_resumen(contenido) do
    # Buscar la sección "EXECUTIVE SUMMARY" en el reporte
    case String.split(contenido, "EXECUTIVE SUMMARY") do
      [_antes, despues] ->
        # Extraer todo hasta la siguiente sección (línea de guiones)
        despues
        |> String.split(
          "--------------------------------------------------------------------------------"
        )
        |> List.first()
        |> String.trim()

      _ ->
        # Si no se encuentra la sección, mostrar las primeras líneas
        contenido
        |> String.split("\n")
        |> Enum.take(20)
        |> Enum.join("\n")
    end
  end
end
