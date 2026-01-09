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
    validate_json_items(items)
    Enum.map(items, transform)
  end

  defp parse_json_items(other, _transform) do
    raise ArgumentError,
          "JSON file must contain an array at root level, found: #{inspect(other)}"
  end

  defp validate_json_items(items) do
    Enum.each(items, fn item ->
      if not is_map(item) do
        raise ArgumentError,
              "JSON file must contain an array of objects, found: #{inspect(item)}"
      end
    end)
  end
end
