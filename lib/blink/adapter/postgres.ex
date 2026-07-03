defmodule Blink.Adapter.Postgres do
  @moduledoc """
  PostgreSQL adapter for Blink bulk copy operations.

  This adapter uses PostgreSQL's `COPY FROM STDIN` command for efficient bulk
  insertion of data. It is the default adapter used by Blink.

  ## Usage

  This adapter is used automatically by default:

      Blink.copy_to_table(rows, "users", MyApp.Repo)

  Or explicitly:

      Blink.copy_to_table(rows, "users", MyApp.Repo, adapter: Blink.Adapter.Postgres)
  """
  @behaviour Blink.Adapter

  @escape_chars ["|", "\"", "\n", "\r", "\\"]

  defmodule Context do
    @moduledoc false

    @enforce_keys [:repo, :table_name, :batch_size, :max_concurrency, :timeout, :escape_cp]
    defstruct @enforce_keys ++ [:columns, :columns_string]

    @type t :: %__MODULE__{
            repo: Ecto.Repo.t(),
            table_name: String.t(),
            batch_size: pos_integer(),
            max_concurrency: pos_integer(),
            timeout: timeout(),
            escape_cp: :binary.cp(),
            columns: [atom() | String.t()] | nil,
            columns_string: String.t() | nil
          }

    def put_column_fields(%__MODULE__{} = context, columns) when is_list(columns) do
      %{context | columns: columns, columns_string: quote_columns(columns)}
    end

    defp quote_columns(columns) do
      Enum.map_join(columns, ", ", &~s("#{&1}"))
    end
  end

  @doc """
  Copies rows into a database table using PostgreSQL's COPY command.

  ## Parameters

    * `rows` - An enumerable (list or stream) of maps where each map represents
      a row to insert. All maps must have the same keys, which correspond to the
      table columns. Using a stream allows for memory-efficient seeding of large
      datasets.
    * `table_name` - The name of the table to insert into (string).
    * `repo` - An Ecto repository module configured with a Postgres adapter.
    * `opts` - Keyword list of options:
      * `:batch_size` - Number of rows per batch (default: 8,000). Items are
        chunked into batches, each inserted via a separate COPY operation. To
        disable batching, set this to a value equal to or greater than the
        total number of rows.
      * `:max_concurrency` - Number of parallel COPY operations (default: 6).
        When greater than 1, batches are inserted using multiple database
        connections in parallel.
      * `:timeout` - Timeout in milliseconds for each batch operation
        (default: `:infinity`).

  ## Returns

    * `:ok` - When the copy operation succeeds

  Raises an exception when the copy operation fails.

  ## Examples

      iex> rows = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> Blink.Adapter.Postgres.call(rows, "users", MyApp.Repo)
      :ok

      # Using a stream for memory-efficient seeding
      iex> stream = Stream.map(1..1_000_000, fn i -> %{id: i, name: "User \#{i}"} end)
      iex> Blink.Adapter.Postgres.call(stream, "users", MyApp.Repo)
      :ok

  ## Notes

  The function assumes all rows have the same keys. NULL values are represented
  as `\\N` in the CSV format. Nested maps are automatically JSON-encoded for
  JSONB columns, and Elixir lists are encoded as PostgreSQL array literals for
  array columns (`int[]`, `text[]`, `jsonb[]`, nested arrays, ...). A JSONB column
  holding a top-level JSON array should be passed as a pre-encoded JSON string.
  """
  @impl true
  @spec call(
          rows :: Enumerable.t(),
          table_name :: String.t(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: :ok
  def call(rows, table_name, repo, opts \\ []) when is_binary(table_name) and is_list(opts) do
    context = %Context{
      repo: repo,
      table_name: table_name,
      batch_size: Keyword.get(opts, :batch_size, 8_000),
      max_concurrency: Keyword.get(opts, :max_concurrency, 6),
      timeout: Keyword.get(opts, :timeout, :infinity),
      escape_cp: :binary.compile_pattern(@escape_chars)
    }

    rows
    |> Stream.chunk_every(context.batch_size)
    |> run_copy(context)
  end

  defp run_copy(batches, %Context{max_concurrency: 1} = context) do
    Enum.reduce(batches, context, fn
      [], context ->
        context

      [first_row | _] = batch, %{columns: nil} = context ->
        columns = Map.keys(first_row)
        context = Context.put_column_fields(context, columns)
        emit_telemetry(context)
        execute_copy(batch, context)
        context

      batch, context ->
        execute_copy(batch, context)
        context
    end)

    :ok
  end

  defp run_copy(batches, %Context{} = context) do
    batches
    |> Stream.transform(context, fn
      [], context ->
        {[], context}

      [first_row | _] = batch, %{columns: nil} = context ->
        columns = Map.keys(first_row)
        context = Context.put_column_fields(context, columns)
        emit_telemetry(context)
        {[{batch, context}], context}

      batch, context ->
        {[{batch, context}], context}
    end)
    |> Task.async_stream(
      fn {batch, context} -> execute_copy(batch, context) end,
      max_concurrency: context.max_concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Stream.each(fn
      {:ok, {:ok, _}} -> :ok
      other -> raise "COPY failed: #{inspect(other)}"
    end)
    |> Stream.run()

    :ok
  end

  defp emit_telemetry(%{
         table_name: table_name,
         batch_size: batch_size,
         max_concurrency: max_concurrency,
         timeout: timeout
       }) do
    :telemetry.execute(
      [:blink, :copy, :start],
      %{system_time: System.system_time()},
      %{
        table_name: table_name,
        batch_size: batch_size,
        max_concurrency: max_concurrency,
        timeout: timeout
      }
    )
  end

  defp execute_copy(batch, %{
         columns: columns,
         columns_string: columns_string,
         escape_cp: escape_cp,
         repo: repo,
         table_name: table_name,
         timeout: timeout
       }) do
    csv_rows = Enum.map(batch, &row_to_csv(&1, columns, escape_cp))

    copy_stream =
      Ecto.Adapters.SQL.stream(
        repo,
        """
        COPY #{table_name} (#{columns_string})
        FROM STDIN
        WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
        """
      )

    repo.transaction(
      fn -> Enum.into([csv_rows], copy_stream) end,
      timeout: timeout
    )
  end

  defp row_to_csv(row, [col], escape_cp) do
    [encode_value(Map.get(row, col), escape_cp), "\n"]
  end

  defp row_to_csv(row, [col | rest], escape_cp) do
    [encode_value(Map.get(row, col), escape_cp), "|" | row_to_csv(row, rest, escape_cp)]
  end

  defp encode_value(nil, _escape_cp), do: "\\N"
  defp encode_value(value, _escape_cp) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value, escape_cp) when is_binary(value), do: maybe_escape(value, escape_cp)

  defp encode_value(value, escape_cp) when is_map(value),
    do: maybe_escape(Jason.encode!(value), escape_cp)

  defp encode_value(value, escape_cp) when is_list(value),
    do: maybe_escape(IO.iodata_to_binary(encode_array(value)), escape_cp)

  defp encode_value(value, escape_cp), do: maybe_escape(to_string(value), escape_cp)

  defp maybe_escape(value, escape_cp) do
    case :binary.match(value, escape_cp) do
      :nomatch -> value
      _ -> ["\"", String.replace(value, "\"", "\"\""), "\""]
    end
  end

  # The encoder never sees column types, so a list always becomes an array literal;
  # a JSONB column holding a top-level JSON array must be passed as a pre-encoded
  # JSON string instead.
  defp encode_array(list),
    do: [?{, Enum.map_intersperse(list, ?,, &encode_array_element/1), ?}]

  defp encode_array_element(nil), do: "NULL"
  defp encode_array_element(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_array_element(value) when is_boolean(value), do: to_string(value)
  defp encode_array_element(value) when is_float(value), do: Float.to_string(value)
  defp encode_array_element(value) when is_list(value), do: encode_array(value)
  defp encode_array_element(value) when is_map(value), do: quote_element(Jason.encode!(value))
  defp encode_array_element(value) when is_binary(value), do: quote_element(value)
  defp encode_array_element(value), do: quote_element(to_string(value))

  defp quote_element(string) do
    escaped = string |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
    [?", escaped, ?"]
  end
end
