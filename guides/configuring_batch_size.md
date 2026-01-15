## Configuring batch size

By default, Blink inserts all table records at once without batching (`batch_size: :infinity`). This maximizes insertion speed but might use more memory as all data is converted to CSV format at once.

You can enable batching by setting a custom batch size:

```elixir
def call do
  new()
  |> with_table("users")
  |> run(Blog.Repo, batch_size: 900)
end
```

Batch size is internally used for conversion of a Seeder's table data to CSV format. The current version of Blink loads Seeder instances into memory before insertion, so even with batching turned on it works best for datasets of moderate size. Future versions might address this limitation.
