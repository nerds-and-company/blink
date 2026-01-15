defmodule Blink.CSV do
  @moduledoc false

  NimbleCSV.define(Blink.CSVParser, separator: ",", escape: "\"")

  @spec from_csv(path :: String.t(), opts :: Keyword.t()) :: Enumerable.t()
  def from_csv(path, opts \\ []) do
    opts = [
      stream: Keyword.get(opts, :stream, false),
      headers: Keyword.get(opts, :headers, :infer),
      transform: Keyword.get(opts, :transform, & &1)
    ]

    validate_opts!(opts)
    parse_csv_rows(path, opts)
  end

  defp parse_csv_rows(path, stream: false, headers: :infer, transform: transform) do
    raw_rows =
      path
      |> File.stream!()
      |> Blink.CSVParser.parse_stream(skip_headers: false)
      |> Enum.to_list()

    case raw_rows do
      [] -> []
      [headers | rows] -> Enum.map(rows, &row_to_map(&1, headers, transform))
    end
  end

  defp parse_csv_rows(path, stream: false, headers: headers, transform: transform) do
    path
    |> File.stream!()
    |> Blink.CSVParser.parse_stream(skip_headers: false)
    |> Enum.map(&row_to_map(&1, headers, transform))
  end

  defp parse_csv_rows(path, stream: true, headers: :infer, transform: transform) do
    path
    |> File.stream!()
    |> Blink.CSVParser.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      row, nil -> {[], row}
      row, headers -> {[row_to_map(row, headers, transform)], headers}
    end)
  end

  defp parse_csv_rows(path, stream: true, headers: headers, transform: transform) do
    path
    |> File.stream!()
    |> Blink.CSVParser.parse_stream(skip_headers: false)
    |> Stream.map(&row_to_map(&1, headers, transform))
  end

  defp row_to_map(row, headers, transform) do
    headers
    |> Enum.zip(row)
    |> Map.new()
    |> transform.()
  end

  defp validate_opts!(opts) do
    unless is_function(opts[:transform], 1) do
      raise ArgumentError, ":transform option must be a function that takes 1 argument"
    end

    case opts[:headers] do
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
