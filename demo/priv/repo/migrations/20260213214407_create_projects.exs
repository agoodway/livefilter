defmodule Demo.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :description, :text
      add :color, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name])
  end
end
