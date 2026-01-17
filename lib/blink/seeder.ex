defmodule Blink.Seeder do
  @moduledoc """
  The central data structure and operations for the Blink seeding pipeline.

  This module provides the `Seeder` struct and functions for building and
  inserting seed data into your database.

  A `Seeder` holds:

    * `:tables` — data that will be inserted into the database.
    * `:table_order` - the order in which tables were added, used to ensure
      inserts respect foreign key constraints.
    * `:context` — auxiliary data available while constructing the `Seeder`, and
      will not be inserted into the database.
  """

  @behaviour Access

  defstruct tables: %{}, table_order: [], context: %{}

  @type key :: binary() | atom()

  @type t :: %__MODULE__{
          tables: map(),
          table_order: [key()],
          context: map()
        }

  @type empty :: %__MODULE__{
          tables: %{},
          table_order: [],
          context: %{}
        }

  defguard is_key(key) when is_binary(key) or is_atom(key)

  @doc """
  Creates an empty Seeder.

  ## Example

      iex> Blink.Seeder.new()
      %Blink.Seeder{tables: %{}, table_order: [], context: %{}}
  """
  @spec new() :: empty()
  def new do
    %__MODULE__{}
  end

  @doc """
  Loads a table into the seeder by calling the provided builder function.

  The builder function should take a seeder and table name and return an
  enumerable (list or stream) of maps representing the table data.
  """
  @spec with_table(
          seeder :: t(),
          table_name :: key(),
          builder :: (t(), key() -> Enumerable.t())
        ) :: t()
  def with_table(%__MODULE__{} = seeder, table_name, builder)
      when is_key(table_name) and is_function(builder, 2) do
    raise_if_key_exists(seeder, table_name, :tables)

    seeder
    |> put_in([:tables, table_name], builder.(seeder, table_name))
    |> update_in([:table_order], fn order -> order ++ [table_name] end)
  end

  @doc """
  Loads context into the seeder by calling the provided builder function.

  The builder function should take a seeder and key and return the context data.
  """
  @spec with_context(
          seeder :: t(),
          key :: key(),
          builder :: (t(), key() -> any())
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

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key

  @doc """
  Runs the seeder, inserting all table records into the given repository.
  Iterates over the tables in order when seeding the database.

  The repo parameter must be a module that implements the Ecto.Repo
  behaviour and is configured with a Postgres adapter (e.g.,
  Ecto.Adapters.Postgres).

  Data stored in the Seeder's context is ignored.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the transaction to
      complete. Defaults to 15000 (15 seconds). Set to `:infinity` to disable
      the timeout.
    * `:batch_size` - Number of rows per batch when streaming (default: 10,000).
      Only applies to streams; lists are sent as a single batch. Adjust based
      on your data size and memory constraints.

  ## Examples

      # With custom timeout for large datasets
      run(seeder, MyApp.Repo, timeout: 60_000)

      # Disable timeout entirely
      run(seeder, MyApp.Repo, timeout: :infinity)

      # Custom batch size for streams
      run(seeder, MyApp.Repo, batch_size: 5_000)

  """
  @spec run(seeder :: t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
          {:ok, any()} | {:error, any()}
  def run(%__MODULE__{} = seeder, repo, opts \\ []) when is_atom(repo) do
    timeout = Keyword.get(opts, :timeout, 15_000)

    repo.transact(
      fn ->
        Enum.each(seeder.table_order, fn table_name ->
          items = Map.fetch!(seeder.tables, table_name)

          case Blink.copy_to_table(items, table_name, repo, opts) do
            {:ok, _} -> :ok
            {:error, reason} -> raise reason
          end
        end)

        {:ok, :inserted}
      end,
      timeout: timeout
    )
  rescue
    e -> {:error, e}
  end

  @impl Access
  def fetch(%__MODULE__{} = seeder, key) when key in [:tables, :table_order, :context] do
    {:ok, Map.get(seeder, key)}
  end

  def fetch(_, _), do: :error

  @impl Access
  def get_and_update(%__MODULE__{} = seeder, key, fun)
      when key in [:tables, :table_order, :context] do
    {get_value, new_value} = fun.(Map.get(seeder, key))
    {get_value, Map.put(seeder, key, new_value)}
  end

  def get_and_update(seeder, _, _), do: {nil, seeder}

  @impl Access
  def pop(%__MODULE__{} = seeder, key) when key in [:tables, :context] do
    {Map.get(seeder, key), Map.put(seeder, key, %{})}
  end

  def pop(%__MODULE__{} = seeder, :table_order) do
    {seeder.table_order, Map.put(seeder, :table_order, [])}
  end

  def pop(%__MODULE__{} = seeder, _), do: {nil, seeder}
end
