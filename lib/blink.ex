defmodule Blink do
  @moduledoc """
  Blink provides an efficient way to seed large amounts of data into your
  database.

  ## Overview

  Blink simplifies database seeding by providing a structured way to build and insert records:

  1. Create an empty `Store`.
  2. Assign the records you want to insert to each database table.
  3. Bulk-insert the records into your database.

  ## Stores

  Stores are the central data unit in Blink. A `Store` is a struct that holds
  the records you want to seed, along with any helper data you need but do not
  want to insert into the database”.

  A `Store` struct contains the keys `seeds` and `helpers`:

      Blink.Store{
        seeds: %{
          "table_name" => [...]
        },
        helpers: %{
          "arbitrary_key" => [...]
        }
      }

  All keys in `seeds` must match the name of a table in your database. Table
  names can be either atoms or strings.

  ### Seeds

  A mapping of table names to lists of records. These records will be persisted
  to the database when `insert_all/2` or `insert_all/3` are called.

  ### Helpers

  A mapping of arbitrary keys to lists of helper data. Helper data can be
  referenced when setting up your seeds, but will not be inserted into the
  database when calling `insert_all/2` or `insert_all/3`.

  ## Basic Usage

  The typical workflow involves three steps:

  - **Create**: Initialize an empty store with `new_store/0`.

  - **Build**: Add seed data with `put_table/2` and helper data with
    `put_helper/2`.

  - **Insert**: Persist records to the database with `insert_all/2` or
    `insert_all/3`.

  ### Example

      defmodule MyApp.Seeder do
        use Blink

        def call do
          new_store()
          |> put_table("users")
          |> put_helper("post_ids")
          |> insert_all(MyApp.Repo, batch_size: 1_200)
        end

        def build(_store, "users") do
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 2, name: "Bob", email: "bob@example.com"}
          ]
        end

        def build(_store, "post_ids", :helpers) do
          [1, 2, 3]
        end
      end

  ## Custom Logic for Inserting Seeds

  The functions `insert_all/2` and `insert_all/3` bulk insert your seed data
  into a PostgreSQL database using PostgreSQL's `COPY` command. You can override
  the default implementation by defining your own `insert_all/2` or
  `insert_all/3` function in your Blink module. Doing so you can support seeding
  databases other than PostgreSQL.

  ### Example

      defmodule MyApp.Seeder do
        use Blink

        def insert_all(store, repo, opts) do
          Enum.each(store.seeds, fn {table, records} ->
            repo.insert_all(table, records, opts)
          end)
        end
      end
  """

  alias Blink.Store

  @doc """
  Builds data for a database table and adds it to the `seeds` of a given `Store`.

  Data added to a store with `build/2` is inserted into the corresponding
  database table when `insert_all/2` or `insert_all/3` are called.
  """
  @callback build(store :: Store.t(), table_name :: binary() | atom()) :: [map()]

  @doc """
  Builds data and adds it to the `seeds` or `helpers` of a given `Store`.

  Use the `target` parameter of `build/3` to specify whether to assign the data
  to the `:seeds` or `:helpers` key.

  Data in the `:seeds` key will be inserted into the database when `insert_all/2`
  or `insert_all/3` are called. Data in the `:helpers` key is ignored during
  insertion.
  """
  @callback build(
              store :: Store.t(),
              table_or_helper_name :: binary() | atom(),
              target :: :seeds | :helpers
            ) :: [
              map()
            ]

  @doc """
  Bulk inserts the seed data from a store to the given Ecto repository.

  This callback function is optional, since Blink ships with a default implementation for Postgres databases.
  """
  @callback insert_all(store :: Store.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              :ok | :error

  @optional_callbacks [build: 2, build: 3, insert_all: 3]

  defmacro __using__(_) do
    quote do
      @behaviour Blink
      @default_batch_size 900

      @doc """
      Creates an empty Store.

      ## Example

          iex> new_store()
          %Store{seeds: %{}, helpers: %{}}
      """
      @spec new_store() :: Store.t()
      def new_store do
        %Store{}
      end

      @spec put_table(store :: Store.t(), table_name :: binary() | atom()) :: Store.t()
      def put_table(%Store{} = store, table_name)
          when is_binary(table_name) or is_atom(table_name) do
        raise_if_key_exists(store, table_name)

        put_in(store.seeds[table_name], build(store, table_name))
      end

      @spec put_helper(store :: Store.t(), key :: binary() | atom()) :: Store.t()
      def put_helper(%Store{} = store, key) when is_binary(key) or is_atom(key) do
        raise_if_key_exists(store, key, :helpers)

        put_in(store.helpers[key], build(store, key, :helpers))
      end

      defp raise_if_key_exists(%Store{} = store, key, target \\ :seeds) do
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

      @spec build(
              store :: Store.t(),
              table_or_helper_name :: binary() | atom(),
              target :: :seeds | :helpers
            ) :: [map()]
      def build(store, table_or_helper_name, target \\ :seeds)

      def build(%Store{}, table_name, :seeds) do
        raise ArgumentError,
              "you must define build/2 clauses that correspond with your calls to put_table/2"
      end

      def build(%Store{}, helper_name, :helpers) do
        raise ArgumentError,
              "you must define build/2 clauses that correspond with your calls to put_helper/2"
      end

      @doc """
      Inserts all table records from a Store's seeds into the given repository.
      Iterates over the tables in order when seeding the database.

      The repo parameter must be a module that implements the Ecto.Repo
      behaviour and is configured with a Postgres adapter (e.g.,
      Ecto.Adapters.Postgres).

      Data stored in the Store's helpers is ignored.
      """
      @spec insert_all(store :: Store.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}
      def insert_all(%Store{} = store, repo, opts \\ []) when is_atom(repo) do
        repo.transact(fn ->
          Enum.each(store.seeds, fn {table_name, items} ->
            copy_to_table(items, table_name, repo, opts)
          end)
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end

      defp copy_to_table(%Store{seeds: seeds}, table_name, repo, opts) do
        columns = Map.keys(seeds)
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

        seeds
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
