## Configuring batch size

By default, Blink inserts all table records at once without batching (`batch_size: :infinity`). This maximizes insertion speed but might use more memory as all data is converted to CSV format at once.

You can enable batching by setting a custom batch size:

```elixir
def call do
  new()
  |> add_table("users")
  |> insert(Blog.Repo, batch_size: 900)
end
```

Batch size is internally used for conversion of the table data from a Store to CSV format. The current version of Blink loads Store instances into memory before insertion, so even with batching turned on it works best for datasets of moderate size. Future versions might address this limitation.
