defmodule Blink.Store do
  @moduledoc """
  The central data structure and operations for the Blink seeding pipeline.

  This module provides the `Store` struct and functions for building and
  inserting seed data into your database.

  A `Store` holds:

    * `:tables` — data that will be inserted into the database.
    * `:table_order` - the order in which tables were added, used to ensure
      inserts respect foreign key constraints.
    * `:context` — auxiliary data available while constructing the `Store`, and
      will not be inserted into the database.
  """

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
  Creates an empty Store.

  ## Example

      iex> Blink.Store.new()
      %Blink.Store{tables: %{}, table_order: [], context: %{}}
  """
  @spec new() :: empty()
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds a table to the store by calling the provided builder function.

  The builder function should take a store and table name and return a list of
  maps representing the table data.
  """
  @spec add_table(
          store :: t(),
          table_name :: key(),
          builder :: (t(), key() -> [map()])
        ) :: t()
  def add_table(%__MODULE__{} = store, table_name, builder)
      when is_key(table_name) and is_function(builder, 2) do
    table_name = to_string(table_name)
    raise_if_key_exists(store, table_name, :tables)

    %{
      store
      | tables: Map.put(store.tables, table_name, builder.(store, table_name)),
        table_order: store.table_order ++ [table_name]
    }
  end

  @doc """
  Adds context to the store by calling the provided builder function.

  The builder function should take a store and key and return the context data.
  """
  @spec add_context(
          store :: t(),
          key :: key(),
          builder :: (t(), key() -> any())
        ) :: t()
  def add_context(%__MODULE__{} = store, key, builder)
      when is_key(key) and is_function(builder, 2) do
    key = to_string(key)
    raise_if_key_exists(store, key, :context)

    %{store | context: Map.put(store.context, key, builder.(store, key))}
  end

  defp raise_if_key_exists(%__MODULE__{} = store, key, target) when is_binary(key) do
    with %{^target => %{^key => _}} <- store do
      raise ArgumentError, "key already exists in `#{inspect(target)}` of Store: #{key}"
    end

    :ok
  end

  @doc """
  Inserts all table records from a Store into the given repository.
  Iterates over the tables in order when seeding the database.

  The repo parameter must be a module that implements the Ecto.Repo
  behaviour and is configured with a Postgres adapter (e.g.,
  Ecto.Adapters.Postgres).

  Data stored in the Store's context is ignored.
  """
  @spec insert(store :: t(), repo :: Ecto.Repo.t(), opts :: Keyword.t()) ::
          {:ok, any()} | {:error, any()}
  def insert(%__MODULE__{} = store, repo, opts \\ []) when is_atom(repo) do
    repo.transact(fn ->
      Enum.each(store.table_order, fn table_name ->
        items = Map.fetch!(store.tables, table_name)

        Blink.copy_to_table(items, table_name, repo, opts)
        :ok
      end)

      {:ok, :inserted}
    end)
  end
end
