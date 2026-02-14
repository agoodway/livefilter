defmodule Demo.Assignees.Assignee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "assignees" do
    field :name, :string
    field :email, :string
    field :avatar_url, :string

    many_to_many :tasks, Demo.Tasks.Task, join_through: Demo.Tasks.TaskAssignee

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(assignee, attrs) do
    assignee
    |> cast(attrs, [:name, :email, :avatar_url])
    |> validate_required([:name, :email])
    |> unique_constraint(:email)
  end
end
