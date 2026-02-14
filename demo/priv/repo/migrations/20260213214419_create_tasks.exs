defmodule Demo.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false
      add :urgent, :boolean, default: false, null: false
      add :tags, {:array, :string}, default: []
      add :due_date, :date
      add :estimated_hours, :float
      add :deleted_at, :utc_datetime
      add :project_id, references(:projects, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:status])
    create index(:tasks, [:urgent])
  end
end
