defmodule FileProcessor.HistoryTest do
  use FileProcessor.DataCase

  alias FileProcessor.History
  alias FileProcessor.History.Report

  describe "reports" do
    @valid_attrs %{
      mode: "secuencial",
      total_files: 8,
      success_rate: 75.0,
      execution_time_ms: 32.2,
      data: %{
        "texto_completo" => "Reporte guardado",
        "nombre_reporte_original" => "ventas_mensuales.txt"
      }
    }

    @invalid_attrs %{
      mode: nil,
      total_files: nil,
      success_rate: nil,
      execution_time_ms: nil,
      data: nil
    }

    def report_fixture(attrs \\ %{}) do
      {:ok, report} =
        attrs
        |> Enum.into(@valid_attrs)
        |> History.create_report()

      report
    end

    test "list_reports/0 devuelve todos los reportes" do
      report = report_fixture()

      reports = History.list_reports()

      assert Enum.any?(reports, fn r -> r.id == report.id end)
    end

    test "get_report!/1 devuelve el reporte con el ID dado" do
      report = report_fixture()

      found_report = History.get_report!(report.id)

      assert found_report.id == report.id
      assert found_report.mode == report.mode
    end

    test "create_report/1 con datos válidos crea un reporte" do
      assert {:ok, %Report{} = report} = History.create_report(@valid_attrs)

      assert report.mode == "secuencial"
      assert report.total_files == 8
      assert report.success_rate == 75.0
      assert report.execution_time_ms == 32.2
      assert report.data["texto_completo"] == "Reporte guardado"
    end

    test "create_report/1 con datos inválidos devuelve un error (changeset)" do
      assert {:error, %Ecto.Changeset{}} = History.create_report(@invalid_attrs)
    end
  end
end
