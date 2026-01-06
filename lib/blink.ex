defmodule Blink do
  @moduledoc """
  Blink provides an efficient way to seed large amounts of data into your
  database.

  ## Overview

  Blink simplifies database seeding by providing a structured way to build and
  insert records:

  1. Create an empty `Store`.
  2. Assign the records you want to insert to each database table.
  3. Bulk-insert the records into your database.

  ## Stores

  Stores are the central data unit in Blink. A `Store` is a struct that holds
  the records you want to seed, along with any contextual data you need during
  the seeding process but do not want to insert into the database.

  A `Store` struct contains the keys `tables` and `context`:

      Blink.Store{
        tables: %{
          "table_name" => [...]
        },
        context: %{
          "key" => [...]
        }
      }

  All keys in `tables` must match the name of a table in your database. Table
  names can be either atoms or strings.

  ### Tables

  A mapping of table names to lists of records. These records will be persisted
  to the database when `insert/2` or `insert/3` are called.

  ### Context

  Stores arbitrary data needed during the seeding process. This data is
  available when building your seeds but is not inserted into the database by
  `insert/2` or `insert/3`.

  ## Basic Usage

  To seed your database with Blink, follow these three steps:

  - **Create**: Initialize an empty store with `new/0`.

  - **Build**: Add seed data with `add_table/2` and context data with
    `add_context/2`.

  - **Insert**: Persist records to the database with `insert/2` or `insert/3`.

  ### Example

      defmodule MyApp.Seeder do
        use Blink

        def call do
          new()
          |> add_table("users")
          |> add_context("post_ids")
          |> insert(MyApp.Repo, batch_size: 1_200)
        end

        def table(_store, "users") do
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 2, name: "Bob", email: "bob@example.com"}
          ]
        end

        def context(_store, "post_ids") do
          [1, 2, 3]
        end
      end

  ## Custom Logic for Inserting Records

  The functions `insert/2` and `insert/3` bulk insert the table records in a
  `Store` into a Postgres database using Postgres' `COPY` command. You can
  override the default implementation by defining your own `insert/2` or
  `insert/3` function in your Blink module. Doing so you can support seeding
  databases other than Postgres.
  """

  alias Blink.Store

  @doc """
  Builds and returns the records to be stored under a table key in the given
  `Store`.

  The callback `table/2` is called by `add_table/2` internally, passing the
  given database table name to `table/2`. Therefore, each table name passed to a
  `add_table/2` clause must match a `table/2` clause.

  Data added to a store with `table/2` is inserted into the corresponding
  database table when calling `insert/2` or `insert/3`.

  When the callback function is missing, an `ArgumentError` is raised.
  """
  @callback table(store :: Store.t(), table_name :: binary() | atom()) :: [map()]

  @doc """
  Builds and returns the data to be stored under a context key in the given
  `Store`.

  The callback `context/2` is called by `add_context/2` internally, passing the
  given context key to `context/2`. Therefore, each key passed to a
  `add_context/2` clause must match a `context/2` clause.

  `insert/2` and `insert/3` ignore the `:context` data and only insert data from
  `:tables`.

  When the callback function is missing, an `ArgumentError` is raised.
  """
  @callback context(store :: Store.t(), table_or_context_key :: binary() | atom()) :: [map()]

  @doc """
  Specifies how to perform a bulk insert of the seed data from a `Store` into
  the given Ecto repository.

  This callback function is optional, since Blink ships with a default
  implementation for Postgres databases.
  """
  @callback insert(store :: Store.t(), repo :: Ecto.Repo.t()) :: :ok | :error
  @callback insert(store :: Store.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              :ok | :error

  @optional_callbacks [table: 2, context: 2, insert: 2, insert: 3]

  defmacro __using__(_) do
    quote do
      @behaviour Blink
      @default_batch_size 900

      @doc """
      Creates an empty Store.

      ## Example

          iex> new()
          %Store{tables: %{}, context: %{}}
      """
      @spec new() :: Store.t()
      def new do
        %Store{}
      end

      @spec add_table(store :: Store.t(), table_name :: binary() | atom()) :: Store.t()
      def add_table(%Store{} = store, table_name)
          when is_binary(table_name) or is_atom(table_name) do
        raise_if_key_exists(store, table_name, :tables)

        put_in(store.tables[table_name], table(store, table_name))
      end

      @spec add_context(store :: Store.t(), key :: binary() | atom()) :: Store.t()
      def add_context(%Store{} = store, key) when is_binary(key) or is_atom(key) do
        raise_if_key_exists(store, key, :context)

        put_in(store.context[key], context(store, key))
      end

      defp raise_if_key_exists(%Store{} = store, key, target) do
        keys_as_strings =
          store[target]
          |> Map.keys()
          |> Enum.map(&key_to_string/1)

        if key_to_string(key) in keys_as_strings do
          raise ArgumentError, "key already exists in `#{inspect(target)}` of Store: #{key}"
        end
      end

      defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
      defp key_to_string(key) when is_binary(key), do: key

      @spec table(
              store :: Store.t(),
              table_or_context_key :: binary() | atom()
            ) :: [map()]
      def table(store, table_or_context_key)

      def table(%Store{}, table_name) do
        raise ArgumentError,
              "you must define table/2 clauses that correspond with your calls to add_table/2"
      end

      def context(%Store{}, context_key) do
        raise ArgumentError,
              "you must define context/2 clauses that correspond with your calls to add_context/2"
      end

      @doc """
      Inserts all table records from a Store's into the given repository.
      Iterates over the tables in order when seeding the database.

      The repo parameter must be a module that implements the Ecto.Repo
      behaviour and is configured with a Postgres adapter (e.g.,
      Ecto.Adapters.Postgres).

      Data stored in the Store's context is ignored.
      """
      @spec insert(store :: Store.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}
      def insert(%Store{} = store, repo, opts \\ []) when is_atom(repo) do
        repo.transact(fn ->
          Enum.each(store.tables, fn {table_name, items} ->
            copy_to_table(items, table_name, repo, opts)
          end)
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end

      defp copy_to_table(%Store{tables: tables}, table_name, repo, opts) do
        columns = Map.keys(tables)
        columns_string = Enum.map_join(columns, ", ", &~s("#{&1}"))

        format_csv_value = fn
          nil -> "\\N"
          value when is_binary(value) -> value
          value -> to_string(value)
        end

        stream =
          Ecto.Adapters.SQL.stream(
            repo,
            """
            COPY #{key_to_string(table_name)} (#{columns_string})
            FROM STDIN
            WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
            """
          )

        tables
        |> Stream.chunk_every(Keyword.get(opts, :batch_size, @default_batch_size))
        |> Enum.into(stream, fn chunk ->
          chunk
          |> Enum.map(fn row ->
            row_iodata =
              columns
              |> Enum.map(fn col -> format_csv_value.(Map.get(row, col)) end)
              |> Enum.intersperse("|")

            [row_iodata, "\n"]
          end)
          |> IO.iodata_to_binary()
        end)
      end

      defoverridable Blink
    end
  end
end
