defmodule Demo.TasksTest do
  use Demo.DataCase

  alias Demo.Tasks

  describe "tasks" do
    alias Demo.Tasks.Task

    import Demo.TasksFixtures

    @invalid_attrs %{
      priority: nil,
      status: nil,
      description: nil,
      title: nil,
      assignee_name: nil,
      project_name: nil,
      tags: nil,
      due_date: nil,
      estimated_hours: nil,
      urgent: nil,
      complexity: nil,
      deleted_at: nil
    }

    test "list_tasks/0 returns all tasks" do
      task = task_fixture()
      assert Tasks.list_tasks() == [task]
    end

    test "get_task!/1 returns the task with given id" do
      task = task_fixture()
      assert Tasks.get_task!(task.id) == task
    end

    test "create_task/1 with valid data creates a task" do
      valid_attrs = %{
        priority: "some priority",
        status: "some status",
        description: "some description",
        title: "some title",
        assignee_name: "some assignee_name",
        project_name: "some project_name",
        tags: ["option1", "option2"],
        due_date: ~D[2026-02-12],
        estimated_hours: 120.5,
        urgent: true,
        complexity: "some complexity",
        deleted_at: ~U[2026-02-12 20:42:00Z]
      }

      assert {:ok, %Task{} = task} = Tasks.create_task(valid_attrs)
      assert task.priority == "some priority"
      assert task.status == "some status"
      assert task.description == "some description"
      assert task.title == "some title"
      assert task.assignee_name == "some assignee_name"
      assert task.project_name == "some project_name"
      assert task.tags == ["option1", "option2"]
      assert task.due_date == ~D[2026-02-12]
      assert task.estimated_hours == 120.5
      assert task.urgent == true
      assert task.complexity == "some complexity"
      assert task.deleted_at == ~U[2026-02-12 20:42:00Z]
    end

    test "create_task/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(@invalid_attrs)
    end

    test "update_task/2 with valid data updates the task" do
      task = task_fixture()

      update_attrs = %{
        priority: "some updated priority",
        status: "some updated status",
        description: "some updated description",
        title: "some updated title",
        assignee_name: "some updated assignee_name",
        project_name: "some updated project_name",
        tags: ["option1"],
        due_date: ~D[2026-02-13],
        estimated_hours: 456.7,
        urgent: false,
        complexity: "some updated complexity",
        deleted_at: ~U[2026-02-13 20:42:00Z]
      }

      assert {:ok, %Task{} = task} = Tasks.update_task(task, update_attrs)
      assert task.priority == "some updated priority"
      assert task.status == "some updated status"
      assert task.description == "some updated description"
      assert task.title == "some updated title"
      assert task.assignee_name == "some updated assignee_name"
      assert task.project_name == "some updated project_name"
      assert task.tags == ["option1"]
      assert task.due_date == ~D[2026-02-13]
      assert task.estimated_hours == 456.7
      assert task.urgent == false
      assert task.complexity == "some updated complexity"
      assert task.deleted_at == ~U[2026-02-13 20:42:00Z]
    end

    test "update_task/2 with invalid data returns error changeset" do
      task = task_fixture()
      assert {:error, %Ecto.Changeset{}} = Tasks.update_task(task, @invalid_attrs)
      assert task == Tasks.get_task!(task.id)
    end

    test "delete_task/1 deletes the task" do
      task = task_fixture()
      assert {:ok, %Task{}} = Tasks.delete_task(task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end

    test "change_task/1 returns a task changeset" do
      task = task_fixture()
      assert %Ecto.Changeset{} = Tasks.change_task(task)
    end
  end
end
