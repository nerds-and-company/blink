defmodule Blink.Adapter.Postgres do
  @moduledoc """
  PostgreSQL adapter for Blink bulk copy operations.

  This adapter uses PostgreSQL's `COPY FROM STDIN` command for efficient bulk
  insertion of data. It is the default adapter used by Blink.

  ## Usage

  This adapter is used automatically by default:

      Blink.copy_to_table(items, "users", MyApp.Repo)

  Or explicitly:

      Blink.copy_to_table(items, "users", MyApp.Repo, adapter: Blink.Adapter.Postgres)

  ## Implementation

  The adapter implements the `Blink.Adapter` behavior by streaming data to
  PostgreSQL in CSV format using the pipe delimiter. It batches data to minimize
  memory usage while maintaining high performance.
  """
  @behaviour Blink.Adapter

  import Blink.Store, only: [is_key: 1]

  @default_batch_size 900

  @doc """
  Executes a bulk copy operation using PostgreSQL's COPY command.

  This is the entry point for the Postgres adapter.
  """
  @impl true
  @spec call(
          items :: [map()],
          table_name :: Blink.Store.key(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: {:ok, any()} | {:error, Exception.t()}
  def call(items, table_name, repo, opts \\ []) do
    copy_to_table(items, table_name, repo, opts)
  end

  @doc """
  Copies a list of items into a database table using PostgreSQL's COPY command.

  This function uses PostgreSQL's `COPY FROM STDIN` command for efficient bulk
  insertion of data. Items are streamed to the database in batches to minimize
  memory usage.

  ## Parameters

    * `items` - A list of maps where each map represents a row to insert. All
      maps must have the same keys, which correspond to the table columns.
    * `table_name` - The name of the table to insert into (string or atom).
    * `repo` - An Ecto repository module configured with a Postgres adapter.
    * `opts` - Keyword list of options:
      * `:batch_size` - Number of rows to send per batch (default: 900). Set to
        `:infinity` to disable batching and send all rows at once for maximum
        speed.

  ## Returns

    * `{:ok, :empty}` - When the items list is empty
    * `{:ok, result}` - When the copy operation succeeds
    * `{:error, exception}` - When the copy operation fails

  ## Examples

      iex> items = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> Blink.Adapter.Postgres.copy_to_table(items, "users", MyApp.Repo, batch_size: 1000)
      {:ok, _result}

      # Disable batching for maximum speed (uses more memory)
      iex> Blink.Adapter.Postgres.copy_to_table(items, "users", MyApp.Repo, batch_size: :infinity)
      {:ok, _result}

  ## Notes

  The function assumes all items have the same keys. NULL values are represented
  as `\\N` in the CSV format.
  """
  @spec copy_to_table(
          items :: Enumerable.t(map()),
          table_name :: Blink.Store.key(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: Enumerable.t() | :empty
  def copy_to_table(items, table_name, repo, opts \\ [])
      when is_key(table_name) and is_atom(repo) and is_list(opts) do
    if Enum.empty?(items) do
      :empty
    else
      # Get columns from the first item
      {first, rest} = take_first(items)
      columns = Map.keys(first)
      columns_string = Enum.map_join(columns, ", ", &~s("#{&1}"))

      items = Stream.concat([first], rest)

      stream =
        Ecto.Adapters.SQL.stream(
          repo,
          """
          COPY #{key_to_string(table_name)} (#{columns_string})
          FROM STDIN
          WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
          """
        )

      batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

      result =
        items
        |> maybe_chunk(batch_size)
        |> Enum.into(stream, fn chunk ->
          Enum.map(chunk, fn row ->
            ["|" | row_iodata] =
              Enum.flat_map(columns, fn col -> ["|", format_csv_value(Map.fetch!(row, col))] end)

            [row_iodata, "\n"]
          end)
        end)

      result
    end
  end

  defp maybe_chunk(items, :infinity), do: [Enum.to_list(items)]

  defp maybe_chunk(items, batch_size) when is_integer(batch_size) and batch_size > 0 do
    Stream.chunk_every(items, batch_size)
  end

  defp format_csv_value(nil), do: "\\N"
  defp format_csv_value("\\N"), do: "\\\\N"
  defp format_csv_value(value) when is_binary(value), do: escape(value)
  defp format_csv_value(value), do: escape(to_string(value))

  defp escape(string) do
    if Regex.match?(~r/\||"/, string) do
      [?", String.replace(string, "\"", "\"\""), ?"]
    else
      string
    end
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key

  def take_first(stream) do
    streamf = fn acc, func -> Enumerable.reduce(stream, acc, func) end
    clos = fn acc -> streamf.(acc, fn elem, _acc -> {:suspend, elem} end) end
    {:suspended, first, clos} = clos.({:cont, []})
    {first, &enumerable_reduce(clos, &1, &2)}
  end

  def enumerable_reduce(clos, {:halt, acc}, _fun) do
    clos.({:halt, acc})
  end

  def enumerable_reduce(clos, {:suspend, acc}, fun) do
    {:suspended, acc, &enumerable_reduce(clos, &1, fun)}
  end

  def enumerable_reduce(clos, {:cont, acc}, fun) do
    case clos.({:cont, []}) do
      {:suspended, value, clos} ->
        acc = fun.(value, acc)
        enumerable_reduce(clos, acc, fun)

      {tag, _} ->
        {tag, acc}
    end
  end
end
