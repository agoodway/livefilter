defmodule Demo.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :description, :string
    field :color, :string

    has_many :tasks, Demo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :color])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
