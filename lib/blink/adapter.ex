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
    * `opts` - Keyword list of adapter-specific options. Adapters own their
      option vocabulary and should validate it, raising `ArgumentError` on
      unknown keys or invalid values (`Keyword.validate!/2` covers the former).

  `Blink.Seeder.run/3` forwards its options here, including `:atomic`. With
  `atomic: true` it opens a transaction on the calling process's connection and
  relies on the adapter to perform the whole copy in the calling process, so
  that the copy enrolls in the transaction. An adapter that hands batches to
  other processes — each checking out its own connection — silently voids that
  all-or-nothing guarantee. Support `:atomic` only by copying in the calling
  process; otherwise reject the option, so a failed seed cannot pass for
  rolled back when parts of it committed.

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
  Truncates the given tables, so a seed or copy can replace their contents.

  Optional. `Blink.Seeder.run/3` calls it with every declared table when run
  with `truncate: true` — before the first copy, on the calling process so
  the truncate enrolls in an atomic run's transaction — and raises
  `ArgumentError` for an adapter that does not implement it. Truncate all
  tables in a single statement (or the database's equivalent), so foreign
  keys between them do not constrain declaration order.

  ## Options

    * `:timeout` - Time in milliseconds allowed for the operation, when given.
  """
  @callback truncate(table_names :: [String.t()], repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              :ok

  @optional_callbacks truncate: 3

  @spec copy_to_table(
          rows :: Enumerable.t(),
          table_name :: String.t(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: :ok
  def copy_to_table(rows, table_name, repo, opts \\ []) do
    {adapter, opts} = Keyword.pop(opts, :adapter, Blink.Adapter.Postgres)

    adapter.call(rows, normalize_table_name(table_name), repo, opts)
  end

  # The `call/4` contract hands adapters a string, so atom names are converted
  # here — the same normalization `Blink.Seeder.run/3` applies to table keys.
  defp normalize_table_name(table_name) when is_atom(table_name), do: Atom.to_string(table_name)
  defp normalize_table_name(table_name) when is_binary(table_name), do: table_name
end
