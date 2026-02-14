defmodule Demo.Repo.Migrations.CreateAssignees do
  use Ecto.Migration

  def change do
    create table(:assignees) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assignees, [:email])
  end
end
