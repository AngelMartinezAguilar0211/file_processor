defmodule FileProcessor.HistoryTest do
  use FileProcessor.DataCase

  alias FileProcessor.History

  describe "reports" do
    alias FileProcessor.History.Report

    import FileProcessor.HistoryFixtures

    @invalid_attrs %{data: nil, mode: nil, total_files: nil, success_rate: nil, execution_time_ms: nil}

    test "list_reports/0 returns all reports" do
      report = report_fixture()
      assert History.list_reports() == [report]
    end

    test "get_report!/1 returns the report with given id" do
      report = report_fixture()
      assert History.get_report!(report.id) == report
    end

    test "create_report/1 with valid data creates a report" do
      valid_attrs = %{data: %{}, mode: "some mode", total_files: 42, success_rate: 120.5, execution_time_ms: 120.5}

      assert {:ok, %Report{} = report} = History.create_report(valid_attrs)
      assert report.data == %{}
      assert report.mode == "some mode"
      assert report.total_files == 42
      assert report.success_rate == 120.5
      assert report.execution_time_ms == 120.5
    end

    test "create_report/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = History.create_report(@invalid_attrs)
    end

    test "update_report/2 with valid data updates the report" do
      report = report_fixture()
      update_attrs = %{data: %{}, mode: "some updated mode", total_files: 43, success_rate: 456.7, execution_time_ms: 456.7}

      assert {:ok, %Report{} = report} = History.update_report(report, update_attrs)
      assert report.data == %{}
      assert report.mode == "some updated mode"
      assert report.total_files == 43
      assert report.success_rate == 456.7
      assert report.execution_time_ms == 456.7
    end

    test "update_report/2 with invalid data returns error changeset" do
      report = report_fixture()
      assert {:error, %Ecto.Changeset{}} = History.update_report(report, @invalid_attrs)
      assert report == History.get_report!(report.id)
    end

    test "delete_report/1 deletes the report" do
      report = report_fixture()
      assert {:ok, %Report{}} = History.delete_report(report)
      assert_raise Ecto.NoResultsError, fn -> History.get_report!(report.id) end
    end

    test "change_report/1 returns a report changeset" do
      report = report_fixture()
      assert %Ecto.Changeset{} = History.change_report(report)
    end
  end
end
