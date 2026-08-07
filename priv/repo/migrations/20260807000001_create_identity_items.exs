defmodule BlinkTest.Repo.Migrations.CreateIdentityItems do
  use Ecto.Migration

  def change do
    # An identity (rather than serial) primary key proves reset_sequences
    # handles both sequence flavors.
    create table(:identity_items, primary_key: false) do
      add(:id, :identity, primary_key: true)
      add(:position, :integer)
    end
  end
end
