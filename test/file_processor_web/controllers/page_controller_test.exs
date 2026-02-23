defmodule FileProcessorWeb.PageControllerTest do
  use FileProcessorWeb.ConnCase

  @moduletag :web

  describe "GET / (Página de Inicio)" do
    test "muestra el formulario principal correctamente", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ "File Processor"

      assert html_response(conn, 200) =~ "Cargar Archivos"
      assert html_response(conn, 200) =~ "Secuencial"
      assert html_response(conn, 200) =~ "Paralelo"
    end
  end

  describe "GET /historial" do
    test "muestra la tabla del historial", %{conn: conn} do
      conn = get(conn, ~p"/historial")

      assert html_response(conn, 200) =~ "Historial de Procesamientos"
    end
  end

  describe "GET /historial/:id" do
    test "reconstruye y muestra un reporte guardado en base de datos", %{conn: conn} do
      {:ok, reporte} =
        FileProcessor.History.create_report(%{
          mode: "paralelo",
          total_files: 3,
          success_rate: 100.0,
          execution_time_ms: 45.5,
          data: %{
            "texto_completo" => "Este es un reporte de prueba unitaria",
            "nombre_reporte_original" => "reporte_test.txt",
            "elapsed_seconds" => 0.045,
            "counts" => %{
              "total" => 3,
              "ok" => 3,
              "failed" => 0,
              "csv" => 1,
              "json" => 1,
              "log" => 1
            },
            "errors" => [],
            "csv_files" => [],
            "json_files" => [],
            "log_files" => [],
            "csv_totals" => %{
              "total_sales" => 1050.50,
              "unique_products" => 10
            },
            "json_totals" => %{
              "total_users" => 50,
              "active_users" => 45,
              "inactive_users" => 5
            },
            "log_totals" => %{
              "total_entries" => 100,
              "by_level" => %{"INFO" => 90, "ERROR" => 10}
            }
          }
        })

      conn = get(conn, ~p"/historial/#{reporte.id}")

      respuesta_html = html_response(conn, 200)

      assert respuesta_html =~ "Resultados del Procesamiento"
      assert respuesta_html =~ "Paralelo"
      assert respuesta_html =~ "reporte_test.txt"
      assert respuesta_html =~ "1050.5"
    end
  end

  describe "POST /procesar" do
    test "redirige al inicio con error si se envían parámetros inválidos", %{conn: conn} do
      conn = post(conn, ~p"/procesar", %{"processing_type" => "secuencial"})

      assert redirected_to(conn) == ~p"/"

      conn = get(conn, ~p"/")
      respuesta_html = html_response(conn, 200)

      assert respuesta_html =~ "File Processor"
    end
  end
end
