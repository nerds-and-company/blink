defmodule Blink.CSV do
  @moduledoc false

  NimbleCSV.define(Blink.CSVParser, separator: ",", escape: "\"")

  @spec from_csv(path :: String.t(), opts :: Keyword.t()) :: [map()]
  def from_csv(path, opts) do
    raw_rows =
      path
      |> File.stream!()
      |> Blink.CSVParser.parse_stream(skip_headers: false)
      |> Enum.to_list()

    parse_csv_rows(
      raw_rows,
      Keyword.get(opts, :headers, :infer),
      Keyword.get(opts, :transform, & &1)
    )
  end

  defp parse_csv_rows([], _, _), do: []

  defp parse_csv_rows(_, _, transform) when not is_function(transform, 1) do
    raise ArgumentError, ":transform option must be a function that takes 1 argument"
  end

  defp parse_csv_rows([headers | rows], :infer, transform) do
    Enum.map(rows, fn row ->
      headers
      |> Enum.zip(row)
      |> Map.new()
      |> transform.()
    end)
  end

  defp parse_csv_rows(rows, headers, transform) when is_list(headers) do
    Enum.map(rows, fn row ->
      headers
      |> Enum.zip(row)
      |> Map.new()
      |> transform.()
    end)
  end

  defp parse_csv_rows(_rows, invalid_headers, _transform) do
    raise ArgumentError,
          ":headers option must be a list of header names or :infer, got: #{inspect(invalid_headers)}"
  end
end
