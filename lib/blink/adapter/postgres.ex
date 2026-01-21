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

  The adapter implements the `Blink.Adapter` behaviour by streaming data to
  PostgreSQL in CSV format using the pipe delimiter.
  """
  @behaviour Blink.Adapter

  @doc """
  Copies items into a database table using PostgreSQL's COPY command.

  This function uses PostgreSQL's `COPY FROM STDIN` command for efficient bulk
  insertion of data.

  ## Parameters

    * `items` - An enumerable (list or stream) of maps where each map represents
      a row to insert. All maps must have the same keys, which correspond to the
      table columns. Using a stream allows for memory-efficient seeding of large
      datasets.
    * `table_name` - The name of the table to insert into (string or atom).
    * `repo` - An Ecto repository module configured with a Postgres adapter.
    * `opts` - Keyword list of options:
      * `:batch_size` - Number of rows per batch when streaming (default: 10,000).
        Only applies to streams; lists are sent as a single batch.

  ## Returns

    * `:ok` - When the copy operation succeeds

  Raises an exception when the copy operation fails.

  ## Examples

      iex> items = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> Blink.Adapter.Postgres.call(items, "users", MyApp.Repo)
      :ok

      # Using a stream for memory-efficient seeding
      iex> stream = Stream.map(1..1_000_000, fn i -> %{id: i, name: "User \#{i}"} end)
      iex> Blink.Adapter.Postgres.call(stream, "users", MyApp.Repo)
      :ok

  ## Notes

  The function assumes all items have the same keys. NULL values are represented
  as `\\N` in the CSV format. Nested maps are automatically JSON-encoded for
  JSONB columns.
  """
  @impl true
  @spec call(
          items :: Enumerable.t(),
          table_name :: String.t(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: :ok
  def call(items, table_name, repo, opts \\ []) when is_binary(table_name) and is_list(opts) do
    pattern = escape_pattern()
    batch_size = Keyword.get(opts, :batch_size, 10_000)

    items
    |> chunk_items(batch_size)
    |> Enum.reduce(nil, fn
      [], acc ->
        acc

      [first | _] = batch, nil ->
        columns = Map.keys(first)
        stream = copy_stream(repo, table_name, columns)
        csv_rows = Enum.map(batch, &row_to_csv(&1, columns, pattern))
        Enum.into([csv_rows], stream)
        {columns, stream}

      batch, {columns, stream} ->
        csv_rows = Enum.map(batch, &row_to_csv(&1, columns, pattern))
        Enum.into([csv_rows], stream)
        {columns, stream}
    end)

    :ok
  end

  defp copy_stream(repo, table_name, columns) do
    columns_string = Enum.map_join(columns, ", ", &~s("#{&1}"))

    Ecto.Adapters.SQL.stream(
      repo,
      """
      COPY #{table_name} (#{columns_string})
      FROM STDIN
      WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
      """
    )
  end

  defp escape_pattern do
    case Process.get(:blink_escape_pattern) do
      nil ->
        pattern = :binary.compile_pattern(["|", "\"", "\n", "\r", "\\"])
        Process.put(:blink_escape_pattern, pattern)
        pattern

      pattern ->
        pattern
    end
  end

  defp chunk_items(items, _batch_size) when is_list(items), do: [items]
  defp chunk_items(items, batch_size), do: Stream.chunk_every(items, batch_size)

  defp row_to_csv(row, [col], pattern) do
    [encode_value(Map.get(row, col), pattern), "\n"]
  end

  defp row_to_csv(row, [col | rest], pattern) do
    [encode_value(Map.get(row, col), pattern), "|" | row_to_csv(row, rest, pattern)]
  end

  defp encode_value(nil, _pattern), do: "\\N"
  defp encode_value(value, _pattern) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value, pattern) when is_binary(value), do: escape(value, pattern)
  defp encode_value(value, pattern) when is_map(value), do: escape(Jason.encode!(value), pattern)
  defp encode_value(value, pattern), do: escape(to_string(value), pattern)

  defp escape(value, pattern) do
    case :binary.match(value, pattern) do
      :nomatch -> value
      _ -> ["\"", String.replace(value, "\"", "\"\""), "\""]
    end
  end
end
