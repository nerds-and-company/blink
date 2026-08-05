# Custom Adapters

Blink uses an adapter pattern to support different database bulk insert implementations. While Blink ships with a PostgreSQL adapter (`Blink.Adapter.Postgres`), you can create custom adapters for other databases (e.g., MySQL).

## The Adapter Behavior

All adapters must implement the `Blink.Adapter` behaviour, which requires a single callback:

```elixir
@callback call(
  rows :: Enumerable.t(),
  table_name :: String.t(),
  repo :: Ecto.Repo.t(),
  opts :: Keyword.t()
) :: :ok
```

The `call/4` function receives:

- `rows` - An enumerable (list or stream) of maps to bulk insert
- `table_name` - Target table name (always a string; atom table names are converted first)
- `repo` - Ecto repository module
- `opts` - Adapter-specific options. Every option passed to `run/3` or `copy_to_table/4` that Blink does not consume itself arrives here, so the adapter owns its option vocabulary and should validate it — `Keyword.validate!/2` rejects unknown keys, and invalid values should raise `ArgumentError` too.

Example:

```elixir
defmodule MyApp.Adapters.MySQL do
  @behaviour Blink.Adapter

  @impl true
  def call(rows, table_name, repo, opts \\ []) do
    # Your bulk insert implementation
    :ok
  end
end
```

The adapter should:
- Perform bulk insertion using database-specific commands
- Return `:ok` on success
- Raise an exception on failure

## Supporting `:atomic`

Seeds are all-or-nothing by default. When `atomic: true`, `run/3` opens a
transaction on the calling process's connection and relies on the adapter to
perform the whole copy **in the calling process** so it enrols in that
transaction. An adapter that hands batches to other processes — each checking
out its own connection — silently voids the guarantee: a failed seed would
report a rollback while parts of it stayed committed.

Support `:atomic` only by copying in the calling process. If your adapter
cannot, reject the option rather than ignore it:

```elixir
@impl true
def call(rows, table_name, repo, opts) do
  case Keyword.get(opts, :atomic, true) do
    true -> raise ArgumentError, "MyApp.Adapters.MySQL does not support atomic: true"
    false -> bulk_insert(rows, table_name, repo, opts)
  end
end
```

## Using a Custom Adapter

Pass your adapter when calling `run/3`:

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> run(MyApp.Repo, adapter: MyApp.Adapters.MySQL)
  end

  def table(_seeder, "users") do
    [
      %{id: 1, name: "Alice"},
      %{id: 2, name: "Bob"}
    ]
  end
end
```

Or use it directly with `copy_to_table/4`:

```elixir
Blink.copy_to_table(items, "users", MyApp.Repo, adapter: MyApp.Adapters.MySQL)
```

## Overriding the Run Function

For complete control over the insertion process, you can override the `run/3` callback in your Blink module:

```elixir
defmodule MyApp.Seeder do
  use Blink

  @impl true
  def run(%Blink.Seeder{} = seeder, repo, opts \\ []) do
    # Implement custom transaction logic, error handling, etc.
    # Tip: Blink.copy_to_table/4 is available for inserting data into individual tables
  end
end
```

`use Blink` imports `Blink.Seeder` rather than aliasing it, so match on the
struct by its full name — a bare `%Seeder{}` does not resolve.

This allows you to customize transaction behavior, error handling, or set a default adapter for all operations. Note that overriding `run/3` replaces Blink's transaction handling, so `atomic: true` no longer does anything by itself — your implementation is responsible for opening the transaction.

## Reference

See `Blink.Adapter.Postgres` for a complete reference implementation using PostgreSQL's `COPY FROM STDIN` command.
