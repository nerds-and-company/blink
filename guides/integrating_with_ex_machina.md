# Integrating with ExMachina

ExMachina is a popular library for generating data in Elixir. Blink works seamlessly with ExMachina, allowing you to combine ExMachina's expressive factories with Blink's high-performance bulk insertion.

## Setting up ExMachina

Add ExMachina to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:ex_machina, "~> 2.7", only: [:dev, :test]}
  ]
end
```

Install the dependencies:

```bash
mix deps.get
```

## Creating factories

Create a factory module:

```elixir
defmodule Blog.Factory do
  use ExMachina

  def user_factory do
    %{
      name: Faker.Person.name(),
      email: Faker.Internet.email()
    }
  end

  def post_factory do
    %{
      title: Faker.Lorem.sentence(),
      body: Faker.Lorem.paragraph()
    }
  end
end
```

Note: To use `Faker`, add `{:faker, "~> 0.18", only: [:dev, :test]}` to your dependencies.

## Basic integration

Use ExMachina's `build/1` function in your Blink seeder:

```elixir
defmodule Blog.Seeders.BlogSeeder do
  use Blink
  import Blog.Factory

  def call do
    new()
    |> add_table("users")
    |> insert(Blog.Repo)
  end

  def table(_store, "users") do
    for i <- 1..1000 do
      user = build(:user)

      Map.merge(user, %{
        id: i,
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      })
    end
  end
end
```

ExMachina generates the names and emails, while you control the IDs and timestamps.

## Summary

In this guide, we learned how to:

- Set up ExMachina for data generation
- Use ExMachina's `build/1` function with Blink seeders

For more information:
- [ExMachina documentation](https://hexdocs.pm/ex_machina/)
- [Blink API documentation](https://hexdocs.pm/blink/Blink.html)
