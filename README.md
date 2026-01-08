# Blink

Fast bulk data insertion for Ecto using PostgreSQL's COPY command.

Blink provides a callback-based pattern for seeding databases with dependent tables and shared context. It's designed for scenarios where you need to insert large amounts of test data, seed development databases, or populate staging environments quickly.

## Features

- **Fast bulk inserts** using PostgreSQL's `COPY FROM STDIN` command
- **Callback-based pattern** for defining seeders with dependent tables
- **Context sharing** between table definitions for managing relationships
- **Configurable batch sizes** for memory-efficient large dataset insertion
- **Transaction support** with automatic rollback on errors
- **Overridable functions** for custom insertion logic

## Installation

Add `blink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:blink, "~> 0.1.0"}
  ]
end
```

## Usage

### Basic Example

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
    [
      %{id: 1, name: "Alice", email: "alice@example.com"},
      %{id: 2, name: "Bob", email: "bob@example.com"}
    ]
  end

  def table(_store, "posts") do
    [
      %{id: 1, title: "First Post", body: "Hello world", user_id: 1},
      %{id: 2, title: "Second Post", body: "Another post", user_id: 2}
    ]
  end
end

# Run the seeder
MyApp.Seeder.call()
```

### Using Context for Shared Data

Context allows you to share computed data between table definitions:

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> add_context("timestamps")
    |> add_table("users")
    |> add_table("posts")
    |> insert(MyApp.Repo)
  end

  def context(_store, "timestamps") do
    # Generate timestamps for 30 days
    base = ~U[2024-01-01 00:00:00Z]
    for day <- 0..29, do: DateTime.add(base, day, :day)
  end

  def table(store, "users") do
    timestamps = store.context["timestamps"]

    Enum.with_index(timestamps, 1)
    |> Enum.map(fn {timestamp, id} ->
      %{
        id: id,
        name: "User #{id}",
        email: "user#{id}@example.com",
        inserted_at: timestamp
      }
    end)
  end

  def table(store, "posts") do
    users = store.tables["users"]

    Enum.flat_map(users, fn user ->
      # Get timestamps after the user's creation time
      later_timestamps =
        store.context["timestamps"]
        |> Enum.filter(&(DateTime.compare(&1, user.inserted_at) == :gt))

      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i} by User #{user.id}",
          body: "Content here",
          user_id: user.id,
          inserted_at: Enum.random(later_timestamps)
        }
      end
    end)
  end
end
```

### Loading Data from CSV Files

Blink provides a `from_csv/2` helper function to easily load data from CSV files:

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> add_table("products")
    |> add_table("users")
    |> insert(MyApp.Repo)
  end

  def table(_store, "products") do
    Blink.from_csv("priv/seed_data/products.csv")
  end

  def table(_store, "users") do
    # With custom transformation for type conversion
    Blink.from_csv("priv/seed_data/users.csv",
      transform: fn row ->
        Map.update!(row, "age", &String.to_integer/1)
      end
    )
  end
end
```

By default, the first row is treated as headers. You can also provide explicit headers using the `:headers` option for CSV files without a header row. Column headers become string keys in the maps, and all values are returned as strings. Use the `:transform` option to convert types or transform keys as needed.

### Loading Data from JSON Files

Blink also provides a `from_json/2` helper function to load data from JSON files:

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> add_table("users")
    |> insert(MyApp.Repo)
  end

  def table(_store, "users") do
    # Simple usage
    Blink.from_json("priv/seed_data/users.json")
  end
end
```

The JSON file must contain an array of objects at the root level. Use the `:transform` option to modify the data as needed.

### Custom Batch Size

For the insert operation you can configure the batch size:

```elixir
def call do
  new()
  |> add_table("users")
  |> insert(MyApp.Repo, batch_size: 5_000)
end
```

The batch size corresponds with a number of rows. The default batch size is 900 rows.

### Integration with ExMachina

Blink works seamlessly with ExMachina for generating realistic test data. ExMachina handles the data generation (realistic names, emails, timestamps, etc.), while Blink handles the fast bulk insertion.

**Why combine them?**

- **ExMachina**: Provides factories with realistic, randomized data and handles associations elegantly
- **Blink**: Provides fast bulk insertion via PostgreSQL's COPY command

**Example with UUIDs:**

```elixir
defmodule MyApp.Seeder do
  use Blink
  import MyApp.Factory

  def call do
    new()
    |> add_table("organizations")
    |> add_table("users")
    |> add_table("posts")
    |> insert(MyApp.Repo, batch_size: 1_000)
  end

  def table(_store, "organizations") do
    for _i <- 1..10 do
      org = build(:organization)
      Map.put(org, :id, Ecto.UUID.generate())
    end
  end

  def table(store, "users") do
    organization_ids =
      store.tables["organizations"]
      |> Enum.map(& &1.id)

    Enum.flat_map(organization_ids, fn org_id ->
      for _i <- 1..50 do
        user = build(:user, organization_id: org_id)
        Map.put(user, :id, Ecto.UUID.generate())
      end
    end)
  end

  def table(store, "posts") do
    user_ids =
      store.tables["users"]
      |> Enum.map(& &1.id)

    Enum.flat_map(user_ids, fn user_id ->
      for _i <- 1..5 do
        post = build(:post, user_id: user_id)
        Map.put(post, :id, Ecto.UUID.generate())
      end
    end)
  end
end

# Seeds 10 organizations, 500 users, and 2,500 posts
MyApp.Seeder.call()
```

## API Reference

### Functions

- `new/0` - Creates a new empty Store
- `add_table/2` - Adds a table to be seeded (tables are inserted in order)
- `add_context/2` - Adds a context key for sharing computed data
- `insert/2` - Inserts all tables into the repository
- `insert/3` - Inserts with options (e.g., `batch_size`)
- `copy_to_table/4` - Low-level function for copying data to a single table
- `from_csv/2` - Reads a CSV file and returns a list of maps for use in `table/2` callbacks

### Callbacks

- `table/2` - Implement to provide data for each table
- `context/2` - Implement to provide shared context data

## Requirements

- PostgreSQL database
- Ecto 3.0 or later
- Elixir 1.14 or later

## Known Limitations

### Memory Usage with Large Datasets

When seeding very large datasets, Blink loads all table data into memory before insertion. This can cause memory spikes.

**Workaround strategy:**

Instead of one large seeder, create separate seeders for independent data sets and run them sequentially, passing IDs between calls:

   ```elixir
   # Seed organizations first, return IDs
   organization_ids = MyApp.OrganizationSeeder.call()

   # Then seed users with organization IDs, return user IDs
   user_ids = MyApp.UserSeeder.call(organization_ids)

   # Finally seed posts with user IDs
   MyApp.PostSeeder.call(user_ids)
   ```

This limitation may be addressed in future version, allowing all seeds to be in one seeder module: `MyApp.Seeder.call()`.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Links

- [Documentation](https://hexdocs.pm/blink)
- [GitHub](https://github.com/nerds-and-company/blink)
- [Changelog](CHANGELOG.md)
