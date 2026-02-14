defmodule Demo.TasksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Demo.Tasks` context.
  """

  @doc """
  Generate a task.
  """
  def task_fixture(attrs \\ %{}) do
    {:ok, task} =
      attrs
      |> Enum.into(%{
        assignee_name: "some assignee_name",
        complexity: "some complexity",
        deleted_at: ~U[2026-02-12 20:42:00Z],
        description: "some description",
        due_date: ~D[2026-02-12],
        estimated_hours: 120.5,
        priority: "some priority",
        project_name: "some project_name",
        status: "some status",
        tags: ["option1", "option2"],
        title: "some title",
        urgent: true
      })
      |> Demo.Tasks.create_task()

    task
  end
end
