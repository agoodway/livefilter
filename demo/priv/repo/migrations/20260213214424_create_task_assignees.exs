defmodule Demo.Repo.Migrations.CreateTaskAssignees do
  use Ecto.Migration

  def change do
    create table(:task_assignees) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :assignee_id, references(:assignees, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:task_assignees, [:task_id, :assignee_id])
    create index(:task_assignees, [:assignee_id])
  end
end
