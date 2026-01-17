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
  PostgreSQL in CSV format using the pipe delimiter.
  """
  @behaviour Blink.Adapter

  import Blink.Seeder, only: [is_key: 1]

  @doc """
  Executes a bulk copy operation using PostgreSQL's COPY command.

  This is the entry point for the Postgres adapter.
  """
  @impl true
  @spec call(
          items :: Enumerable.t(),
          table_name :: Blink.Seeder.key(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: {:ok, any()} | {:error, Exception.t()}
  def call(items, table_name, repo, opts \\ []) do
    copy_to_table(items, table_name, repo, opts)
  end

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

    * `{:ok, :empty}` - When the items enumerable is empty
    * `{:ok, result}` - When the copy operation succeeds
    * `{:error, exception}` - When the copy operation fails

  ## Examples

      iex> items = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> Blink.Adapter.Postgres.copy_to_table(items, "users", MyApp.Repo)
      {:ok, _result}

      # Using a stream for memory-efficient seeding
      iex> stream = Stream.map(1..1_000_000, fn i -> %{id: i, name: "User \#{i}"} end)
      iex> Blink.Adapter.Postgres.copy_to_table(stream, "users", MyApp.Repo)
      {:ok, _result}

  ## Notes

  The function assumes all items have the same keys. NULL values are represented
  as `\\N` in the CSV format. Nested maps are automatically JSON-encoded for
  JSONB columns.
  """
  @spec copy_to_table(
          items :: Enumerable.t(),
          table_name :: Blink.Seeder.key(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: {:ok, :inserted} | {:error, Exception.t()}
  def copy_to_table(items, table_name, repo, opts \\ [])
      when is_key(table_name) and is_atom(repo) and is_list(opts) do
    # Take the first item to get columns; this works for both lists and streams
    case Enum.take(items, 1) do
      [] ->
        {:ok, :empty}

      [first | _] ->
        columns = Map.keys(first)
        columns_string = Enum.map_join(columns, ", ", &~s("#{&1}"))

        repo_stream =
          Ecto.Adapters.SQL.stream(
            repo,
            """
            COPY #{key_to_string(table_name)} (#{columns_string})
            FROM STDIN
            WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
            """
          )

        pattern = escape_pattern()
        batch_size = Keyword.get(opts, :batch_size, 10_000)

        items
        |> chunk_items(batch_size)
        |> Stream.into(repo_stream, fn batch ->
          Enum.map(batch, fn row ->
            row_to_csv(row, columns, pattern)
          end)
        end)
        |> Stream.run()

        {:ok, :inserted}
    end
  rescue
    error -> {:error, error}
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key

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
