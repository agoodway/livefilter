defmodule Demo.Projects do
  @moduledoc """
  The Projects context.
  """

  import Ecto.Query, warn: false
  alias Demo.Repo

  alias Demo.Projects.Project

  @doc """
  Returns the list of projects.
  """
  def list_projects do
    Repo.all(from p in Project, order_by: p.name)
  end

  @doc """
  Returns projects as options for select inputs.
  """
  def project_options do
    list_projects()
    |> Enum.map(fn p -> {p.name, p.id} end)
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Creates a project.
  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end
end
