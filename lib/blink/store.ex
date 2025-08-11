defmodule Blink.Store do
  @moduledoc """
  The central data structure passed through the Blink seeding pipeline.

  A `Store` is a container for two kinds of data:

    * `:seeds` — data that you intend to seed.
    * `:helpers` — transient data available to pipeline steps but ignored during
      seeding.
  """

  defstruct seeds: %{}, helpers: %{}
  @behaviour Access

  @type t :: %__MODULE__{
          seeds: map(),
          helpers: map()
        }

  @impl Access
  def fetch(%__MODULE__{} = store, key) when key in [:seeds, :helpers] do
    {:ok, Map.get(store, key)}
  end

  def fetch(_, _), do: :error

  @impl Access
  def get_and_update(%__MODULE__{} = store, key, fun) when key in [:seeds, :helpers] do
    {get_value, new_value} = fun.(Map.get(store, key))
    {get_value, Map.put(store, key, new_value)}
  end

  def get_and_update(store, _, _), do: {nil, store}

  @impl Access
  def pop(%__MODULE__{} = store, key) when key in [:seeds, :helpers] do
    {Map.get(store, key), Map.put(store, key, nil)}
  end

  def pop(store, _), do: {nil, store}
end
