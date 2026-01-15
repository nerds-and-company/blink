# Blink

Blink is a fast bulk data insertion library for Ecto and PostgreSQL.

It provides a callback-based pattern for seeding databases with dependent tables and shared context. Designed for scenarios where you need to insert test data, seed development databases, or populate staging environments quickly.

## Installation

Add `blink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:blink, "~> 0.4.0"}
  ]
end
```

Then run `mix deps.get` to install it.

## Example

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> with_table("posts")
    |> run(MyApp.Repo)
  end

  def table(_seeder, "users") do
    for i <- 1..1000 do
      %{
        id: i,
        name: "User #{i}",
        email: "user#{i}@example.com",
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end
  end

  def table(seeder, "posts") do
    users = seeder.tables["users"]

    Enum.flat_map(users, fn user ->
      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i}",
          user_id: user.id,
          inserted_at: ~U[2024-01-01 00:00:00Z],
          updated_at: ~U[2024-01-01 00:00:00Z]
        }
      end
    end)
  end
end

# Inserts 1,000 users and 5,000 posts
MyApp.Seeder.call()
```

## Features

- **Fast bulk inserts** - Uses PostgreSQL's `COPY FROM STDIN` command for optimal performance
- **Dependent tables** - Insert tables in order with access to previously inserted data
- **Shared context** - Compute expensive operations once and share across tables
- **File loading** - Built-in helpers for CSV and JSON file imports
- **Configurable batching** - Adjust batch sizes for memory-efficient large dataset insertion
- **Transaction support** - Automatic rollback on errors

## Usage

Blink uses a callback-based pattern where you define:

- Which tables to insert (via `with_table/2`)
- What data goes in each table (via `table/2` callback)
- Optional shared context (via `with_context/2` and `context/2` callback)

### Using Data from Context

Use context to compute expensive operations once and share across all tables:

```elixir
def call do
  new()
  |> with_context("timestamps")
  |> with_table("users")
  |> with_table("posts")
  |> run(MyApp.Repo)
end

def context(_seeder, "timestamps") do
  base = ~U[2024-01-01 00:00:00Z]
  for day <- 0..29, do: DateTime.add(base, day, :day)
end

def table(seeder, "users") do
  timestamps = seeder.context["timestamps"]
  # Use shared timestamps...
end

def table(seeder, "posts") do
  timestamps = seeder.context["timestamps"]
  # Reuse same timestamps...
end
```

### Loading from Files

Load data from CSV or JSON files:

```elixir
def table(_seeder, "users") do
  from_csv("priv/seed_data/users.csv",
    transform: fn row ->
      row
      |> Map.update!("id", &String.to_integer/1)
      |> Map.put("inserted_at", ~U[2024-01-01 00:00:00Z])
      |> Map.put("updated_at", ~U[2024-01-01 00:00:00Z])
    end
  )
end

def table(_seeder, "products") do
  from_json("priv/seed_data/products.json",
    transform: fn product ->
      Map.put(product, "inserted_at", ~U[2024-01-01 00:00:00Z])
    end
  )
end
```

CSV files use the first row as headers by default. Both helpers accept a `:transform` option for type conversion or data manipulation.

### Configuring Batch Size

Adjust batch size:

```elixir
new()
|> with_table("users")
|> run(MyApp.Repo, batch_size: 5_000)  # Default: 900
```

Or disable batching:

```elixir
new()
|> with_table("users")
|> run(MyApp.Repo, batch_size: :infinity)
```

### Using with ExMachina

Combine ExMachina's factory pattern with Blink's fast insertion:

```elixir
defmodule MyApp.Seeder do
  use Blink
  import MyApp.Factory

  def call do
    new()
    |> with_table("users")
    |> with_table("posts")
    |> run(MyApp.Repo)
  end

  def table(_seeder, "users") do
    for _i <- 1..100 do
      user = build(:user)
      Map.put(user, :id, Ecto.UUID.generate())
    end
  end

  def table(seeder, "posts") do
    user_ids = Enum.map(seeder.tables["users"], & &1.id)

    Enum.flat_map(user_ids, fn user_id ->
      for _i <- 1..5 do
        post = build(:post, user_id: user_id)
        Map.put(post, :id, Ecto.UUID.generate())
      end
    end)
  end
end
```

## Requirements

| Requirement | Version               |
| ----------- | --------------------- |
| Elixir      | 1.15+                 |
| Ecto        | 3.0+                  |
| PostgreSQL  | Any supported version |

## Known Limitations

**Memory usage with large datasets** - Blink loads all table data into memory before insertion. For very large datasets, consider splitting your seeder into multiple modules:

```elixir
# Instead of one large seeder, use multiple smaller ones
organization_ids = OrganizationSeeder.call()
user_ids = UserSeeder.call(organization_ids)
PostSeeder.call(user_ids)
```

This limitation may be addressed in a future version.

## License

Copyright (c) 2026 Nerds and Company

Licensed under the MIT License. See [LICENSE](LICENSE) for details.
