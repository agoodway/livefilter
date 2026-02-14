defmodule Demo.Assignees do
  @moduledoc """
  The Assignees context.
  """

  import Ecto.Query, warn: false
  alias Demo.Repo

  alias Demo.Assignees.Assignee

  @doc """
  Returns the list of assignees.
  """
  def list_assignees do
    Repo.all(from a in Assignee, order_by: a.name)
  end

  @doc """
  Returns assignees as options for select inputs.
  """
  def assignee_options do
    list_assignees()
    |> Enum.map(fn a -> {a.name, a.id} end)
  end

  @doc """
  Gets a single assignee.

  Raises `Ecto.NoResultsError` if the Assignee does not exist.
  """
  def get_assignee!(id), do: Repo.get!(Assignee, id)

  @doc """
  Creates an assignee.
  """
  def create_assignee(attrs \\ %{}) do
    %Assignee{}
    |> Assignee.changeset(attrs)
    |> Repo.insert()
  end
end
