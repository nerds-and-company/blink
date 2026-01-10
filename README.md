# Blink

Blink is a fast bulk data insertion library for Ecto and PostgreSQL.

It provides a callback-based pattern for seeding databases with dependent tables and shared context. Designed for scenarios where you need to insert test data, seed development databases, or populate staging environments quickly.

## Installation

Add `blink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:blink, "~> 0.2.0"}
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
    |> add_table("users")
    |> add_table("posts")
    |> insert(MyApp.Repo)
  end

  def table(_store, "users") do
    for i <- 1..1000 do
      %{
        id: i,
        name: "User #{i}",
        email: "user#{i}@example.com",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    end
  end

  def table(store, "posts") do
    users = store.tables["users"]

    Enum.flat_map(users, fn user ->
      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i}",
          user_id: user.id,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
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
- Which tables to insert (via `add_table/2`)
- What data goes in each table (via `table/2` callback)
- Optional shared context (via `add_context/2` and `context/2` callback)

### Accessing Previously Inserted Tables

Tables are inserted in the order they're added. Access previous table data via `store.tables`:

```elixir
def table(store, "posts") do
  users = store.tables["users"]  # Access users inserted earlier

  Enum.flat_map(users, fn user ->
    for i <- 1..3 do
      %{
        id: (user.id - 1) * 3 + i,
        title: "Post #{i}",
        user_id: user.id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    end
  end)
end
```

### Using Data from Context

Use context to compute expensive operations once and share across all tables:

```elixir
def call do
  new()
  |> add_context("timestamps")
  |> add_table("users")
  |> add_table("posts")
  |> insert(MyApp.Repo)
end

def context(_store, "timestamps") do
  base = ~U[2024-01-01 00:00:00Z]
  for day <- 0..29, do: DateTime.add(base, day, :day)
end

def table(store, "users") do
  timestamps = store.context["timestamps"]
  # Use shared timestamps...
end

def table(store, "posts") do
  timestamps = store.context["timestamps"]
  # Reuse same timestamps...
end
```

### Loading from Files

Load data from CSV or JSON files:

```elixir
def table(_store, "users") do
  Blink.from_csv("priv/seed_data/users.csv",
    transform: fn row ->
      row
      |> Map.update!("id", &String.to_integer/1)
      |> Map.put("inserted_at", DateTime.utc_now())
      |> Map.put("updated_at", DateTime.utc_now())
    end
  )
end

def table(_store, "products") do
  Blink.from_json("priv/seed_data/products.json",
    transform: fn product ->
      Map.put(product, "inserted_at", DateTime.utc_now())
    end
  )
end
```

CSV files use the first row as headers by default. Both helpers accept a `:transform` option for type conversion or data manipulation.

### Configuring Batch Size

Adjust batch size for large datasets:

```elixir
new()
|> add_table("users")
|> insert(MyApp.Repo, batch_size: 5_000)  # Default: 900
```

### Using with ExMachina

Combine ExMachina's factory pattern with Blink's fast insertion:

```elixir
defmodule MyApp.Seeder do
  use Blink
  import MyApp.Factory

  def call do
    new()
    |> add_table("users")
    |> add_table("posts")
    |> insert(MyApp.Repo)
  end

  def table(_store, "users") do
    for _i <- 1..100 do
      user = build(:user)
      Map.put(user, :id, Ecto.UUID.generate())
    end
  end

  def table(store, "posts") do
    user_ids = Enum.map(store.tables["users"], & &1.id)

    Enum.flat_map(user_ids, fn user_id ->
      for _i <- 1..5 do
        post = build(:post, user_id: user_id)
        Map.put(post, :id, Ecto.UUID.generate())
      end
    end)
  end
end
```

## Learning Blink

- [Getting Started guide](https://hexdocs.pm/blink/getting-started.html) - Step-by-step tutorial building a complete seeding system
- [Custom Adapters guide](https://hexdocs.pm/blink/custom-adapters.html) - Create adapters for MySQL, SQL Server, or custom implementations
- [API documentation](https://hexdocs.pm/blink) - Full reference for all functions and callbacks
- [Changelog](CHANGELOG.md) - Version history and migration guides

## Requirements

| Requirement | Version |
|-------------|---------|
| Elixir | 1.15+ |
| Ecto | 3.0+ |
| PostgreSQL | Any supported version |

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
