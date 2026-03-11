defmodule FileProcessor.Repo.Migrations.CreateReportsTable do
  use Ecto.Migration

  def change do
    # Creates the reports table with necessary schema fields
    create table(:reports) do
      add :data, :map
      add :execution_time_ms, :float
      add :mode, :string
      add :success_rate, :float
      add :total_files, :integer

      timestamps()
    end
  end
end
