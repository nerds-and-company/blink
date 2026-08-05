# Configuring Options

Blink provides options to control how data is inserted into your database. Options can be set globally when calling `run/3`, or per-table when declaring tables with `with_table/3`.

## Global options

Global options are passed to `run/3` and apply to all tables:

```elixir
defmodule Blog.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> with_table("posts")
    |> run(Blog.Repo, batch_size: 5_000, max_concurrency: 4)
  end

  def table(_seeder, "users"), do: # ...
  def table(_seeder, "posts"), do: # ...
end
```

### Available options

- `:timeout` - The time in milliseconds to wait for the transaction to complete (default: 15,000). Set to `:infinity` to disable the timeout.

The following options are specific to `Blink.Adapter.Postgres`:

- `:batch_size` - Number of rows per batch (default: 8,000). Rows are grouped into batches before being sent to the database.

- `:max_concurrency` - Maximum number of parallel database connections for COPY operations (default: 6). Set to 1 for sequential execution.

## Per-table options

Per-table options override global options for specific tables. Pass them as the last argument to `with_table/3`:

```elixir
def call do
  new()
  |> with_table("users", batch_size: 1_000)
  |> with_table("posts", max_concurrency: 2)
  |> run(Blog.Repo, batch_size: 5_000, max_concurrency: 4)
end
```

In this example:
- `users` uses `batch_size: 1_000` and `max_concurrency: 4` (from global)
- `posts` uses `batch_size: 5_000` (from global) and `max_concurrency: 2`

### When to use per-table options

Per-table options are useful when tables have different characteristics and you care about optimizing seeding time and/or memory use.

## Using `copy_to_table/4` directly

When using `copy_to_table/4` outside of a seeder, pass options directly:

```elixir
users = [
  %{id: 1, name: "Alice"},
  %{id: 2, name: "Bob"}
]

Blink.copy_to_table(users, "users", Blog.Repo,
  batch_size: 1_000,
  max_concurrency: 2
)
```

## Summary

In this guide, we learned how to:

- Set global options with `run/3`
- Override options per-table with `with_table/3`
- Use options with `copy_to_table/4`
