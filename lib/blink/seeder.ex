defmodule Blink.Seeder do
  @moduledoc """
  The central data structure and operations for the Blink seeding pipeline.

  This module provides the `Seeder` struct and functions for building and
  inserting seed data into your database.

  A `Seeder` holds:

    * `:tables` — data that will be inserted into the database.
    * `:table_order` - the insertion order for tables.
    * `:table_opts` — per-table options (`:batch_size`, `:concurrency`) used
      during the copy operation.
    * `:context` — auxiliary data used while building the seeder, not inserted.
  """

  @behaviour Access

  defstruct tables: %{}, table_order: [], table_opts: %{}, context: %{}

  @type key :: binary() | atom()

  @type table_opts :: Keyword.t()

  # Options that configure the whole run rather than one table's copy. Allowing
  # them per-table would let a single table silently break a run-level
  # guarantee — e.g. a per-table `atomic: false` inside an atomic seed would
  # copy that table over parallel connections outside the run's transaction.
  @reserved_table_opts [:adapter, :atomic, :timeout]

  @type t :: %__MODULE__{
          tables: %{optional(key()) => Enumerable.t()},
          table_order: [key()],
          table_opts: %{optional(key()) => table_opts()},
          context: map()
        }

  @type empty :: %__MODULE__{
          tables: %{},
          table_order: [],
          table_opts: %{},
          context: %{}
        }

  defguard is_key(key) when is_binary(key) or is_atom(key)

  @doc """
  Creates an empty Seeder.

  ## Example

      iex> Blink.Seeder.new()
      %Blink.Seeder{tables: %{}, table_order: [], table_opts: %{}, context: %{}}
  """
  @spec new() :: empty()
  def new do
    %__MODULE__{}
  end

  @doc """
  Loads a table into the seeder by calling the provided builder function.

  This is the low-level form, which takes an explicit builder. If your module
  calls `use Blink`, call `with_table/2` or `with_table/3` on that module
  instead — it dispatches to your `table/2` clause for you and reports a missing
  clause as a `Blink.MissingClauseError`. See `Blink` for the full seeder API.

  The builder function should take a seeder and table name and return an
  enumerable (list or stream) of maps representing the table data.

  ## Options

  Options given here override the ones passed to `run/3` for this table only.
  They are forwarded to the adapter, which owns and validates them — unknown
  keys and invalid values raise `ArgumentError` when the seeder runs. The
  run-level options `:adapter`, `:atomic`, and `:timeout` configure the whole
  run and raise `ArgumentError` here.

  For `Blink.Adapter.Postgres` the per-table options are:

    * `:batch_size` - Number of rows per batch. Overrides `:batch_size` in
      `run/3`.
    * `:concurrency` - Number of parallel workers. Overrides `:concurrency` in
      `run/3`.

  ## Examples

      # Without options (uses options from `run/3`)
      Seeder.with_table(seeder, "users", &table/2)

      # With custom batch size and concurrency
      Seeder.with_table(seeder, "users", &table/2, batch_size: 1_000, concurrency: 2)

  """
  @spec with_table(
          seeder :: t(),
          table_name :: key(),
          builder :: (seeder :: t(), table_name :: key() -> Enumerable.t()),
          opts :: table_opts()
        ) :: t()
  def with_table(%__MODULE__{} = seeder, table_name, builder, opts \\ [])
      when is_key(table_name) and is_function(builder, 2) do
    raise_if_key_exists(seeder, table_name, :tables)
    reject_reserved_opts!(opts)

    seeder
    |> put_in([:tables, table_name], builder.(seeder, table_name))
    |> update_in([:table_order], fn order -> order ++ [table_name] end)
    |> put_in([:table_opts, table_name], opts)
  end

  @doc """
  Loads context into the seeder by calling the provided builder function.

  This is the low-level form, which takes an explicit builder. If your module
  calls `use Blink`, call `with_context/2` on that module instead — it
  dispatches to your `context/2` clause for you and reports a missing clause as
  a `Blink.MissingClauseError`. See `Blink` for the full seeder API.

  The builder function should take a seeder and key and return the context data.
  """
  @spec with_context(
          seeder :: t(),
          key :: key(),
          builder :: (seeder :: t(), key :: key() -> any())
        ) :: t()
  def with_context(%__MODULE__{} = seeder, key, builder)
      when is_key(key) and is_function(builder, 2) do
    raise_if_key_exists(seeder, key, :context)

    put_in(seeder.context[key], builder.(seeder, key))
  end

  defp raise_if_key_exists(%__MODULE__{} = seeder, key, target) do
    keys_as_strings =
      seeder[target]
      |> Map.keys()
      |> Enum.map(&key_to_string/1)

    if key_to_string(key) in keys_as_strings do
      raise ArgumentError, "key already exists in `#{inspect(target)}` of Seeder: #{key}"
    end
  end

  defp reject_reserved_opts!(opts) do
    case Enum.filter(@reserved_table_opts, &Keyword.has_key?(opts, &1)) do
      [] ->
        :ok

      reserved ->
        raise ArgumentError,
              "#{inspect(reserved)} cannot be set per-table; " <>
                "pass run-level options to `run/3` instead"
    end
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key

  @doc """
  Runs the seeder, inserting all table records into the given repository.
  Iterates over the tables in order when seeding the database.

  The repo parameter must be a module that implements the Ecto.Repo behaviour
  and is configured with a Postgres adapter (e.g., Ecto.Adapters.Postgres).

  Data stored in the Seeder's context is ignored.

  ## Options

  `:adapter` selects the adapter and `:atomic` additionally tells the seeder
  whether to open a transaction; every option is forwarded to the adapter,
  which owns and validates its option vocabulary — unknown keys and invalid
  values raise `ArgumentError`.

    * `:atomic` - Whether the seed is all-or-nothing (default: `false`). When
      `true`, every table is copied over a single database connection inside
      one transaction: if any table fails, all tables are rolled back. When
      `false`, batches are copied over parallel connections for maximum speed,
      and a failure partway through can leave earlier batches and tables
      committed.
    * `:timeout` - The time in milliseconds allowed for each database
      operation (default: 15,000). Set to `:infinity` to disable it. See
      `Blink.Adapter.Postgres` for the exact semantics in each mode.
    * `:adapter` - The adapter module to use (default:
      `Blink.Adapter.Postgres`).

  The following options are specific to `Blink.Adapter.Postgres`:

    * `:batch_size` - Number of rows per batch (default: 8,000). Can be
      overridden per-table via `with_table/4`.
    * `:concurrency` - Number of parallel workers: COPY connections when
      `atomic: false` (configure the repo's `pool_size` accordingly), row
      encoders feeding the single connection when `atomic: true`. See
      `Blink.Adapter.Postgres` for defaults. Can be overridden per-table via
      `with_table/4`.

  ## Atomicity

  Seeds are fast by default and atomic on request: pass `atomic: true` for
  all-or-nothing seeding. `:atomic` and `:timeout` apply to the whole run and
  cannot be overridden per-table.

  ## Returns

    * `:ok` - When all tables have been seeded successfully

  Raises an exception when the seeding operation fails.

  ## Examples

      # All-or-nothing seeding
      run(seeder, MyApp.Repo, atomic: true)

      # With custom timeout
      run(seeder, MyApp.Repo, timeout: 60_000)

      # With custom batch size and concurrency
      run(seeder, MyApp.Repo, batch_size: 5_000, concurrency: 4)

  """
  @spec run(seeder :: t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) :: :ok
  def run(%__MODULE__{} = seeder, repo, opts \\ []) when is_atom(repo) do
    atomic = Keyword.get(opts, :atomic, false)

    copy_tables = fn ->
      Enum.each(seeder.table_order, fn table_name ->
        items = Map.fetch!(seeder.tables, table_name)
        table_opts = Map.fetch!(seeder.table_opts, table_name)
        merged_opts = Keyword.merge(opts, table_opts)

        Blink.copy_to_table(items, key_to_string(table_name), repo, merged_opts)
      end)
    end

    if atomic do
      # The checkout timeout is :infinity because this connection is held for
      # the whole seed; each database operation is bounded by :timeout instead
      # (see Blink.Adapter.Postgres).
      repo.transaction(copy_tables, timeout: :infinity)
    else
      copy_tables.()
    end

    :ok
  end

  @impl Access
  def fetch(%__MODULE__{} = seeder, key)
      when key in [:tables, :table_order, :table_opts, :context] do
    {:ok, Map.get(seeder, key)}
  end

  def fetch(_, _), do: :error

  @impl Access
  def get_and_update(%__MODULE__{} = seeder, key, fun)
      when key in [:tables, :table_order, :table_opts, :context] do
    {get_value, new_value} = fun.(Map.get(seeder, key))
    {get_value, Map.put(seeder, key, new_value)}
  end

  def get_and_update(seeder, _, _), do: {nil, seeder}

  @impl Access
  def pop(%__MODULE__{} = seeder, key) when key in [:tables, :table_opts, :context] do
    {Map.get(seeder, key), Map.put(seeder, key, %{})}
  end

  def pop(%__MODULE__{} = seeder, :table_order) do
    {seeder.table_order, Map.put(seeder, :table_order, [])}
  end

  def pop(%__MODULE__{} = seeder, _), do: {nil, seeder}
end
