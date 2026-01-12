defmodule Blink.JSON do
  @moduledoc false

  @spec from_json(path :: String.t(), opts :: Keyword.t()) :: [map()]
  def from_json(path, opts) do
    raw_items =
      path
      |> File.read!()
      |> Jason.decode!()

    unless is_list(raw_items) do
      raise ArgumentError,
            "JSON file must contain an array at root level, found: #{inspect(raw_items)}"
    end

    transform = Keyword.get(opts, :transform, & &1)

    unless is_function(transform, 1) do
      raise ArgumentError, ":transform option must be a function that takes 1 argument"
    end

    transform = fn
      %{} = item ->
        transform.(item)

      item ->
        raise ArgumentError,
              "JSON file must contain an array of objects, found: #{inspect(item)}"
    end

    Enum.map(raw_items, transform)
  end
end
