# Configuring Options

Blink provides options to control how data is inserted into your database. Options can be set globally when calling `run/3`, or per-table when declaring tables with `with_table/3`. Unknown options and invalid values raise an `ArgumentError`, so a typo fails loudly instead of being silently ignored.

## Global options

Global options are passed to `run/3` and apply to all tables:

```elixir
defmodule Blog.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> with_table("posts")
    |> run(Blog.Repo, atomic: true, batch_size: 5_000)
  end

  def table(_seeder, "users"), do: # ...
  def table(_seeder, "posts"), do: # ...
end
```

### Available options

- `:atomic` - Whether the seed is all-or-nothing (default: `false`). By default Blink copies batches over parallel database connections for maximum speed, and each batch commits independently — a failure partway through can leave earlier batches and tables committed. With `atomic: true` the whole seed runs over a single connection inside one transaction (rows are still encoded in parallel across cores): if any table fails, every table is rolled back.

- `:timeout` - The time in milliseconds allowed for each database operation (default: 15,000). Set to `:infinity` to disable the timeout.

The following options are specific to `Blink.Adapter.Postgres`:

- `:batch_size` - Number of rows per batch (default: 8,000). Rows are grouped into batches before being sent to the database.

- `:concurrency` - Number of parallel workers. Without `atomic: true` each worker copies batches over its own database connection (default: 6), so configure your repo's `pool_size` to at least `:concurrency`. With `atomic: true` the workers encode rows in parallel while a single connection copies (default: the number of cores).

## Per-table options

Per-table options override global options for specific tables. Only the tuning options `:batch_size` and `:concurrency` can be set per table — `:atomic` and `:timeout` apply to the whole run. Pass them as the last argument to `with_table/3`:

```elixir
def call do
  new()
  |> with_table("users", batch_size: 1_000)
  |> with_table("posts", concurrency: 2)
  |> run(Blog.Repo, batch_size: 5_000, concurrency: 4)
end
```

In this example:
- `users` uses `batch_size: 1_000` and `concurrency: 4` (from global)
- `posts` uses `batch_size: 5_000` (from global) and `concurrency: 2`

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
  concurrency: 2
)
```

`copy_to_table/4` accepts the same options as `run/3`, including `atomic: true` for an all-or-nothing copy of a single table.

## Summary

In this guide, we learned how to:

- Set global options with `run/3`
- Make a seed all-or-nothing with `atomic: true`
- Override tuning options per-table with `with_table/3`
- Use options with `copy_to_table/4`
