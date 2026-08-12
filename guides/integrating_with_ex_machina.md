# Integrating with ExMachina

ExMachina is a popular library for generating data in Elixir. Blink works
well with it, combining ExMachina's expressive factories with Blink's bulk
insertion. There are two ways to pair them, and which one you want depends on
whether the factories exist for seeding alone or are shared with your test
suite.

## Setting up ExMachina

Add ExMachina to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:ex_machina, "~> 2.7", only: [:dev, :test]}
  ]
end
```

Note: To use `Faker` in the examples below, add
`{:faker, "~> 0.18", only: [:dev, :test]}` as well.

## Map factories: the simple pairing

When the factories exist for seeding, make them return plain maps — the maps
*are* the rows, and nothing needs converting (see
[Building Rows](building_rows.html) for why plain maps are the recommended
shape):

```elixir
defmodule Blog.Factory do
  use ExMachina

  def user_factory do
    %{
      name: Faker.Person.name(),
      email: Faker.Internet.email()
    }
  end
end
```

```elixir
defmodule Blog.Seeder do
  use Blink
  import Blog.Factory

  def call do
    new()
    |> with_table("users")
    |> run(Blog.Repo)
  end

  @impl true
  def table(_seeder, "users") do
    for _ <- 1..1000 do
      Map.merge(build(:user), %{
        id: Ecto.UUID.generate(),
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      })
    end
  end
end
```

ExMachina generates the variable data; you control the IDs and timestamps.
Generating the ID with `Ecto.UUID.generate/0` rather than letting the
database assign one is what makes the value usable straight away — a later
table can reference it before anything is inserted, and a `uuid` primary key
has no sequence to reset. See
[Choosing IDs](getting_started.html#choosing-ids).

## Struct factories: sharing with the test suite

A factory that your tests already use is a different situation. An
`ExMachina.Ecto` factory returns schema structs, and rewriting it as a map
factory would fork the definition — the test factory and the seed factory
would drift apart. Keep the shared factory, and convert its structs at the
seeder boundary with `Blink.to_row/2` (imported by `use Blink`):

```elixir
defmodule Shop.Seeder do
  use Blink
  import Shop.Factory

  def call do
    new()
    |> with_table("products")
    |> run(Shop.Repo, reset_sequences: true)
  end

  @impl true
  def table(_seeder, "products") do
    for id <- 1..200, do: to_row(build(:product), id: id)
  end
end
```

Earlier versions of this guide defined `to_row/2` by hand inside the seeder.
Delete that local version when upgrading — it now conflicts with the import
(`imported Blink.to_row/2 conflicts with local function`) — and move the id
to a keyword: `to_row(struct, id: id)` instead of `to_row(struct, id)`.

`to_row/2` keeps only the schema's persisted fields. This is the load-bearing
part: `Map.from_struct/1` alone would keep `__meta__`, unloaded associations,
and virtual fields, and Blink reads the column list from the map keys, so any
stray key becomes a column in the COPY statement. It also future-proofs the
seeder — an association added to the schema later cannot leak in.

The `:id` option is the primary-key policy, and the choice is the same
explicit-vs-database trade-off as in
[Choosing IDs](getting_started.html#choosing-ids). An explicit id, as above,
keeps the row referenceable by later tables — pair it with
`reset_sequences: true` so the sequence clears the seeded ids. The default
(`id: :database`) drops the primary key instead, so the column is omitted
from the COPY entirely and the database assigns ids from the sequence — no
reset needed, but no stable id to reference either. And a factory that
assigns its own ids (`Ecto.UUID.generate/0` and the like) keeps them with
`id: :keep`.

Values inside the struct need no special treatment: `Ecto.Enum` atoms,
calendar structs, and embedded maps are all encoded by the adapter (see the
notes on `Blink.Adapter.Postgres.call/4`).

### Letting database defaults apply

A struct materializes *every* schema field, mostly as `nil` — and COPY sends
an explicit `NULL` where `Repo.insert/2` would have omitted the field and let
the database default apply. If your schema relies on database defaults,
convert the table with `Blink.to_rows/2` and drop the columns that are nil in
every row:

```elixir
@impl true
def table(_seeder, "products") do
  to_rows(build_list(200, :product), drop_nil_columns: true)
end
```

The whole-table shape is deliberate: rows must all have the same keys — a row
that dropped its nils individually would raise `Blink.RowError`.

## Summary

- Factories dedicated to seeding: return plain maps, merge in IDs and
  timestamps, done.
- Factories shared with the test suite: keep them returning structs and
  convert at the boundary with `to_row/2` or `to_rows/2`, adding
  `drop_nil_columns: true` when the schema leans on database defaults.

For more information:

- [Building Rows](building_rows.html)
- [ExMachina documentation](https://hexdocs.pm/ex_machina/)
