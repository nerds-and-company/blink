defmodule Blink do
  @moduledoc """
  Blink provides efficient database seeding with a clean, declarative syntax.

  ## Example

      defmodule MyApp.Seeder do
        use Blink

        def call do
          new()
          |> with_table("users")
          |> run(MyApp.Repo)
        end

        def table(_seeder, "users") do
          [
            %{id: 1, name: "Alice", email: "alice@example.com"},
            %{id: 2, name: "Bob", email: "bob@example.com"}
          ]
        end
      end

  ## Overview

  Blink simplifies database seeding by providing a structured way to build and
  insert rows:

  1. Create an empty `Seeder` with `new/0`.
  2. Declare which tables to seed with `with_table/2`.
  3. Define `table/2` clauses that return the rows to insert.
  4. Run `run/2` or `run/3` to bulk-insert the rows.

  ## The seeder API

  `use Blink` defines these functions on your module. They are the primary API,
  but they do not appear in this module's function list below, because they are
  defined on *your* module rather than on `Blink`:

    * `with_table(seeder, table_name)` and `with_table(seeder, table_name, opts)` —
      declare a table; the rows come from your `table/2` clause for that name.
    * `with_context(seeder, key)` — declare a context key; the value comes from
      your `context/2` clause for that key.

  `use Blink` also imports `new/0` and, from this module, `put_table/2,3,4`,
  `put_context/2,3`, `copy_to_table/3,4`, `from_csv/1,2` and `from_json/1,2`, so
  you call all of them unqualified.

  ### Choosing between with_* and put_*

  Reach for `with_table/2` and `with_context/2` by default. Because the callback
  runs when the table is declared, it receives the seeder built so far and can
  read earlier tables and context off it — that is what makes the pipeline
  declarative and lets `"posts"` derive from `"users"`.

  Use `put_table/3` and `put_context/3` only when the data is already in hand at
  the call site and no callback is needed:

      # Callback form: rows are computed per table, in declaration order
      new()
      |> with_table("users")
      |> with_table("posts")
      |> run(MyApp.Repo)

      # Direct form: rows already exist
      new()
      |> put_table("users", users)
      |> run(MyApp.Repo)

  The two forms compose freely — a later `table/2` clause reads rows that
  `put_table/3` added earlier.

  ### Choosing IDs

  You assign primary keys yourself. Blink builds plain maps and hands them to
  PostgreSQL's `COPY`, so it never asks the database to generate an ID and never
  reads one back. An ID is just another value in the map you are building, no
  different from a name or a timestamp — inserting a row is not what gives it
  one. So a later table can reference rows that have not been inserted yet:

      def table(_seeder, "users") do
        [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      end

      def table(seeder, "posts") do
        Enum.map(seeder.tables["users"], fn user ->
          %{id: user.id, title: "Welcome, \#{user.name}", user_id: user.id}
        end)
      end

  Foreign keys are satisfied by insertion order, which follows the order tables
  were declared, so declare parents before children.

  > #### Reset the sequence for serial columns {: .warning}
  >
  > Inserting explicit IDs does not advance a `serial`, `bigserial`, or identity
  > sequence, so the next ordinary insert your application makes can collide with
  > a seeded row. See
  > [Getting Started](getting_started.html#choosing-ids) for the reset query.

  ## Seeders

  Seeders are the central data unit in Blink. A `Seeder` is a struct that holds
  the rows you want to seed, any contextual data you need during the seeding
  process, and internal state that Blink uses to execute the bulk insert.

      %Blink.Seeder{
        tables: %{
          "table_name" => [...]
        },
        context: %{
          "key" => [...]
        },
        table_order: ...,
        table_opts: ...
      }

  All keys in `tables` must match the name of a table in your database. Table
  names can be either atoms or strings.

  ### Tables

  A mapping of table names to lists of rows. These rows will be persisted to the
  database when `run/2` or `run/3` is called.

  ### Context

  Stores arbitrary data needed during the seeding process. This data is
  available when building your seeds but is not inserted into the database by
  `run/2` or `run/3`. Use `with_context/2` to declare context keys and define
  corresponding `context/2` clauses.

  ## Custom Logic for Running the Seeder

  By default, `run/2` and `run/3` bulk insert rows from the seeder into the
  tables of a Postgres database. Internally they use Postgres' `COPY` command.

  There are two ways to customize the insert behavior:

  - Override the default implementation of `run/2` or `run/3`
  - Pass a custom adapter to `run/3` (e.g., for non-Postgres databases)
  """

  alias Blink.Seeder

  @doc """
  Builds and returns the rows to be stored under a table key in the given
  `Seeder`.

  Called internally by `with_table/2` and `with_table/3`. Each table name passed
  to `with_table` must have a corresponding `table/2` clause.

  Data added to a Seeder with `table/2` is inserted into the corresponding
  database table when calling `run/2` or `run/3`.

  The callback can return either a list or a stream of maps. Returning a stream
  enables memory-efficient seeding of large datasets.

  When the callback function is missing, an `ArgumentError` is raised.
  """
  @callback table(seeder :: Seeder.t(), table_name :: Seeder.key()) :: Enumerable.t()

  @doc """
  Builds and returns the data to be stored under a context key in the given
  `Seeder`.

  Called internally by `with_context/2`. Each key passed to `with_context` must
  have a corresponding `context/2` clause.

  `run/2` and `run/3` ignore context data and only insert data from `:tables`.

  When the callback function is missing, an `ArgumentError` is raised.
  """
  @callback context(seeder :: Seeder.t(), key :: Seeder.key()) :: Enumerable.t()

  @doc """
  Specifies how to run the Seeder, performing a bulk insert of the seed data
  from a `Seeder` into the given Ecto repository.

  This callback function is optional, since Blink ships with a default
  implementation.
  """
  @callback run(seeder :: Seeder.t(), repo :: Ecto.Repo.t()) :: :ok
  @callback run(seeder :: Seeder.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) :: :ok

  @optional_callbacks [table: 2, context: 2, run: 2, run: 3]

  defmacro __using__(_) do
    quote do
      @behaviour Blink

      import Seeder, only: [is_key: 1, new: 0]

      import Blink,
        only: [
          from_csv: 1,
          from_csv: 2,
          from_json: 1,
          from_json: 2,
          copy_to_table: 3,
          copy_to_table: 4,
          put_context: 2,
          put_context: 3,
          put_table: 2,
          put_table: 3,
          put_table: 4
        ]

      @doc """
      Declares a table, building its rows with this module's `table/2` clause
      for `table_name`.

      The clause receives the seeder built so far, so it can read tables and
      context declared before it. `opts` takes per-table options (for
      `Blink.Adapter.Postgres`: `:batch_size` and `:concurrency`), which
      override the ones given to `run/3`.

      Raises `Blink.MissingClauseError` when no `table/2` clause matches
      `table_name`.

          new()
          |> with_table("users")
          |> with_table("posts", batch_size: 1_000)
          |> run(MyApp.Repo)
      """
      @spec with_table(seeder :: Seeder.t(), table_name :: Seeder.key(), opts :: Keyword.t()) ::
              Seeder.t()
      def with_table(%Seeder{} = seeder, table_name, opts \\ []) when is_key(table_name) do
        Blink.__with_table__(seeder, table_name, &table/2, opts, __MODULE__)
      end

      @doc """
      Declares a context key, building its value with this module's `context/2`
      clause for `key`.

      Context is available to later clauses via `seeder.context` and is never
      inserted into the database.

      Raises `Blink.MissingClauseError` when no `context/2` clause matches `key`.

          new()
          |> with_context("timestamps")
          |> with_table("users")
          |> run(MyApp.Repo)
      """
      @spec with_context(seeder :: Seeder.t(), key :: Seeder.key()) :: Seeder.t()
      def with_context(%Seeder{} = seeder, key) when is_key(key) do
        Blink.__with_context__(seeder, key, &context/2, __MODULE__)
      end

      @impl true
      @spec table(
              seeder :: Seeder.t(),
              table_name :: Seeder.key()
            ) :: Enumerable.t()
      def table(seeder, table_name)

      @impl true
      def table(%Seeder{}, table_name) do
        raise Blink.MissingClauseError,
          module: __MODULE__,
          callback: :table,
          key: table_name
      end

      @impl true
      def context(%Seeder{}, key) do
        raise Blink.MissingClauseError,
          module: __MODULE__,
          callback: :context,
          key: key
      end

      @impl true
      @spec run(seeder :: Seeder.t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) :: :ok
      defdelegate run(seeder, repo, opts \\ []), to: Seeder

      defoverridable Blink
    end
  end

  @doc false
  def __with_table__(seeder, table_name, builder, opts, module) do
    Seeder.with_table(seeder, table_name, builder, opts)
  rescue
    error in FunctionClauseError ->
      reraise_missing_clause(error, module, :table, table_name, __STACKTRACE__)
  end

  @doc false
  def __with_context__(seeder, key, builder, module) do
    Seeder.with_context(seeder, key, builder)
  rescue
    error in FunctionClauseError ->
      reraise_missing_clause(error, module, :context, key, __STACKTRACE__)
  end

  # A user-defined `table/2` replaces the fallback injected by `__using__`
  # (that is what `defoverridable` means), so a declared-but-unhandled table
  # surfaces as a bare FunctionClauseError rather than the fallback's raise.
  # Only the seeder module's own callback is translated; anything raised from
  # within a clause body propagates untouched.
  @spec reraise_missing_clause(
          error :: Exception.t(),
          module :: module(),
          callback :: :table | :context,
          key :: Seeder.key(),
          stacktrace :: Exception.stacktrace()
        ) :: no_return()
  defp reraise_missing_clause(error, module, callback, key, stacktrace) do
    if error.module == module and error.function == callback and error.arity == 2 do
      reraise Blink.MissingClauseError,
              [module: module, callback: callback, key: key],
              stacktrace
    else
      reraise error, stacktrace
    end
  end

  @doc """
  Adds several `{key, value}` pairs to the seeder's context at once.

  A multi-key form of `put_context/3`; pairs are applied in order and each key
  must be unique (as with `put_context/3`).

  ## Examples

      new()
      |> put_context(user_id: user_id, project_indices: project_indices)
  """
  @spec put_context(seeder :: Seeder.t(), pairs :: [{Seeder.key(), any()}]) :: Seeder.t()
  def put_context(seeder, pairs) when is_list(pairs) do
    Enum.reduce(pairs, seeder, fn {key, value}, acc -> put_context(acc, key, value) end)
  end

  @doc """
  Adds `value` to the seeder's context under `key`.

  A convenience wrapper over `Blink.Seeder.with_context/3` for when the context
  data is already available and you do not want to define a `context/2` callback.
  Raises `ArgumentError` if `key` is already present.

  ## Examples

      new()
      |> put_context(:generated_at, ~U[2024-01-01 00:00:00Z])
  """
  @spec put_context(seeder :: Seeder.t(), key :: Seeder.key(), value :: any()) :: Seeder.t()
  def put_context(seeder, key, value) do
    Seeder.with_context(seeder, key, fn _seeder, _key -> value end)
  end

  @doc """
  Adds several `{table_name, rows}` pairs to the seeder at once.

  A multi-table form of `put_table/3`; tables are added in order (which becomes
  their insertion order) and each name must be unique. Per-table options are not
  supported here — use `put_table/4` when you need them.

  ## Examples

      new()
      |> put_table(users: users, posts: posts)
  """
  @spec put_table(seeder :: Seeder.t(), pairs :: [{Seeder.key(), Enumerable.t()}]) :: Seeder.t()
  def put_table(seeder, pairs) when is_list(pairs) do
    Enum.reduce(pairs, seeder, fn {table_name, rows}, acc -> put_table(acc, table_name, rows) end)
  end

  @doc """
  Adds `rows` to the seeder under `table_name`.

  A convenience wrapper over `Blink.Seeder.with_table/4` for when the rows are
  already available and you do not want to define a `table/2` callback. `rows`
  may be a list or a stream. `opts` takes per-table options (for
  `Blink.Adapter.Postgres`: `:batch_size` and `:concurrency`), forwarded to
  `Blink.Seeder.with_table/4`. Raises `ArgumentError` if `table_name` is
  already present.

  ## Examples

      new()
      |> put_table("users", [%{id: 1, name: "Alice"}])
      |> put_table("events", [%{id: 1, name: "Launch"}], batch_size: 1_000)
  """
  @spec put_table(
          seeder :: Seeder.t(),
          table_name :: Seeder.key(),
          rows :: Enumerable.t(),
          opts :: Keyword.t()
        ) :: Seeder.t()
  def put_table(seeder, table_name, rows, opts \\ []) do
    Seeder.with_table(seeder, table_name, fn _seeder, _table_name -> rows end, opts)
  end

  @doc """
  Copies rows into a database table using database-specific bulk copy commands.

  ## Parameters

    * `rows` - An enumerable (list or stream) of maps where each map represents
      a row to insert. All maps must have the same keys, which correspond to the
      table columns. Using a stream allows for memory-efficient seeding of large
      datasets.
    * `table_name` - The name of the table to insert into (string or atom).
    * `repo` - An Ecto repository module.
    * `opts` - Keyword list of options:
      * `:adapter` - The adapter module to use. Defaults to
        `Blink.Adapter.Postgres`.

      All other options are adapter-specific and validated by the adapter —
      unknown keys raise `ArgumentError`. See `Blink.Adapter.Postgres` for its
      options: `:atomic` (all-or-nothing copy), `:concurrency`, `:batch_size`,
      and `:timeout`.

  ## Returns

    * `:ok` - When the copy operation succeeds

  Raises an exception when the copy operation fails.

  ## Examples

      iex> rows = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> copy_to_table(rows, "users", MyApp.Repo)
      :ok

      # Using a stream for memory-efficient seeding
      iex> stream = Stream.map(1..1_000_000, fn i -> %{id: i, name: "User \#{i}"} end)
      iex> copy_to_table(stream, "users", MyApp.Repo)
      :ok

  ## Notes

  The function assumes all rows have the same structure. Column names are
  extracted from the first row in the enumerable.

  Currently only PostgreSQL is supported via `Blink.Adapter.Postgres`.
  """
  @spec copy_to_table(
          rows :: Enumerable.t(),
          table_name :: String.t(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: :ok
  defdelegate copy_to_table(rows, table_name, repo, opts \\ []), to: Blink.Adapter

  @doc """
  Reads a CSV file and returns a list or stream of maps.

  Each column header becomes a string key in the resulting maps. All values are
  returned as strings.

  ## Parameters

    * `path` - Path to the CSV file (relative or absolute)
    * `opts` - Keyword list of options. Unknown options raise `ArgumentError`:
      * `:headers` - `:infer` to read the header names from the first row
        (default), or a list of names for a file **without** a header row.
        Explicit headers do not skip the first row — on a file that has one,
        the header row comes back as a data map.
      * `:transform` - Function to transform each row map (default: identity)
      * `:stream` - When `true`, returns a stream instead of a list (default:
        `false`)

  ## Examples

      # Read CSV with headers in first row
      from_csv("users.csv")

      # Name the columns of a file that has no header row
      from_csv("users_no_headers.csv", headers: ["id", "name", "email"])

      # Transform values
      from_csv("users.csv", transform: fn row ->
        Map.update!(row, "id", &String.to_integer/1)
      end)

      # Stream for memory-efficient processing
      from_csv("large_users.csv", stream: true)

  ## Returns

  A list of maps, or a stream of maps when `stream: true`.

  ## Notes

  For JSONB columns, prefer leaving the value as the raw JSON string read from
  the CSV. Since CSV values are already strings, an untransformed JSONB column is
  inserted directly, skipping a JSON round trip. Only decode it into a map (via
  `:transform`) when you need to inspect or modify the value before inserting —
  the Postgres adapter will re-encode maps with `Jason.encode!/1` on the way in.
  """
  @spec from_csv(path :: String.t(), opts :: Keyword.t()) :: Enumerable.t()
  defdelegate from_csv(path, opts \\ []), to: Blink.CSV

  @doc """
  Reads a JSON file and returns a list of maps.

  The JSON file must contain an array of objects at the root level. Each object
  becomes a map with string keys.

  ## Parameters

    * `path` - Path to the JSON file
    * `opts` - Keyword list of options. Unknown options raise `ArgumentError`:
      * `:transform` - Function to transform each row map (default: identity)

  ## Examples

      # Read JSON file
      from_json("users.json")

      # Transform values
      from_json("users.json", transform: fn row ->
        Map.update!(row, "id", &String.to_integer/1)
      end)

  ## Returns

  A list of maps.
  """
  @spec from_json(path :: String.t(), opts :: Keyword.t()) :: [map()]
  defdelegate from_json(path, opts \\ []), to: Blink.JSON
end
