defmodule Blink.Adapter do
  @moduledoc """
  Defines the adapter behaviour and dispatches to the selected adapter.

  Adapters are responsible for implementing database-specific bulk insert
  operations. Each adapter must implement the `call/4` callback to bulk insert
  rows into a table using a database-specific mechanism (e.g., PostgreSQL's COPY
  command).

  ## Example

      defmodule MyApp.CustomAdapter do
        @behaviour Blink.Adapter

        @impl true
        def call(items, table_name, repo, opts) do
          # Custom bulk copy implementation
          :ok
        end
      end

      # Usage
      run(seeder, MyApp.Repo, adapter: MyApp.CustomAdapter)

      # Or via copy_to_table/4
      Blink.copy_to_table(items, "users", MyApp.Repo, adapter: MyApp.CustomAdapter)
  """

  @doc """
  Performs a bulk copy operation to insert rows into a database table.

  ## Parameters

    * `rows` - An enumerable (list or stream) of maps where each map represents
      a row to insert. All maps must have the same keys, which correspond to the
      table columns.
    * `table_name` - The name of the table to insert into (string).
    * `repo` - An Ecto repository module.
    * `opts` - Keyword list of adapter-specific options.

  ## Returns

    * `:ok` - When the copy operation succeeds

  Raises an exception when the copy operation fails.
  """
  @callback call(
              rows :: Enumerable.t(),
              table_name :: String.t(),
              repo :: Ecto.Repo.t(),
              opts :: Keyword.t()
            ) :: :ok

  @doc """
  Copies rows into a database table using the appropriate database adapter.

  The adapter is selected based on the `:adapter` option in `opts`.
  """
  @spec copy_to_table(
          rows :: Enumerable.t(),
          table_name :: String.t(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: :ok
  def copy_to_table(rows, table_name, repo, opts \\ []) do
    {adapter, opts} = Keyword.pop(opts, :adapter, Blink.Adapter.Postgres)

    adapter.call(rows, table_name, repo, opts)
  end
end
