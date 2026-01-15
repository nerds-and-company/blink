defmodule Blink do
  @moduledoc """
  Blink provides an efficient way to seed large amounts of data into your
  database.

  ## Overview

  Blink simplifies database seeding by providing a structured way to build and
  insert records:

  1. Create an empty `Seeder`.
  2. Assign the records you want to insert to each database table.
  3. Bulk-insert the records into your database.

  ## Seeders

  Seeders are the central data unit in Blink. A `Seeder` is a struct that holds
  the records you want to seed, along with any contextual data you need during
  the seeding process but do not want to insert into the database.

  A `Seeder` struct contains the keys `tables` and `context`:

      Blink.Seeder{
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
  to the database when `run/2` or `run/3` are called.

  ### Context

  Stores arbitrary data needed during the seeding process. This data is
  available when building your seeds but is not inserted into the database by
  `run/2` or `run/3`.

  ## Basic Usage

  To seed your database with Blink, follow these four steps:

  - **Create**: Initialize an empty seeder with `new/0`.

  - **Declare**: Declare when tables and context keys need to be added to the Seeder with `with_table/2` and `with_context/2`.

  - **Build**: Define the data for each table and context key by adding `table/2` or `context/2` clauses.

  - **Run**: Persist records to the database with `run/2` or `run/3`.

  ### Example

      defmodule MyApp.Seeder do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> with_context("post_ids")
          |> run(MyApp.Repo, batch_size: 1_200)
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

  ## Custom Logic for Running the Seeder

  The functions `run/2` and `run/3` bulk insert the table records in a
  `Seeder` into a Postgres database using Postgres' `COPY` command. You can
  override the default implementation by defining your own `run/2` or
  `run/3` function in your Blink module. Doing so you can support seeding
  databases other than Postgres.
  """

  alias Blink.Seeder

  @doc """
  Builds and returns the records to be stored under a table key in the given
  `Seeder`.

  The callback `table/2` is called by `with_table/2` internally, passing the
  given database table name to `table/2`. Therefore, each table name passed to a
  `with_table/2` clause must match a `table/2` clause.

  Data added to a Seeder with `table/2` is inserted into the corresponding
  database table when calling `run/2` or `run/3`.

  When the callback function is missing, an `ArgumentError` is raised.
  """
  @callback table(store :: Seeder.t(), table_name :: Seeder.key()) :: [map()]

  @doc """
  Builds and returns the data to be stored under a context key in the given
  `Seeder`.

  The callback `context/2` is called by `with_context/2` internally, passing the
  given context key to `context/2`. Therefore, each key passed to a
  `with_context/2` clause must match a `context/2` clause.

  `run/2` and `run/3` ignore the `:context` data and only insert data from
  `:tables`.

  When the callback function is missing, an `ArgumentError` is raised.
  """
  @callback context(store :: Seeder.t(), key :: Seeder.key()) :: [map()]

  @doc """
  Specifies how to run the Seeder, performing a bulk insert of the seed data
  from a `Seeder` into the given Ecto repository.

  This callback function is optional, since Blink ships with a default
  implementation.
  """
  @callback run(seeder :: Seeder.t(), repo :: Ecto.Repo.t()) :: {:ok, any()} | {:error, any()}
  @callback run(seeder :: Seeder.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              {:ok, any()} | {:error, any()}

  @optional_callbacks [table: 2, context: 2, run: 2, run: 3]

  defmacro __using__(_) do
    quote do
      @behaviour Blink
      @default_batch_size :infinity

      import Seeder, only: [is_key: 1, new: 0]

      import Blink,
        only: [
          from_csv: 1,
          from_csv: 2,
          from_json: 1,
          from_json: 2,
          copy_to_table: 3,
          copy_to_table: 4
        ]

      @spec with_table(seeder :: Seeder.t(), table_name :: Seeder.key()) ::
              Seeder.t()
      def with_table(%Seeder{} = seeder, table_name) when is_key(table_name) do
        Seeder.with_table(seeder, table_name, &table/2)
      end

      @spec with_context(seeder :: Seeder.t(), key :: Seeder.key()) :: Seeder.t()
      def with_context(%Seeder{} = seeder, key) when is_key(key) do
        Seeder.with_context(seeder, key, &context/2)
      end

      @impl true
      @spec table(
              store :: Seeder.t(),
              table_name :: Seeder.key()
            ) :: [map()]
      def table(store, table_name)

      @impl true
      def table(%Seeder{}, table_name) do
        raise ArgumentError,
              "you must define table/2 clauses that correspond with your calls to with_table/2"
      end

      @impl true
      def context(%Seeder{}, key) do
        raise ArgumentError,
              "you must define context/2 clauses that correspond with your calls to with_context/2"
      end

      @impl true
      @spec run(seeder :: Seeder.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
              {:ok, any()} | {:error, any()}
      defdelegate run(seeder, repo, opts \\ []), to: Seeder

      defoverridable Blink
    end
  end

  @doc """
  Copies a list of items into a database table using database-specific bulk copy commands.

  This function provides an efficient way to insert large amounts of data by using
  database-specific bulk copy commands. Items are streamed to the database in batches
  to minimize memory usage.

  ## Parameters

    * `items` - A list of maps where each map represents a row to insert. All maps
      must have the same keys, which correspond to the table columns.
    * `table_name` - The name of the table to insert into (string or atom).
    * `repo` - An Ecto repository module.
    * `opts` - Keyword list of options:
      * `:adapter` - The adapter module to use. Defaults to `Blink.Adapter.Postgres`.
      * `:batch_size` - Number of rows to send per batch (default: `:infinity`)

  ## Returns

    * `{:ok, result}` - When the copy operation succeeds
    * `{:error, reason}` - When the copy operation fails

  ## Examples

      iex> items = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> copy_to_table(items, "users", MyApp.Repo, batch_size: 1000)
      {:ok, _result}

      # Using a specific adapter
      iex> copy_to_table(items, "users", MyApp.Repo, adapter: Some.Custom.Adapter)
      {:ok, _result}

  ## Notes

  The function assumes all items have the same structure. Column names are
  extracted from the first item in the list.

  Currently only PostgreSQL is supported via `Blink.Adapter.Postgres`.
  """
  @spec copy_to_table(
          items :: [map()],
          table_name :: Seeder.key(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: {:ok, any()} | {:error, any()}
  defdelegate copy_to_table(items, table_name, repo, opts \\ []), to: Blink.Adapter

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
  defdelegate from_csv(path, opts \\ []), to: Blink.CSV

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
  defdelegate from_json(path, opts \\ []), to: Blink.JSON
end
