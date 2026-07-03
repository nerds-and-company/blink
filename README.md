# Blink

Fast bulk data insertion for Ecto and PostgreSQL.

## Installation

Add `blink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:blink, "~> 0.7.0"}
  ]
end
```

## Example

```elixir
defmodule MyApp.Seeder do
  use Blink

  def call do
    new()
    |> with_table("users")
    |> with_table("posts")
    |> run(MyApp.Repo)
  end

  def table(_seeder, "users") do
    for i <- 1..1000 do
      %{
        id: i,
        name: "User #{i}",
        email: "user#{i}@example.com",
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end
  end

  def table(seeder, "posts") do
    Enum.flat_map(seeder.tables["users"], fn user ->
      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i}",
          user_id: user.id,
          inserted_at: ~U[2024-01-01 00:00:00Z],
          updated_at: ~U[2024-01-01 00:00:00Z]
        }
      end
    end)
  end
end

# Inserts 1,000 users and 5,000 posts
MyApp.Seeder.call()
```

## Features

- **Fast bulk inserts** of data into PostgreSQL
- **Stream support** for memory-efficient seeding
- **CSV/JSON loading** with built-in helpers
- **JSONB support** with automatic JSON encoding
- **Extensible** via adapters for other databases

## Documentation

See the [getting started guide](https://hexdocs.pm/blink/getting_started.html) and [full documentation](https://hexdocs.pm/blink) for more.

## Requirements

- Elixir 1.15+
- Ecto 3.0+
- PostgreSQL

## License

MIT - see [LICENSE](LICENSE) for details.
