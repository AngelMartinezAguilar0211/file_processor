defmodule FileProcessor.History.Report do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reports" do
    field :data, :map
    field :execution_time_ms, :float
    field :mode, :string
    field :success_rate, :float
    field :total_files, :integer

    timestamps()
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:mode, :total_files, :success_rate, :execution_time_ms, :data])
    |> validate_required([:mode, :total_files, :success_rate, :execution_time_ms, :data])
  end
end
