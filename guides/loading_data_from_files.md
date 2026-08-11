# Loading Data from Files

Blink provides helper functions to load data from CSV and JSON files, making it easy to seed your database from external data sources.

## Loading from CSV files

CSV files are a common format for storing tabular data. Blink can read CSV files and convert them into maps suitable for insertion.

### Basic usage

Create a CSV file at `priv/seed_data/users.csv`:

```csv
id,name,email
1,Alice Johnson,alice@example.com
2,Bob Smith,bob@example.com
3,Carol White,carol@example.com
```

Load it in your seeder:

```elixir
defmodule Blog.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> run(Blog.Repo)
  end

  @impl true
  def table(_seeder, "users") do
    Blink.from_csv("priv/seed_data/users.csv")
  end
end
```

By default, from_csv/2 reads the first row as column headers and returns all keys and values as strings.

### Transforming data

Use the `:transform` option to convert types and add required fields:

```elixir
def table(_seeder, "users") do
  Blink.from_csv("priv/seed_data/users.csv",
    transform: fn row ->
      row
      |> Map.update!("id", &String.to_integer/1)
      |> Map.put("inserted_at", ~U[2024-01-01 00:00:00Z])
      |> Map.put("updated_at", ~U[2024-01-01 00:00:00Z])
    end
  )
end
```

The `transform` function receives each row as a map and should return the transformed map.

### CSV files without headers

If your CSV file doesn't have a header row, provide the column names explicitly:

```elixir
def table(_seeder, "users") do
  Blink.from_csv("priv/seed_data/users_no_headers.csv",
    headers: ["id", "name", "email"]
  )
end
```

### Combining headers and transform

You can use both options together:

```elixir
def table(_seeder, "users") do
  Blink.from_csv("priv/seed_data/users_no_headers.csv",
    headers: ["id", "name", "email"],
    transform: fn row ->
      Map.update!(row, "id", &String.to_integer/1)
    end
  )
end
```

### Streaming CSV files

For large CSV files, use the `:stream` option to process data lazily without loading the entire file into memory:

```elixir
def table(_seeder, "users") do
  Blink.from_csv("priv/seed_data/large_users.csv",
    stream: true,
    transform: fn row ->
      Map.update!(row, "id", &String.to_integer/1)
    end
  )
end
```

When `stream: true` is set, `from_csv/2` returns a stream instead of a list. Blink's insertion process handles streams efficiently.

### JSONB columns in CSV files

CSV files can also contain JSON data for JSONB columns, including deeply nested structures. Embed the JSON as a quoted string:

```csv
id,name,email,settings
1,Alice,alice@example.com,"{""theme"":""dark"",""notifications"":{""email"":true,""sms"":false}}"
2,Bob,bob@example.com,"{""theme"":""light"",""notifications"":{""email"":false,""sms"":true}}"
```

The `settings` value read from the CSV is already a JSON string, so you can
insert it into the JSONB column as-is — no decoding needed:

```elixir
def table(_seeder, "users") do
  Blink.from_csv("priv/seed_data/users_with_settings.csv",
    transform: fn row ->
      %{
        id: String.to_integer(row["id"]),
        name: row["name"],
        email: row["email"],
        settings: row["settings"]
      }
    end
  )
end
```

Decoding the string into a map (`Jason.decode!(row["settings"])`) is only worth
it when you need to inspect or modify the value before inserting — the Postgres
adapter re-encodes maps with `Jason.encode!/1` when copying, so decoding and then
letting the adapter re-encode is a wasted round trip.

## Loading from JSON files

JSON files are also supported via `from_json/2`.

### Basic usage

Create a JSON file at `priv/seed_data/products.json`:

```json
[
  { "id": 1, "name": "Widget", "price": 9.99 },
  { "id": 2, "name": "Gadget", "price": 19.99 },
  { "id": 3, "name": "Doohickey", "price": 29.99 }
]
```

Load it in your seeder:

```elixir
def table(_seeder, "products") do
  Blink.from_json("priv/seed_data/products.json")
end
```

The JSON file must contain an array of objects at the root level. Each object becomes a map with string keys.

Note that `from_json/2` does not support the `:stream` option. For large datasets, consider using CSV files with `stream: true` instead.

### Transforming JSON data

Use the `:transform` option to add or modify fields:

```elixir
def table(_seeder, "products") do
  Blink.from_json("priv/seed_data/products.json",
    transform: fn product ->
      Map.merge(product, %{
        "inserted_at" => ~U[2024-01-01 00:00:00Z],
        "updated_at" => ~U[2024-01-01 00:00:00Z]
      })
    end
  )
end
```

### Objects with optional fields

Every row must have the same keys as the first row — Blink reads the column
list from the first row, and a later row whose keys differ raises
`Blink.RowError` when copied. A JSON export whose objects omit optional
fields — say some products in the file above carry no `"price"` — must
therefore be normalized with `:transform`, choosing explicitly which columns
every row provides:

```elixir
defaults = %{"id" => nil, "name" => nil, "price" => nil}

Blink.from_json("priv/seed_data/products.json", transform: &Map.merge(defaults, &1))
```

This also frees the result from depending on which object happens to come
first in the file.

### Seeding JSONB columns

Blink automatically handles nested maps when inserting into JSONB columns. Create a JSON file with nested objects:

```json
[
  {
    "id": 1,
    "name": "Alice",
    "settings": { "theme": "dark", "notifications": true }
  },
  {
    "id": 2,
    "name": "Bob",
    "settings": { "theme": "light", "notifications": false }
  }
]
```

Load it in your seeder:

```elixir
def table(_seeder, "users") do
  Blink.from_json("priv/seed_data/users_with_settings.json",
    transform: fn row ->
      %{
        id: row["id"],
        name: row["name"],
        email: "#{String.downcase(row["name"])}@example.com",
        settings: row["settings"]
      }
    end
  )
end
```

The nested `settings` map is automatically JSON-encoded and inserted into the JSONB column.

## Error handling

The functions `from_csv/2` and `from_json/2` will raise exceptions if:

- The file doesn't exist
- The file format is invalid
- The `:transform` function is not a single-arity function
- For JSON: the root element is not an array, or the array contains non-object elements
- For CSV: the `:headers` option is not `:infer` or a list of strings

Separately, when the loaded rows are copied: a row whose keys differ from the
first row's raises `Blink.RowError` — normalize sparse objects as shown in
[Objects with optional fields](#objects-with-optional-fields).

## Summary

In this guide, we learned how to:

- Load data from CSV files with `from_csv/2`
- Transform data with the `:transform` option
- Handle CSV files without headers
- Stream large CSV files with the `:stream` option
- Load data from JSON files with `from_json/2`
- Seed JSONB columns with nested maps
