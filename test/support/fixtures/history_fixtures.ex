defmodule FileProcessor.HistoryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FileProcessor.History` context.
  """

  @doc """
  Generate a report.
  """
  def report_fixture(attrs \\ %{}) do
    {:ok, report} =
      attrs
      |> Enum.into(%{
        data: %{},
        execution_time_ms: 120.5,
        mode: "some mode",
        success_rate: 120.5,
        total_files: 42
      })
      |> FileProcessor.History.create_report()

    report
  end
end
