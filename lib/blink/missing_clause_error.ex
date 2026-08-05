defmodule Blink.MissingClauseError do
  @moduledoc """
  Raised when a table or context is declared but no callback clause matches it.

  Every `with_table/2` call needs a `table/2` clause for that table name, and
  every `with_context/2` call needs a `context/2` clause for that key. The
  message names the missing key and shows the clause to add.
  """

  defexception [:module, :callback, :key]

  @type t :: %__MODULE__{
          module: module(),
          callback: :table | :context,
          key: Blink.Seeder.key()
        }

  @impl true
  def message(%__MODULE__{module: module, callback: callback, key: key}) do
    """
    #{inspect(module)} declares #{inspect(key)} with #{declarer(callback)}, but no \
    #{callback}/2 clause matches #{inspect(key)}.

    Add a clause to #{inspect(module)}:

        def #{callback}(_seeder, #{inspect(key)}) do
          #{placeholder(callback, key)}
        end
    """
  end

  defp declarer(:table), do: "with_table/2"
  defp declarer(:context), do: "with_context/2"

  defp placeholder(:table, key), do: "# a list or stream of maps to insert into #{inspect(key)}"
  defp placeholder(:context, key), do: "# the value to store under #{inspect(key)}"
end
