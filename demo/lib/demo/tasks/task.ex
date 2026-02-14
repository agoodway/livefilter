defmodule Demo.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string
    field :urgent, :boolean, default: false
    field :tags, {:array, :string}, default: []
    field :due_date, :date
    field :estimated_hours, :float
    field :deleted_at, :utc_datetime

    belongs_to :project, Demo.Projects.Project
    many_to_many :assignees, Demo.Assignees.Assignee, join_through: Demo.Tasks.TaskAssignee

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :status,
      :urgent,
      :tags,
      :due_date,
      :estimated_hours,
      :project_id,
      :deleted_at
    ])
    |> validate_required([:title, :status, :project_id])
    |> foreign_key_constraint(:project_id)
  end
end
