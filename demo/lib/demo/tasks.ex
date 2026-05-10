defmodule Demo.Tasks do
  @moduledoc """
  The Tasks context.
  """

  import Ecto.Query, warn: false
  alias Demo.Repo

  alias Demo.Tasks.Task
  alias Demo.Tasks.TaskAssignee

  @doc """
  Returns the list of tasks with preloaded associations.
  """
  def list_tasks do
    Task
    |> preload([:project, :assignees])
    |> Repo.all()
  end

  @doc """
  Returns tasks from a custom query with preloaded associations.
  """
  def list_tasks(query) do
    query
    |> preload([:project, :assignees])
    |> Repo.all()
  end

  @doc """
  Gets a single task with preloaded associations.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task!(id) do
    Task
    |> preload([:project, :assignees])
    |> Repo.get!(id)
  end

  @doc """
  Creates a task.
  """
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a task with assignees.
  """
  def create_task_with_assignees(attrs, assignee_ids) do
    Repo.transaction(fn ->
      case create_task(attrs) do
        {:ok, task} -> insert_assignees(task, assignee_ids)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp insert_assignees(task, assignee_ids) do
    Enum.each(assignee_ids, &insert_task_assignee(task.id, &1))
    Repo.preload(task, [:project, :assignees])
  end

  defp insert_task_assignee(task_id, assignee_id) do
    %TaskAssignee{}
    |> TaskAssignee.changeset(%{task_id: task_id, assignee_id: assignee_id})
    |> Repo.insert!()
  end

  @doc """
  Updates a task.
  """
  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task.
  """
  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end
end
