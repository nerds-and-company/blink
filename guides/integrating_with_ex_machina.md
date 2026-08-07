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
seeder boundary:

```elixir
defmodule Shop.Seeder do
  use Blink
  import Shop.Factory

  def call do
    new()
    |> with_table("products")
    |> run(Shop.Repo, reset_sequences: true)
  end

  def table(_seeder, "products") do
    for id <- 1..200, do: to_row(build(:product), id)
  end

  # Take only schema fields: COPY derives its column list from the map keys,
  # so an association or virtual field would otherwise be sent as a column.
  defp to_row(struct, id \\ :auto) do
    row =
      struct
      |> Map.from_struct()
      |> Map.take(struct.__struct__.__schema__(:fields))

    case id do
      :auto -> Map.delete(row, :id)
      id -> Map.put(row, :id, id)
    end
  end
end
```

What each step does:

  * `Map.from_struct/1` drops `__struct__` but keeps everything else —
    `__meta__`, unloaded associations, virtual fields.
  * `Map.take(__schema__(:fields))` keeps only the persisted fields. This is
    the load-bearing step: Blink reads the column list from the map keys, so
    any stray key becomes a column in the COPY statement. It also
    future-proofs the seeder — an association added to the schema later
    cannot leak in.
  * The `id` policy is yours. Passing an explicit id keeps the row
    referenceable by later tables (pair it with `reset_sequences: true` so
    the sequence clears the seeded ids). `:auto` deletes the key instead, so
    the column is omitted from the COPY entirely and the database assigns ids
    from the sequence — no reset needed, but no stable id to reference
    either.

Values inside the struct need no special treatment: `Ecto.Enum` atoms,
calendar structs, and embedded maps are all encoded by the adapter (see the
notes on `Blink.Adapter.Postgres.call/4`).

### Letting database defaults apply

A struct materializes *every* schema field, mostly as `nil` — and COPY sends
an explicit `NULL` where `Repo.insert/2` would have omitted the field and let
the database default apply. If your schema relies on database defaults, drop
the columns that are nil in every row:

```elixir
# Mirror Repo.insert on a bare struct, which omits nil fields (database
# defaults apply). Dropping per-table rather than per-row keeps all rows on
# the same keys, which Blink requires.
defp drop_all_nil_columns([]), do: []

defp drop_all_nil_columns([first | _] = rows) do
  all_nil =
    Enum.filter(Map.keys(first), fn key -> Enum.all?(rows, &is_nil(Map.get(&1, key))) end)

  Enum.map(rows, &Map.drop(&1, all_nil))
end
```

The whole-table shape is deliberate: rows must all have the same keys — a row
that dropped its nils individually would raise `Blink.RowError`.

## Summary

- Factories dedicated to seeding: return plain maps, merge in IDs and
  timestamps, done.
- Factories shared with the test suite: keep them returning structs and
  convert at the boundary with `to_row/2`, adding `drop_all_nil_columns/1`
  when the schema leans on database defaults.

For more information:

- [Building Rows](building_rows.html)
- [ExMachina documentation](https://hexdocs.pm/ex_machina/)
