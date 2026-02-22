defmodule FileProcessor.History do
  import Ecto.Query, warn: false
  alias FileProcessor.Repo
  alias FileProcessor.History.Report

  def create_report(attrs \\ %{}) do
    %Report{}
    |> Report.changeset(attrs)
    |> Repo.insert()
  end

  def list_reports do
    Repo.all(from r in Report, order_by: [desc: r.inserted_at])
  end

  def get_report!(id), do: Repo.get!(Report, id)
end
