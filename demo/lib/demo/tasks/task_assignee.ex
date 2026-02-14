defmodule Demo.Tasks.TaskAssignee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_assignees" do
    belongs_to :task, Demo.Tasks.Task
    belongs_to :assignee, Demo.Assignees.Assignee

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task_assignee, attrs) do
    task_assignee
    |> cast(attrs, [:task_id, :assignee_id])
    |> validate_required([:task_id, :assignee_id])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:assignee_id)
    |> unique_constraint([:task_id, :assignee_id])
  end
end
