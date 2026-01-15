defmodule Blink.CSV do
  @moduledoc false

  NimbleCSV.define(Blink.CSVParser, separator: ",", escape: "\"")

  @spec from_csv(path :: String.t(), opts :: Keyword.t()) :: Enumerable.t()
  def from_csv(path, opts \\ []) do
    validate_opts!(opts)

    stream? = Keyword.get(opts, :stream, false)
    headers = Keyword.get(opts, :headers, :infer)
    transform = Keyword.get(opts, :transform, & &1)

    rows =
      path
      |> stream_rows()
      |> apply_headers(headers, transform)

    if stream?, do: rows, else: Enum.to_list(rows)
  end

  defp stream_rows(path) do
    path
    |> File.stream!()
    |> Blink.CSVParser.parse_stream(skip_headers: false)
  end

  defp apply_headers(rows, :infer, transform) do
    Stream.transform(rows, nil, fn
      row, nil -> {[], row}
      row, headers -> {[row_to_map(row, headers, transform)], headers}
    end)
  end

  defp apply_headers(rows, headers, transform) do
    Stream.map(rows, &row_to_map(&1, headers, transform))
  end

  defp row_to_map(row, headers, transform) do
    headers
    |> Enum.zip(row)
    |> Map.new()
    |> transform.()
  end

  defp validate_opts!(opts) do
    transform = Keyword.get(opts, :transform)

    if transform != nil and not is_function(transform, 1) do
      raise ArgumentError, ":transform option must be a function that takes 1 argument"
    end

    case Keyword.get(opts, :headers) do
      nil ->
        :ok

      :infer ->
        :ok

      headers when is_list(headers) ->
        unless Enum.all?(headers, &(is_binary(&1) or is_atom(&1))) do
          raise ArgumentError,
                ":headers option must be a list of strings or atoms, got: #{inspect(headers)}"
        end

      invalid ->
        raise ArgumentError,
              ":headers option must be a list of header names or :infer, got: #{inspect(invalid)}"
    end
  end
end
