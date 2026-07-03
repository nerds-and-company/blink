defmodule BlinkTest.Repo.Migrations.CreateArrayRecords do
  use Ecto.Migration

  def change do
    create table(:array_records, primary_key: false) do
      add :id, :integer, primary_key: true
      add :ints, {:array, :integer}
      add :strings, {:array, :string}
      add :docs, {:array, :map}
      add :matrix, {:array, {:array, :integer}}
    end
  end
end
