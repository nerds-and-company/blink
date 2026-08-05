defmodule BlinkTest.Repo.Migrations.CreateSerialItems do
  use Ecto.Migration

  def change do
    # A serial primary key lets tests assert insertion order: Postgres assigns
    # ids in the order rows arrive, so `ORDER BY id` reveals the COPY row order.
    create table(:serial_items) do
      add(:position, :integer)
    end
  end
end
