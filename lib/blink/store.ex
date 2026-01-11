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
    raise_if_key_exists(store, table_name, :tables)

    store
    |> put_in([:tables, table_name], builder.(store, table_name))
    |> update_in([:table_order], fn order -> order ++ [table_name] end)
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
    raise_if_key_exists(store, key, :context)

    put_in(store.context[key], builder.(store, key))
  end

  defp raise_if_key_exists(%__MODULE__{} = store, key, target) do
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

        case Blink.copy_to_table(items, table_name, repo, opts) do
          {:ok, _} -> :ok
          {:error, reason} -> raise reason
        end
      end)

      {:ok, :inserted}
    end)
  rescue
    e -> {:error, e}
  end

  @impl Access
  def fetch(%__MODULE__{} = store, key) when key in [:tables, :table_order, :context] do
    {:ok, Map.get(store, key)}
  end

  def fetch(_, _), do: :error

  @impl Access
  def get_and_update(%__MODULE__{} = store, key, fun)
      when key in [:tables, :table_order, :context] do
    {get_value, new_value} = fun.(Map.get(store, key))
    {get_value, Map.put(store, key, new_value)}
  end

  def get_and_update(store, _, _), do: {nil, store}

  @impl Access
  def pop(%__MODULE__{} = store, key) when key in [:tables, :context] do
    {Map.get(store, key), Map.put(store, key, %{})}
  end

  def pop(%__MODULE__{} = store, :table_order) do
    {store.table_order, Map.put(store, :table_order, [])}
  end

  def pop(store, _), do: {nil, store}
end
