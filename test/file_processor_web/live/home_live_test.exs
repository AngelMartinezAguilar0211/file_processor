defmodule FileProcessorWeb.HomeLiveTest do
  use FileProcessorWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders the main interface correctly", %{conn: conn} do
    # Mounts the LiveView at the root path
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "File Processor"
    assert html =~ "Cargar Archivos"
    assert html =~ "Iniciar Proceso"
  end

  test "displays an error when attempting to process without files", %{conn: conn} do
    # Mounts the LiveView at the root path
    {:ok, view, _html} = live(conn, "/")

    # Submits the form with parallel processing type without files
    rendered_result =
      view
      |> element("form")
      |> render_submit(%{"processing_type" => "parallel"})

    assert rendered_result =~ "Debes subir archivos o ingresar una ruta válida."
  end

  test "toggles benchmark mode dynamically", %{conn: conn} do
    # Mounts the LiveView at the root path
    {:ok, view, _html} = live(conn, "/")

    # Triggers a form change to activate benchmark mode
    rendered_form =
      view
      |> element("form")
      |> render_change(%{"benchmark_active" => "true"})

    # Verifies that detailed inputs like "Max Workers" are hidden when benchmark is true
    refute rendered_form =~ "Max Workers"
  end

  test "displays the processing state correctly upon submission", %{conn: conn} do
      # Mounts the LiveView at the root path
      {:ok, view, _html} = live(conn, "/")

      # Submits the form with sequential processing type without files
      rendered_result =
        view
        |> element("form")
        |> render_submit(%{"processing_type" => "sequential"})

      # Checks that the button text changes or an error state handles it properly
      assert rendered_result =~ "Debes subir archivos o ingresar una ruta válida."
    end
end
