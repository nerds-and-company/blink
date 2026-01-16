# Getting Started

This guide is an introduction to Blink, a fast bulk data insertion library for Ecto and PostgreSQL.

In this guide, we will:

- Create a seeder module for inserting users and posts
- Learn how to reference data from previously declared tables
- Use streams for memory-efficient seeding
- Store auxiliary data in context without inserting it into the database

## Adding Blink to an application

Add Blink to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:blink, "~> 0.4.0"}
  ]
end
```

Install the dependencies:

```bash
mix deps.get
```

## Configuring the repository

Blink works with any Ecto repository. If you don't have Ecto set up yet, follow the [Ecto Getting Started guide](https://hexdocs.pm/ecto/getting-started.html) to configure your repository and create your database tables.

For this guide, we'll assume you have:

- An Ecto repository (e.g., `Blog.Repo`) configured
- A `users` table with columns: `id`, `name`, `email`, `inserted_at`, `updated_at`
- A `posts` table with columns: `id`, `title`, `body`, `user_id`, `inserted_at`, `updated_at`

## Creating a seeder

Now that we have our database set up, let's create a seeder module to insert data:

```elixir
defmodule Blog.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> with_table("posts")
    |> run(Blog.Repo)
  end

  def table(_seeder, "users") do
    [
      %{id: 1, name: "Alice", email: "alice@example.com"},
      %{id: 2, name: "Bob", email: "bob@example.com"},
    ]
  end

  def table(seeder, "posts") do
    IO.inspect(seeder)
    # %Blink.Seeder{
    #   tables: %{"users" => [%{id: 1, name: "Alice", ...}, ...]},
    #   ...
    # }

    Enum.flat_map(seeder.tables["users"], fn user ->
      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i} by #{user.name}",
          body: "This is the content of post #{i} by #{user.name}",
          user_id: user.id,
          inserted_at: ~U[2024-01-01 00:00:00Z],
          updated_at: ~U[2024-01-01 00:00:00Z]
        }
      end
    end)
  end
end
```

The seeder above does the following:

1. `use Blink` - Injects Blink's functions and defines required callbacks
2. `new()` - Creates an empty Seeder struct
3. `with_table/2` - Declares the tables to insert rows into
4. `table/2` - Defines what rows to insert into each table
5. `run/2` - Executes the bulk insertion

Each `table/2` callback receives a Seeder struct. The `tables` field stores data from previously declared tables, allowing the `"posts"` callback to reference `seeder.tables["users"]`. Tables are inserted in declaration order. The `context` field is covered below.

Let's run it from IEx:

```elixir
iex -S mix
iex> Blog.Seeder.call()
# => Inserts 2 users and 10 posts
``` 

## Streams

The `table/2` callback can also return a stream for memory-efficient seeding of large datasets:

```elixir
def table(_seeder, "users") do
  Stream.map(1..1_000_000, fn i ->
    %{
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      inserted_at: ~U[2024-01-01 00:00:00Z],
      updated_at: ~U[2024-01-01 00:00:00Z]
    }
  end)
end

def table(seeder, "posts") do
  Stream.flat_map(seeder.tables["users"], fn user ->
    Stream.map(1..20, fn i ->
      %{
        id: (user.id - 1) * 20 + i,
        title: "Post #{i} by #{user.name}",
        body: "This is the content of post #{i}",
        user_id: user.id,
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end)
  end)
end
```

Streams are processed lazily by `run/2`—no extra configuration needed—so they're recommended for large datasets to keep memory usage low.

## Using context

Sometimes you need to compute data once and share it across multiple tables. Context data is not inserted into the database but is available when building your table data.

In this example, we generate timestamps once and reuse them across tables, ensuring posts are created after their author.

```elixir
def call do
  new()
  |> with_context("timestamps")
  |> with_table("users")
  |> with_table("posts")
  |> run(Blog.Repo)
end

def context(_seeder, "timestamps") do
  base = ~U[2024-01-01 00:00:00Z]
  for day <- 0..29, do: DateTime.add(base, day, :day)
end

def table(seeder, "users") do
  timestamps = seeder.context["timestamps"]

  for i <- 1..100 do
    %{
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      inserted_at: Enum.random(timestamps),
      updated_at: Enum.random(timestamps)
    }
  end
end

def table(seeder, "posts") do
  users = seeder.tables["users"]
  timestamps = seeder.context["timestamps"]

  Enum.flat_map(users, fn user ->
    # Only use timestamps after the user was created
    valid_timestamps =
      Enum.filter(timestamps, fn ts ->
        DateTime.compare(ts, user.inserted_at) == :gt
      end)

    for i <- 1..5 do
      %{
        id: (user.id - 1) * 5 + i,
        title: "Post #{i}",
        body: "Content here",
        user_id: user.id,
        inserted_at: Enum.random(valid_timestamps),
        updated_at: Enum.random(valid_timestamps)
      }
    end
  end)
end
```

## Summary

In this guide, we learned how to:

- Create a seeder module with `use Blink`
- Reference data from previously declared tables via `seeder.tables`
- Use streams for memory-efficient seeding of large datasets
- Store auxiliary data in context without inserting it into the database

## Next steps

You might also find these guides useful:

- [Loading Data from Files](loading_data_from_files.html) - Learn how to load data from CSV and JSON files
- [Integrating with ExMachina](integrating_with_ex_machina.html) - Generate realistic test data
