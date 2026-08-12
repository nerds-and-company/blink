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

    @enforce_keys [:repo, :table_name, :batch_size, :concurrency, :timeout, :atomic, :escape_cp]
    defstruct @enforce_keys ++ [:columns, :columns_string, :row_counter]

    @type t :: %__MODULE__{
            repo: Ecto.Repo.t(),
            table_name: String.t(),
            batch_size: pos_integer(),
            concurrency: pos_integer(),
            timeout: timeout(),
            atomic: boolean(),
            escape_cp: :binary.cp(),
            columns: [atom() | String.t()] | nil,
            columns_string: String.t() | nil,
            row_counter: :counters.counters_ref() | nil
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
      table columns; a row whose keys differ from the first row's raises
      `Blink.RowError`. Using a stream allows for memory-efficient seeding of
      large datasets. The input is consumed exactly once, so single-use streams
      are safe.
    * `table_name` - The name of the table to insert into (string).
    * `repo` - An Ecto repository module configured with a Postgres adapter.
    * `opts` - Keyword list of options. Unknown keys and invalid values raise
      `ArgumentError`:
      * `:atomic` - Whether the copy is all-or-nothing (default: `true`).
        * `false` - Workers copy batches over up to `:concurrency` database
          connections in parallel and each batch commits independently.
          Fastest, but a failure can leave earlier batches committed. The
          worker connections do not enroll in a transaction of the caller's
          own: they cannot see its uncommitted data, and their commits
          survive its rollback.
        * `true` - All batches are copied over one connection inside a single
          transaction while `:concurrency` workers encode rows in parallel.
          Any failure rolls back the whole COPY, and the copy enrolls in a
          surrounding transaction such as the one `Blink.Seeder.run/3` opens
          for atomic seeds. Rows are copied in input order.
      * `:concurrency` - Number of parallel workers (default: 6 when
        `atomic: false`, `System.schedulers_online/0` when `atomic: true`).
        With `atomic: false` each worker encodes and copies batches over its
        own database connection, so configure the repo's `pool_size` to at
        least `:concurrency`. With `atomic: true` workers only encode; a
        single connection performs the COPY.
      * `:batch_size` - Number of rows per batch (default: 8,000). Items are
        chunked into batches, each written via a separate COPY operation (or a
        separate write to the single COPY when `atomic: true`). To disable
        batching, set this to a value equal to or greater than the total
        number of rows.
      * `:timeout` - Time in milliseconds allowed for each database operation
        (default: 15,000). With `atomic: false` this bounds each batch's COPY
        transaction. With `atomic: true` it is enforced server-side as a
        `statement_timeout` on each COPY statement, because a connection
        checkout deadline cannot bound individual operations inside one
        transaction. Set to `:infinity` to disable Blink's timeout (a
        server-configured `statement_timeout` still applies).
      * `:reset_sequences` - After the copy, advance the sequence behind each
        of the table's `serial` or identity primary key columns past the
        highest copied value (default: `false`). Explicit IDs do not advance
        a sequence, so without this the application's next ordinary insert
        collides with a seeded row. Primary keys without a sequence (`uuid`,
        self-managed integers) are unaffected. No rows, no reset: the option
        does nothing when the input is empty. Intended for seed-time use —
        the reset derives its target from the `MAX()` of *visible* rows, so
        on a table receiving concurrent inserts it can move the sequence
        backwards past values already handed out to in-flight transactions,
        causing unique violations later.

  ## Returns

    * `:ok` - When the copy operation succeeds

  Raises an exception when the copy operation fails.

  ## Examples

      iex> rows = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      iex> Blink.Adapter.Postgres.call(rows, "users", MyApp.Repo)
      :ok

      # Atomic, all-or-nothing copy
      iex> Blink.Adapter.Postgres.call(rows, "users", MyApp.Repo, atomic: true)
      :ok

      # Using a stream for memory-efficient seeding
      iex> stream = Stream.map(1..1_000_000, fn i -> %{id: i, name: "User \#{i}"} end)
      iex> Blink.Adapter.Postgres.call(stream, "users", MyApp.Repo)
      :ok

  ## Notes

  The column list is read from the keys of the first row, and every subsequent
  row must have exactly the same keys — a mismatch raises `Blink.RowError` when
  the offending row is reached. With `atomic: true` (the default) a failed
  validation therefore leaves nothing behind; with `atomic: false` it surfaces
  like any other mid-copy failure, with earlier batches possibly committed.
  NULL values are represented as `\\N` in the CSV format. Nested maps are automatically JSON-encoded for
  JSONB columns; values that are already JSON strings are inserted as-is, so
  passing pre-encoded JSON avoids a redundant `Jason.encode!/1` call. Elixir
  lists are encoded as PostgreSQL array literals for array columns (`int[]`,
  `text[]`, `jsonb[]`, nested arrays, ...). A JSONB column holding a top-level
  JSON array should be passed as a pre-encoded JSON string.

  Structs are maps, so a struct value (a `DateTime`, `Date`, `Decimal`, ...) is
  also JSON-encoded. PostgreSQL's date/time parsers accept the quoted result,
  so calendar structs work in `timestamp`, `date`, and `time` columns; in a
  `text` column the stored value keeps the JSON quotes — pass
  `to_string(value)` instead.
  """
  @impl true
  @spec call(
          rows :: Enumerable.t(),
          table_name :: String.t(),
          repo :: Ecto.Repo.t(),
          opts :: Keyword.t()
        ) :: :ok
  def call(rows, table_name, repo, opts \\ []) when is_binary(table_name) and is_list(opts) do
    opts = validate_opts!(opts)
    atomic = Keyword.fetch!(opts, :atomic)

    context = %Context{
      repo: repo,
      table_name: table_name,
      batch_size: Keyword.fetch!(opts, :batch_size),
      concurrency: Keyword.get_lazy(opts, :concurrency, fn -> default_concurrency(atomic) end),
      timeout: Keyword.fetch!(opts, :timeout),
      atomic: atomic,
      escape_cp: :binary.compile_pattern(@escape_chars)
    }

    case uncons(rows) do
      :empty ->
        :ok

      {first_row, rest} ->
        context = %{
          Context.put_column_fields(context, Map.keys(first_row))
          | row_counter: :counters.new(1, [])
        }

        emit_start(context)
        start_time = System.monotonic_time()

        # catch, not rescue: a worker exit or a throw must re-raise with its
        # original class, which reraise/3 cannot do.
        try do
          [[first_row], rest]
          |> Stream.concat()
          |> Stream.chunk_every(context.batch_size)
          |> validate_batches(context)
          |> run_copy(context)

          if Keyword.fetch!(opts, :reset_sequences), do: reset_sequences(context)
        catch
          kind, reason ->
            emit_exception(context, start_time, kind, reason, __STACKTRACE__)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

        emit_stop(context, start_time)

        :ok
    end
  end

  # setval is non-transactional, so a later rollback leaves the sequence
  # advanced — harmless, since the sequence only needs to clear the seeded
  # ids. Inside an atomic run the MAX() sees the uncommitted rows because the
  # query runs on the same connection.
  defp reset_sequences(%Context{repo: repo, table_name: table_name}) do
    %{rows: pk_columns} =
      repo.query!(
        """
        SELECT a.attname::text, pg_get_serial_sequence($1, a.attname::text)
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = to_regclass($1) AND i.indisprimary
        """,
        [table_name]
      )

    Enum.each(pk_columns, fn
      [_column, nil] ->
        :ok

      [column, sequence] ->
        # The ::text::regclass cast lets the sequence name travel as a plain
        # string parameter; Postgrex refuses binaries for bare oid types.
        repo.query!(
          ~s|SELECT setval($1::text::regclass, COALESCE(MAX("#{column}") + 1, 1), false) | <>
            "FROM #{table_name}",
          [sequence]
        )
    end)
  end

  defp default_concurrency(true), do: System.schedulers_online()
  defp default_concurrency(false), do: 6

  defp validate_opts!(opts) do
    opts =
      Keyword.validate!(opts, [
        :concurrency,
        batch_size: 8_000,
        timeout: 15_000,
        atomic: true,
        reset_sequences: false
      ])

    Enum.each(opts, &validate_opt!/1)
    opts
  end

  defp validate_opt!({:batch_size, value}) when is_integer(value) and value > 0, do: :ok
  defp validate_opt!({:concurrency, value}) when is_integer(value) and value > 0, do: :ok

  defp validate_opt!({:timeout, value})
       when (is_integer(value) and value > 0) or value == :infinity, do: :ok

  defp validate_opt!({key, value}) when key in [:atomic, :reset_sequences] and is_boolean(value),
    do: :ok

  defp validate_opt!({key, value}) do
    raise ArgumentError, "invalid value #{inspect(value)} for option #{inspect(key)}"
  end

  # Validation runs in the calling process as batches are pulled toward the
  # COPY, so a mismatch raises `Blink.RowError` directly in the caller instead
  # of surfacing as a wrapped worker error. The running index is the row's
  # absolute position in the input, addressable with `Enum.at/2`.
  # The counter mirrors the running index out of the stream: its final value
  # is the table's row count for the copy :stop event, which is otherwise
  # unreachable once the stream has been consumed.
  defp validate_batches(batches, %Context{columns: columns} = context) do
    count = length(columns)

    Stream.transform(batches, 0, fn batch, index ->
      index = validate_batch!(batch, context, count, index)
      :counters.put(context.row_counter, 1, index)
      {[batch], index}
    end)
  end

  defp validate_batch!(batch, %Context{columns: columns} = context, count, index) do
    Enum.reduce(batch, index, fn row, index ->
      if map_size(row) == count and Enum.all?(columns, &is_map_key(row, &1)) do
        index + 1
      else
        row_keys = Map.keys(row)

        raise Blink.RowError,
          table_name: context.table_name,
          index: index,
          missing: Enum.sort(columns -- row_keys),
          extra: Enum.sort(row_keys -- columns)
      end
    end)
  end

  defp run_copy(batches, %Context{atomic: true} = context) do
    batches
    |> execute_copy_atomic(context)
    |> check_copy!()

    :ok
  end

  defp run_copy(batches, %Context{atomic: false} = context) do
    batches
    |> Task.async_stream(
      fn batch -> try_execute_copy(batch, context) end,
      max_concurrency: context.concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Stream.each(fn
      {:ok, {:raised, exception, stacktrace}} -> reraise(exception, stacktrace)
      {:ok, result} -> check_copy!(result)
      other -> check_copy!(other)
    end)
    |> Stream.run()

    :ok
  end

  # Captures exceptions so a failed COPY re-raises in the calling process with
  # its original stacktrace, rather than exiting the caller through the task
  # link.
  defp try_execute_copy(batch, context) do
    execute_copy(batch, context)
  rescue
    exception -> {:raised, exception, __STACKTRACE__}
  end

  defp check_copy!({:ok, _result}), do: :ok
  defp check_copy!(other), do: raise("COPY failed: #{inspect(other)}")

  defp emit_start(context) do
    :telemetry.execute(
      [:blink, :copy, :start],
      %{system_time: System.system_time()},
      copy_metadata(context)
    )
  end

  defp emit_stop(context, start_time) do
    :telemetry.execute(
      [:blink, :copy, :stop],
      %{
        duration: System.monotonic_time() - start_time,
        row_count: :counters.get(context.row_counter, 1)
      },
      copy_metadata(context)
    )
  end

  defp emit_exception(context, start_time, kind, reason, stacktrace) do
    :telemetry.execute(
      [:blink, :copy, :exception],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(copy_metadata(context), %{kind: kind, reason: reason, stacktrace: stacktrace})
    )
  end

  defp copy_metadata(%{
         table_name: table_name,
         batch_size: batch_size,
         concurrency: concurrency,
         timeout: timeout,
         atomic: atomic
       }) do
    %{
      table_name: table_name,
      batch_size: batch_size,
      concurrency: concurrency,
      timeout: timeout,
      atomic: atomic
    }
  end

  defp execute_copy(
         batch,
         %{repo: repo, columns: columns, escape_cp: escape_cp, timeout: timeout} = context
       ) do
    csv_rows = rows_to_csv(batch, columns, escape_cp)

    repo.transaction(
      fn -> Enum.into([csv_rows], copy_stream(context)) end,
      timeout: timeout
    )
  end

  # Atomic mode: encode batches in parallel across cores, then feed them into
  # one COPY on one connection inside one transaction. Because the COPY runs in
  # the calling process, it enrolls in any surrounding transaction (e.g. the one
  # `Blink.Seeder.run/3` opens for atomic seeds). The checkout timeout is
  # :infinity because the connection is held for the whole copy; DBConnection
  # ignores opts on nested transactions anyway, so the per-operation `:timeout`
  # is enforced server-side instead.
  defp execute_copy_atomic(batches, context) do
    %{
      repo: repo,
      columns: columns,
      escape_cp: escape_cp,
      timeout: timeout,
      concurrency: concurrency
    } = context

    repo.transaction(
      fn ->
        previous_timeout = put_statement_timeout(repo, timeout)

        result =
          batches
          |> Task.async_stream(
            fn batch -> encode_batch(batch, columns, escape_cp) end,
            max_concurrency: concurrency,
            timeout: :infinity
          )
          |> Stream.map(fn
            {:ok, {:ok, iodata}} -> iodata
            {:ok, {:error, error}} -> raise "COPY encode failed: #{Exception.message(error)}"
            {:exit, reason} -> raise "COPY encode failed: #{inspect(reason)}"
          end)
          |> Enum.into(copy_stream(context))

        restore_statement_timeout(repo, previous_timeout)
        result
      end,
      timeout: :infinity
    )
  end

  # SET LOCAL is scoped to the enclosing transaction, so this gives each COPY a
  # server-side timeout — the only per-operation mechanism available inside a
  # single transaction. That transaction may belong to the caller (an atomic
  # `run/3`, or a transaction of the application's own), so the previous value
  # is restored after the COPY rather than left applied to the rest of it. If
  # the COPY raises, the transaction is aborted and the SET LOCAL dies with it.
  # :infinity leaves any server-configured value in place.
  defp put_statement_timeout(_repo, :infinity), do: nil

  defp put_statement_timeout(repo, timeout) when is_integer(timeout) do
    %{rows: [[previous]]} = repo.query!("SHOW statement_timeout")
    repo.query!("SET LOCAL statement_timeout = #{timeout}")
    previous
  end

  defp restore_statement_timeout(_repo, nil), do: :ok

  # `previous` comes from SHOW above, never from user input.
  defp restore_statement_timeout(repo, previous) when is_binary(previous) do
    repo.query!("SET LOCAL statement_timeout = '#{previous}'")
  end

  defp copy_stream(%{repo: repo, table_name: table_name, columns_string: columns_string}) do
    Ecto.Adapters.SQL.stream(
      repo,
      """
      COPY #{table_name} (#{columns_string})
      FROM STDIN
      WITH (FORMAT csv, DELIMITER '|', NULL '\\N')
      """
    )
  end

  # Tags the result so an encoding failure in a worker surfaces as a descriptive
  # error rather than a raw process exit.
  defp encode_batch(batch, columns, escape_cp) do
    {:ok, rows_to_csv(batch, columns, escape_cp)}
  rescue
    error -> {:error, error}
  end

  # Splits an enumerable into its first element and a stream of the rest without
  # enumerating the source twice, so single-use streams are safe. The suspended
  # continuation is abandoned (its cleanup does not run) if the copy raises
  # mid-stream.
  defp uncons(enum) do
    case Enumerable.reduce(enum, {:cont, nil}, fn elem, _acc -> {:suspend, elem} end) do
      {:suspended, first, cont} -> {first, resume_stream(cont)}
      {:done, _acc} -> :empty
      {:halted, _acc} -> :empty
    end
  end

  defp resume_stream(cont) do
    Stream.resource(
      fn -> cont end,
      fn cont ->
        case cont.({:cont, nil}) do
          {:suspended, elem, cont} -> {[elem], cont}
          {:done, _acc} -> {:halt, :done}
          {:halted, _acc} -> {:halt, :done}
        end
      end,
      fn _ -> :ok end
    )
  end

  # Encodes a batch to a list of CSV row iodata, memoizing the JSON encoding of
  # map values within the batch. Seed data typically reuses a small number of
  # distinct JSONB values across many rows, so this avoids re-running
  # `Jason.encode!/1` on identical maps. The cache lives only for the batch.
  defp rows_to_csv(batch, columns, escape_cp) do
    {rows, _cache} =
      Enum.map_reduce(batch, %{}, fn row, cache ->
        row_to_csv(row, columns, escape_cp, cache)
      end)

    rows
  end

  defp row_to_csv(row, [col], escape_cp, cache) do
    {encoded, cache} = encode_value(Map.get(row, col), escape_cp, cache)
    {[encoded, "\n"], cache}
  end

  defp row_to_csv(row, [col | rest], escape_cp, cache) do
    {encoded, cache} = encode_value(Map.get(row, col), escape_cp, cache)
    {tail, cache} = row_to_csv(row, rest, escape_cp, cache)
    {[encoded, "|" | tail], cache}
  end

  defp encode_value(value, escape_cp, cache) when is_map(value) do
    case cache do
      %{^value => encoded} ->
        {encoded, cache}

      _ ->
        encoded = maybe_escape(Jason.encode!(value), escape_cp)
        {encoded, Map.put(cache, value, encoded)}
    end
  end

  # Maps never reach the /2 clauses: the memoizing /3 clause above intercepts
  # them, so a /2 map clause would be dead code (Elixir 1.20 proves it).
  defp encode_value(value, escape_cp, cache), do: {encode_value(value, escape_cp), cache}

  defp encode_value(nil, _escape_cp), do: "\\N"
  defp encode_value(value, _escape_cp) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value, escape_cp) when is_binary(value), do: maybe_escape(value, escape_cp)

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
