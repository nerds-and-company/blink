defmodule Blink.RowError do
  @moduledoc """
  Raised when a row's keys differ from the first row's keys.

  The Postgres adapter reads the table's column list from the keys of the
  first row, so every row must have exactly the same keys. Without this check
  a key missing from a later row would be inserted as `NULL`, and an extra key
  would be silently dropped. The message names the table, the offending row's
  index, and the keys that differ.
  """

  defexception [:table_name, :index, :missing, :extra]

  @type t :: %__MODULE__{
          table_name: String.t(),
          index: non_neg_integer(),
          missing: [term()],
          extra: [term()]
        }

  @impl true
  def message(%__MODULE__{table_name: table_name, index: index} = error) do
    """
    the row at index #{index} of table #{inspect(table_name)} does not have the \
    same keys as the first row: it #{describe(error)}.

    Blink reads the column list from the keys of the first row, so every row \
    must have exactly the same keys. A missing key would be inserted as NULL; \
    an extra key would be silently dropped.
    """
  end

  defp describe(%{missing: missing, extra: []}), do: "is missing #{inspect(missing)}"
  defp describe(%{missing: [], extra: extra}), do: "has extra keys #{inspect(extra)}"

  defp describe(%{missing: missing, extra: extra}),
    do: "is missing #{inspect(missing)} and has extra keys #{inspect(extra)}"
end
