defmodule Blink.JSON do
  @moduledoc false

  @spec from_json(path :: String.t(), opts :: Keyword.t()) :: [map()]
  def from_json(path, opts) do
    raw_items =
      path
      |> File.read!()
      |> Jason.decode!()

    parse_json_items(raw_items, Keyword.get(opts, :transform, & &1))
  end

  defp parse_json_items(_, transform) when not is_function(transform, 1) do
    raise ArgumentError, ":transform option must be a function that takes 1 argument"
  end

  defp parse_json_items(items, transform) when is_list(items) do
    Enum.map(items, fn
      item when is_map(item) ->
        transform.(item)

      other ->
        raise ArgumentError,
              "JSON file must contain an array of objects, found: #{inspect(other)}"
    end)
  end

  defp parse_json_items(other, _transform) do
    raise ArgumentError,
          "JSON file must contain an array at root level, found: #{inspect(other)}"
  end
end
