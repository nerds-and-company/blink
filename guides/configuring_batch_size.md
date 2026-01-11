## Configuring batch size

By default, Blink inserts records in batches of 900.

You can configure this to another number:

```elixir
def call do
  new()
  |> add_table("users")
  |> insert(Blog.Repo, batch_size: 1_200)
end
```

Or disable batching altogether:

```elixir
def call do
  new()
  |> add_table("users")
  |> insert(Blog.Repo, batch_size: :infinity)
end
```

Batch size is internally used for conversion of the table data in a Store to CSV format. Turning off batching maximizes insertion speed. However, it will use more memory as all data is converted to CSV format at once. The current version of Blink loads Store instances into memory before insertion, so even with batching turned on it works best for datasets of moderate size. Future versions might address this limitation.
