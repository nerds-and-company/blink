defmodule Blink.Adapter.Postgres do
  @moduledoc false
  @behaviour Blink.Adapter

  @default_batch_size 900

  defguardp is_table_name(table_name)
            when is_binary(table_name) or is_atom(table_name)

  @doc """
  Executes a bulk copy operation using PostgreSQL's COPY command.

  This is the entry point for the Postgres adapter.
  """
  @impl true
  @spec call(
          items :: [map()],
          table_name :: binary() | atom(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: {:ok, :empty} | {:ok, any()}
  def call(items, table_name, repo, opts \\ []) do
    copy_to_table(items, table_name, repo, opts)
  end

  @doc """
  Copies a list of items into a database table using PostgreSQL's COPY command.

  This function uses PostgreSQL's `COPY FROM STDIN` command for efficient bulk
  insertion of data. Items are streamed to the database in batches to minimize
  memory usage.

  ## Parameters

    * `items` - A list of maps where each map represents a row to insert. All maps
      must have the same keys, which correspond to the table columns.
    * `table_name` - The name of the table to insert into (string or atom).
    * `repo` - An Ecto repository module configured with a Postgres adapter.
    * `opts` - Keyword list of options:
      * `:batch_size` - Number of rows to send per batch (default: 900)

  ## Returns

    * `{:ok, :empty}` - When the items list is empty
    * `{:ok, result}` - When the copy operation succeeds

  ## Examples

      iex> items = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> Blink.Adapter.Postgres.copy_to_table(items, "users", MyApp.Repo, batch_size: 1000)
      {:ok, _result}

  ## Notes

  The function assumes all items have the same structure. Column names are
  extracted from the first item in the list. NULL values are represented as `\\N`
  in the CSV format.
  """
  @spec copy_to_table(
          items :: [map()],
          table_name :: binary() | atom(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: {:ok, :empty} | {:ok, any()}
  def copy_to_table(items, table_name, repo, opts \\ [])
      when is_list(items) and is_table_name(table_name) and is_atom(repo) and
             is_list(opts) do
    # Skip if no items to insert
    if Enum.empty?(items) do
      {:ok, :empty}
    else
      # Get columns from the first item
      columns = items |> List.first() |> Map.keys()
      columns_string = Enum.map_join(columns, ", ", &~s("#{&1}"))

      stream =
        Ecto.Adapters.SQL.stream(
          repo,
          """
          COPY #{key_to_string(table_name)} (#{columns_string})
          FROM STDIN
          WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
          """
        )

      result =
        items
        |> Stream.chunk_every(Keyword.get(opts, :batch_size, @default_batch_size))
        |> Enum.into(stream, fn chunk ->
          chunk
          |> Enum.map(fn row ->
            row_iodata =
              columns
              |> Enum.map(fn col -> format_csv_value(Map.get(row, col)) end)
              |> Enum.intersperse("|")

            [row_iodata, "\n"]
          end)
          |> IO.iodata_to_binary()
        end)

      {:ok, result}
    end
  end

  defp format_csv_value(nil), do: "\\N"
  defp format_csv_value(value) when is_binary(value), do: value
  defp format_csv_value(value), do: to_string(value)

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
end
