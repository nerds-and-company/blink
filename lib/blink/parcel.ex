defmodule Blink.Parcel do
  @moduledoc """
  The central data structure passed through the Blink seeding pipeline.

  A `Parcel` is a container for two kinds of data:

    * `:seeds` — the data that will be seeded.
    * `:context` — transient data available to pipeline steps but ignored during
      seeding.
  """

  defstruct seeds: %{}, context: %{}
  @behaviour Access

  @type t :: %__MODULE__{
          seeds: map(),
          context: map()
        }

  @impl Access
  def fetch(%__MODULE__{} = parcel, key) when key in [:seeds, :context] do
    {:ok, Map.get(parcel, key)}
  end

  def fetch(_, _), do: :error

  @impl Access
  def get_and_update(%__MODULE__{} = parcel, key, fun) when key in [:seeds, :context] do
    {get_value, new_value} = fun.(Map.get(parcel, key))
    {get_value, Map.put(parcel, key, new_value)}
  end

  def get_and_update(parcel, _, _), do: {nil, parcel}

  @impl Access
  def pop(%__MODULE__{} = parcel, key) when key in [:seeds, :context] do
    {Map.get(parcel, key), Map.put(parcel, key, nil)}
  end

  def pop(parcel, _), do: {nil, parcel}
end
