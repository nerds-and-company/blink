defmodule Blink.Adapter do
  @moduledoc """
  Behaviour and routing for Blink database adapters.

  Adapters are responsible for implementing database-specific bulk insert
  operations. Each adapter must implement the `call/4` callback which performs
  the bulk insertion using the appropriate database-specific mechanism (e.g.,
  PostgreSQL's COPY, MySQL's LOAD DATA INFILE, etc.).

  ## Example

      defmodule MyApp.CustomAdapter do
        @behaviour Blink.Adapter

        @impl true
        def call(items, table_name, repo, opts) do
          # Custom bulk copy implementation
          {:ok, result}
        end
      end

      # Usage
      Blink.copy_to_table(items, "users", MyApp.Repo, adapter: MyApp.CustomAdapter)
  """

  @doc """
  Performs a bulk copy operation to insert items into a database table.

  ## Parameters

    * `items` - A list of maps where each map represents a row to insert. All
      maps must have the same keys, which correspond to the table columns.
    * `table_name` - The name of the table to insert into (string or atom).
    * `repo` - An Ecto repository module.
    * `opts` - Keyword list of options. Common options include:
      * `:batch_size` - Number of rows to send per batch
      * Other adapter-specific options

  ## Returns

    * `{:ok, result}` - When the copy operation succeeds
    * `{:error, reason}` - When the copy operation fails
  """
  @callback call(
              items :: [map()],
              table_name :: Blink.Store.key(),
              repo :: Ecto.Repo.t(),
              opts :: Keyword.t()
            ) :: Enumerable.t() | :empty

  @doc """
  Copies a list of items into a database table using the appropriate database
  adapter.

  The adapter is selected based on the `:adapter` option in `opts`.
  """
  @spec copy_to_table(
          items :: [map()],
          table_name :: Blink.Store.key(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: Enumerable.t() | :empty
  def copy_to_table(items, table_name, repo, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Blink.Adapter.Postgres)

    unless Code.ensure_loaded?(adapter) and function_exported?(adapter, :call, 4) do
      raise ArgumentError,
            "adapter #{inspect(adapter)} must implement Blink.Adapter behaviour and define call/4"
    end

    adapter.call(items, table_name, repo, opts)
  end
end
