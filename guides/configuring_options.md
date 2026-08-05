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
    |> run(Blog.Repo, batch_size: 5_000, timeout: 60_000)
  end

  def table(_seeder, "users"), do: # ...
  def table(_seeder, "posts"), do: # ...
end
```

### Available options

- `:atomic` - Whether the seed is all-or-nothing (default: `true`). By default the whole seed runs over a single connection inside one transaction (rows are still encoded in parallel across cores): if any table fails, every table is rolled back, so fixing the data and re-running is always safe. Pass `atomic: false` to copy batches over parallel database connections for maximum speed; each batch then commits independently, and a failure partway through raises with earlier batches and tables left committed for you to inspect and clean up. A seed running inside a transaction of your own must stay atomic — the parallel connections of a non-atomic seed cannot see your transaction's uncommitted data, and their commits survive its rollback.

- `:timeout` - The time in milliseconds allowed for each database operation (default: 15,000). Set to `:infinity` to disable the timeout.

The following options are specific to `Blink.Adapter.Postgres`:

- `:batch_size` - Number of rows per batch (default: 8,000). Rows are grouped into batches before being sent to the database.

- `:concurrency` - Number of parallel workers. By default (`atomic: true`) the workers encode rows in parallel while a single connection copies (default: the number of cores). With `atomic: false` each worker instead copies batches over its own database connection (default: 6), so configure your repo's `pool_size` to at least `:concurrency`.

## Per-table options

Per-table options override global options for specific tables. The run-level options `:atomic` and `:timeout` apply to the whole run and raise `ArgumentError` when set per table; the tuning options `:batch_size` and `:concurrency` can be set freely. Pass them as the last argument to `with_table/3`:

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

`copy_to_table/4` accepts the same options as `run/3`. Like a seed, a single copy is all-or-nothing unless you pass `atomic: false`.

## Summary

In this guide, we learned how to:

- Set global options with `run/3`
- Trade all-or-nothing seeding for speed with `atomic: false`
- Override tuning options per-table with `with_table/3`
- Use options with `copy_to_table/4`
