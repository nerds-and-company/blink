# Custom Adapters

Blink uses an adapter pattern to support different database bulk insert implementations. While Blink ships with a PostgreSQL adapter (`Blink.Adapter.Postgres`), you can create custom adapters for other databases (e.g., MySQL).

## The Adapter Behavior

All adapters must implement the `Blink.Adapter` behavior, which requires a single callback:

```elixir
@callback call(
  items :: [map()],
  table_name :: binary() | atom(),
  repo :: Ecto.Repo.t(),
  opts :: Keyword.t()
) :: {:ok, any()} | {:error, any()}
```

The `call/4` function receives:

- `items` - List of maps to bulk insert into table
- `table_name` - Target table name
- `repo` - Ecto repository module
- `opts` - Options like `:batch_size`

## Creating a Custom Adapter

Here's a minimal adapter implementation:

```elixir
defmodule MyApp.Adapters.MySQL do
  @behaviour Blink.Adapter

  @impl true
  def call(items, table_name, repo, opts \\ []) do
    # Your bulk insert implementation
    {:ok, result}
  rescue
    e -> {:error, e}
  end
end
```

The adapter should:
- Perform bulk insertion using database-specific commands
- Return `{:ok, result}` on success or `{:error, reason}` on failure
- Handle errors gracefully

## Using a Custom Adapter

Pass your adapter when calling `insert/3`:

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> add_table("users")
    |> insert(MyApp.Repo, adapter: MyApp.Adapters.MySQL)
  end

  def table(_store, "users") do
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

## Overriding the Insert Function

For complete control over the insertion process, you can override the `insert/3` callback in your Blink module:

```elixir
defmodule MyApp.Seeder do
  use Blink

  @impl true
  def insert(%Store{} = store, repo, opts \\ []) do
    # Implement custom transaction logic, error handling, etc.
    # Tip: Blink.copy_to_table/4 is available for inserting data into individual tables
  end
end
```

This allows you to customize transaction behavior, error handling, or set a default adapter for all operations.

## Reference

See `Blink.Adapter.Postgres` for a complete reference implementation using PostgreSQL's `COPY FROM STDIN` command.
