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
    {:blink, "~> 0.9.0"}
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

  @impl true
  def table(_seeder, "users") do
    [
      %{id: 1, name: "Alice", email: "alice@example.com"},
      %{id: 2, name: "Bob", email: "bob@example.com"}
    ]
  end

  def table(seeder, "posts") do
    IO.inspect(seeder)
    # %Blink.Seeder{
    #   tables: %{"users" => [%{id: 1, name: "Alice", ...}, ...]},
    #   table_order: ["users"],
    #   table_opts: %{"users" => []},
    #   context: %{}
    # }

    users = seeder.tables["users"]

    Enum.flat_map(users, fn user ->
      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i} by #{user.name}",
          body: "This is the content of post #{i}.",
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

`with_table/2` and `table/2` come as a pair: every table you declare needs a `table/2` clause matching that name. Declaring one without the other raises `Blink.MissingClauseError`, which names the table and shows the clause to add.

Each `table/2` callback receives a Seeder struct. The `tables` field stores data from previously declared tables, allowing the `"posts"` callback to reference `seeder.tables["users"]`.

Once `run/2` is called, data is inserted in the order tables were declared. The whole seed runs in one transaction, so if any table fails nothing is inserted and you can fix the data and re-run. See [Configuring Options](configuring_options.html) for how to trade that for speed on very large seeds. The `context` field is covered below.

Let's run it from IEx:

```elixir
iex -S mix
iex> Blog.Seeder.call()
# => Inserts 2 users and 10 posts
```

## Choosing IDs

You assign primary keys yourself. Blink builds plain maps and hands them to
PostgreSQL's `COPY`, so it never asks the database to generate an ID and never
reads one back.

It is easy to carry over a habit from the usual Ecto flow, where you insert a
struct without an ID and read the generated one off the result:

```elixir
# Here the database assigns the ID, so it only exists after the insert
{:ok, user} = Repo.insert(%User{name: "Alice"})
Repo.insert(%Post{title: "Hello", user_id: user.id})
```

That makes it look as though a row must be inserted before it has an ID to
reference. It does not. An ID is just another value in the map you are
building, no different from a name or a timestamp; writing it down is what
gives the row an ID, and inserting only stores what you already wrote. So the
`"posts"` clause can reference `user.id` for rows that have not been inserted
yet:

```elixir
def table(_seeder, "users") do
  [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
end

def table(seeder, "posts") do
  # Nothing has touched the database yet - these IDs are simply the ones
  # declared above, and they are the ones that will be inserted.
  Enum.map(seeder.tables["users"], fn user ->
    %{id: user.id, title: "Welcome, #{user.name}", user_id: user.id}
  end)
end
```

Any scheme works as long as the values are unique within the table: sequential
integers, an offset per table, or `Ecto.UUID.generate/0` for `uuid` columns.
Foreign keys are satisfied by insertion order, which follows the order tables
were declared, so declare parents before children.

> #### Reset the sequence for serial columns {: .warning}
>
> If a primary key column is `serial`, `bigserial`, or an identity column,
> inserting explicit IDs does **not** advance its sequence. Seeding IDs 1 to
> 1,000 leaves the sequence at 1, and the next ordinary insert your application
> makes fails with a unique constraint violation on ID 1.
>
> Pass `reset_sequences: true` to advance every seeded table's sequence past
> the highest copied value:
>
> ```elixir
> run(seeder, Blog.Repo, reset_sequences: true)
> ```
>
> Tables with `uuid` primary keys, or integer keys you manage yourself, have no
> sequence and are skipped.

## Streams

In the example above, the `table/2` clauses returned lists. Since Blink stores the entire Seeder struct in memory, large lists can be problematic.

To avoid this, `table/2` can return a stream instead:

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
    for i <- 1..20 do
      %{
        id: (user.id - 1) * 20 + i,
        title: "Post #{i} by #{user.name}",
        body: "This is the content of post #{i}",
        user_id: user.id,
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end
  end)
end
```

Streams are processed lazily by `run/2` without extra configuration needed.

## Using context

Sometimes you need to compute data once and share it across multiple tables. Context data is not inserted into the database but is available when building your table data.

In this example, we generate timestamps once and reuse them across tables, ensuring posts are created after their author are.

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
  random_timestamp = Enum.random(timestamps)

  for i <- 1..100 do
    %{
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      inserted_at: random_timestamp,
      updated_at: random_timestamp
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

    random_valid_timestamp = Enum.random(valid_timestamps)

    for i <- 1..5 do
      %{
        id: (user.id - 1) * 5 + i,
        title: "Post #{i}",
        body: "Content here",
        user_id: user.id,
        inserted_at: random_valid_timestamp,
        updated_at: random_valid_timestamp
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

- [Configuring Options](configuring_options.html) - Set global and per-table options for batch size and concurrency
- [Loading Data from Files](loading_data_from_files.html) - Learn how to load data from CSV and JSON files
- [Integrating with ExMachina](integrating_with_ex_machina.html) - Generate realistic test data
