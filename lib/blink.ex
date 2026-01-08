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
  alias Blink.CSVParser

  @doc """
  Reads a CSV file and returns a list of maps suitable for use in `table/2` callbacks.

  By default, the CSV file must have a header row. Each column header will become a
  string key in the resulting maps. All values are returned as strings.

  ## Parameters

    * `path` - Path to the CSV file (relative or absolute)
    * `opts` - Keyword list of options:
      * `:headers` - List of header names to use, or `:infer` to read from first row (default: `:infer`)
      * `:transform` - Function to transform each row map (default: identity function)

  ## Examples

      # Simple usage with headers in first row
      def table(_store, "users") do
        Blink.from_csv("users.csv")
      end

      # CSV without headers - provide them explicitly
      def table(_store, "users") do
        Blink.from_csv("users.csv", headers: ["id", "name", "email"])
      end

      # With custom transformation for type conversion
      def table(_store, "users") do
        Blink.from_csv("users.csv",
          transform: fn row ->
            row
            |> Map.update!("id", &String.to_integer/1)
            |> Map.update!("age", &String.to_integer/1)
          end
        )
      end

  ## Returns

  A list of maps, where each map represents a row from the CSV file.
  """
  @spec from_csv(path :: String.t(), opts :: Keyword.t()) :: [map()]
  def from_csv(path, opts \\ []) do
    raw_rows =
      path
      |> File.stream!()
      |> CSVParser.parse_stream(skip_headers: false)
      |> Enum.to_list()

    parse_csv_rows(
      raw_rows,
      Keyword.get(opts, :headers, :infer),
      Keyword.get(opts, :transform, & &1)
    )
  end

  defp parse_csv_rows([], _, _), do: []

  defp parse_csv_rows(_, _, transform) when not is_function(transform, 1) do
    raise ArgumentError, ":transform option must be a function that takes 1 argument"
  end

  defp parse_csv_rows([headers | rows], :infer, transform) do
    Enum.map(rows, fn row ->
      headers
      |> Enum.zip(row)
      |> Map.new()
      |> transform.()
    end)
  end

  defp parse_csv_rows(rows, headers, transform) when is_list(headers) do
    Enum.map(rows, fn row ->
      headers
      |> Enum.zip(row)
      |> Map.new()
      |> transform.()
    end)
  end

  defp parse_csv_rows(_rows, invalid_headers, _transform) do
    raise ArgumentError,
          ":headers option must be a list of header names or :infer, got: #{inspect(invalid_headers)}"
  end

  @doc """
  Reads a JSON file and returns a list of maps suitable for use in `table/2` callbacks.

  The JSON file must contain an array of objects at the root level. Each object
  becomes a map with string keys.

  ## Parameters

    * `path` - Path to the JSON file
    * `opts` - Keyword list of options:
      * `:transform` - Function to transform each row map (default: identity function)

  ## Examples

      # Simple usage
      def table(_store, "users") do
        Blink.from_json("users.json")
      end

      # With custom transformation for type conversion
      def table(_store, "users") do
        Blink.from_json("users.json",
          transform: fn row ->
            row
            |> Map.update!("id", &String.to_integer/1)
            |> Map.update!("age", &String.to_integer/1)
          end
        )
      end

  ## Returns

  A list of maps, where each map represents an object from the JSON array.
  """
  @spec from_json(path :: String.t(), opts :: Keyword.t()) :: [map()]
  def from_json(path, opts \\ []) do
    raw_items =
      path
      |> File.read!()
      |> Jason.decode!()

    parse_json_items(raw_items, Keyword.get(opts, :transform, & &1))
  end

  defp parse_json_items(_, transform) when not is_function(transform, 1) do
    raise ArgumentError, ":transform option must be a function that takes 1 argument"
  end

  defp parse_json_items(items, transform) when is_list(items) do
    validate_json_items(items)
    Enum.map(items, transform)
  end

  defp parse_json_items(other, _transform) do
    raise ArgumentError,
          "JSON file must contain an array at root level, found: #{inspect(other)}"
  end

  defp validate_json_items(items) do
    Enum.each(items, fn item ->
      if not is_map(item) do
        raise ArgumentError,
              "JSON file must contain an array of objects, found: #{inspect(item)}"
      end
    end)
  end

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
            case copy_to_table(items, table_name, repo, opts) do
              {:ok, _} -> :ok
              {:error, reason} -> raise reason
            end
          end)

          {:ok, :inserted}
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      rescue
        e -> {:error, e}
      end

      @doc """
      Copies a list of items into a database table using PostgreSQL's COPY command.

      This function uses PostgreSQL's `COPY FROM STDIN` command for efficient bulk
      insertion of data. Items are streamed to the database in batches to minimize
      memory usage.

      ## Parameters

        * `items` - A list of maps where each map represents a row to insert. All maps
          must have the same keys, which correspond to the table columns.
        * `table_name` - The name of the table to insert into (string or atom).
        * `repo` - An Ecto repository module configured with a Postgres adapter.
        * `opts` - Keyword list of options:
          * `:batch_size` - Number of rows to send per batch (default: #{@default_batch_size})

      ## Returns

        * `{:ok, :empty}` - When the items list is empty
        * `{:ok, result}` - When the copy operation succeeds

      ## Examples

          iex> items = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
          iex> copy_to_table(items, "users", MyApp.Repo, batch_size: 1000)
          {:ok, _result}

      ## Notes

      The function assumes all items have the same structure. Column names are
      extracted from the first item in the list. NULL values are represented as `\\N`
      in the CSV format.
      """
      @spec copy_to_table(
              items :: [map()],
              table_name :: binary() | atom(),
              repo :: Ecto.Repo.t(),
              opts :: Keyword.t()
            ) :: {:ok, :empty} | {:ok, any()}
      def copy_to_table(items, table_name, repo, opts \\ [])
          when is_list(items) and (is_binary(table_name) or is_atom(table_name)) and
                 is_atom(repo) and is_list(opts) do
        # Skip if no items to insert
        if Enum.empty?(items) do
          {:ok, :empty}
        else
          # Get columns from the first item
          columns = items |> List.first() |> Map.keys()
          columns_string = Enum.map_join(columns, ", ", &~s("#{&1}"))

          stream =
            Ecto.Adapters.SQL.stream(
              repo,
              """
              COPY #{key_to_string(table_name)} (#{columns_string})
              FROM STDIN
              WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
              """
            )

          result =
            items
            |> Stream.chunk_every(Keyword.get(opts, :batch_size, @default_batch_size))
            |> Enum.into(stream, fn chunk ->
              chunk
              |> Enum.map(fn row ->
                row_iodata =
                  columns
                  |> Enum.map(fn col -> format_csv_value(Map.get(row, col)) end)
                  |> Enum.intersperse("|")

                [row_iodata, "\n"]
              end)
              |> IO.iodata_to_binary()
            end)

          {:ok, result}
        end
      end

      defp format_csv_value(nil), do: "\\N"
      defp format_csv_value(value) when is_binary(value), do: value
      defp format_csv_value(value), do: to_string(value)

      defoverridable Blink
    end
  end
end
