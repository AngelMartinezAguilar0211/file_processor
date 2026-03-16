defmodule FileProcessorWeb.HistoryLiveTest do
  use FileProcessorWeb.ConnCase
  import Phoenix.LiveViewTest
  alias FileProcessor.History

  setup do
    # Creates a comprehensive mock report to properly test the detailed report breakdown
    {:ok, report} = History.create_report(%{
      mode: "parallel",
      total_files: 2,
      success_rate: 100.0,
      execution_time_ms: 120.5,
      data: %{
        "full_text" => "Contenido real del reporte de texto plano",
        "elapsed_seconds" => 0.120,
        "counts" => %{"ok" => 2, "total" => 2, "log" => 0, "json" => 1, "failed" => 0, "csv" => 1},
        "csv_files" => [
                  %{
                    "path" => "/fake/ventas.csv",
                    "status" => "ok",
                    "metrics" => %{
                      "total_sales" => 1500.50,
                      "unique_products" => 42,
                      "avg_discount_pct" => 5.12,
                      "top_product" => %{"name" => "Laptop", "value" => 10},
                      "top_category" => %{"name" => "Electronics", "value" => 5.50}
                    }
                  }
                ],
        "json_files" => [
          %{
            "path" => "/fake/usuarios.json",
            "status" => "ok",
            "metrics" => %{"total_users" => 10, "active_users" => 7, "inactive_users" => 3, "avg_session_seconds" => 600, "total_pages" => 20}
          }
        ],
        "log_files" => [],
        "csv_totals" => %{
                  "total_sales" => 1500.50,
                  "unique_products" => 42,
                  "avg_discount_pct" => 5.12,
                  "top_product" => %{"name" => "Laptop", "value" => 10},
                  "top_category" => %{"name" => "Electronics", "value" => 5.50}
                },
        "json_totals" => %{"active_users" => 7, "inactive_users" => 3, "total_users" => 10},
        "log_totals" => %{"total_entries" => 0, "by_level" => %{}},
        "errors" => []
      }
    })

    %{report: report}
  end

  test "renders the main history table", %{conn: conn, report: report} do
    # Mounts the history LiveView
    {:ok, _view, html} = live(conn, "/history")

    assert html =~ "Historial de Procesamientos"
    assert html =~ "PARALLEL"
    assert html =~ "100.0%"
    assert html =~ "120.5 ms"
    assert html =~ "/history/#{report.id}"
  end

  test "renders the detail view with the summary tab by default", %{conn: conn, report: report} do
    # Mounts the history detail LiveView
    {:ok, _view, html} = live(conn, "/history/#{report.id}")

    assert html =~ "Reporte ##{report.id}"
    assert html =~ "Resumen Ejecutivo"
    assert html =~ "Parallel"
    # Matches the 0.120 elapsed_seconds multiplied by 1000 in the UI
    assert html =~ "120.0 ms"
  end

  test "navigates to the detailed report tab and displays all file metrics", %{conn: conn, report: report} do
    # Mounts the history detail LiveView
    {:ok, view, _html} = live(conn, "/history/#{report.id}")

    # Clicks the actual "Reporte Detallado" tab from the component
    rendered_tab =
      view
      |> element("button", "Reporte Detallado")
      |> render_click()

    # Asserts CSV metrics are rendered within the detailed report
    assert rendered_tab =~ "Métricas de Archivos CSV"
    assert rendered_tab =~ "ventas.csv"
    assert rendered_tab =~ "1500.5"
    assert rendered_tab =~ "42"

    # Asserts JSON metrics are rendered within the detailed report
    assert rendered_tab =~ "Métricas de Archivos JSON"
    assert rendered_tab =~ "usuarios.json"
    assert rendered_tab =~ "10"
  end

  test "navigates to the raw text file tab and displays content", %{conn: conn, report: report} do
    # Mounts the history detail LiveView
    {:ok, view, _html} = live(conn, "/history/#{report.id}")

    # Clicks the raw text tab
    rendered_tab =
      view
      |> element("button", "Archivo Texto")
      |> render_click()

    assert rendered_tab =~ "Contenido real del reporte de texto plano"
  end

  test "redirects to the history index when clicking the back button", %{conn: conn, report: report} do
    # Mounts the history detail LiveView
    {:ok, view, _html} = live(conn, "/history/#{report.id}")

    # Clicks the back button
    view
    |> element("a", "Volver al Historial")
    |> render_click()

    # Asserts the redirection to the main history page
    assert_redirect(view, "/history")
  end
end
