defmodule BlinkTest.Repo.Migrations.CreateTestTables do
  use Ecto.Migration

  def change do
    # Manual integer primary keys allow tests to use explicit IDs for
    # predictable assertions and controlled foreign key relationships.
    create table(:users, primary_key: false) do
      add :id, :integer, primary_key: true
      add :name, :string
      add :email, :string
      add :settings, :map
    end

    create table(:posts, primary_key: false) do
      add :id, :integer, primary_key: true
      add :title, :string
      add :body, :text
      add :user_id, references(:users, type: :integer, on_delete: :nothing), null: false
    end
  end
end
