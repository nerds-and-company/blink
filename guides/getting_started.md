# Getting Started

This guide is an introduction to Blink, a fast bulk data insertion library for Ecto and PostgreSQL.

In this guide, we are going to:
- Create a seeder module for inserting users and posts
- Learn how to access data from previously inserted tables

## Adding Blink to an application

Add Blink to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:blink, "~> 0.4.0"}
  ]
end
```

Install the dependencies:

```bash
mix deps.get
```

## Configuring the repository

Blink works with any Ecto repository. If you don't have Ecto set up yet, follow the [Ecto Getting Started guide](https://hexdocs.pm/ecto/getting-started.html) to configure your repository and create your database tables.

For this guide, we'll assume you have:
- An Ecto repository (e.g., `Blog.Repo`) configured
- A `users` table with columns: `id`, `name`, `email`, `inserted_at`, `updated_at`
- A `posts` table with columns: `id`, `title`, `body`, `user_id`, `inserted_at`, `updated_at`

## Creating a seeder

Now that we have our database set up, let's create a seeder to insert data. Create `lib/blog/seeders/blog_seeder.ex`:

```elixir
defmodule Blog.Seeders.BlogSeeder do
  use Blink

  def call do
    new()
    |> add_table("users")
    |> insert(Blog.Repo)
  end

  def table(_store, "users") do
    for i <- 1..100 do
      %{
        id: i,
        name: "User #{i}",
        email: "user#{i}@example.com",
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end
  end
end
```

The seeder above does the following:

1. `use Blink` - Injects Blink's functions and defines required callbacks
2. `new()` - Creates an empty container, called a store, to hold our table data
3. `add_table("users")` - Declares the users table
4. `table/2` callback - Defines what data to insert into the users table
5. `insert/2` - Executes the bulk insertion

Let's run it from IEx:

```elixir
iex -S mix
iex> Blog.Seeders.BlogSeeder.call()
# => Inserts 100 users
```

## Inserting dependent tables

But what if you have relationships between tables. Let's add posts that belong to users. Update the seeder:

```elixir
def call do
  new()
  |> add_table("users")
  |> add_table("posts")  # Add the posts table
  |> insert(Blog.Repo)
end

def table(_store, "users") do
  for i <- 1..100 do
    %{
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      inserted_at: ~U[2024-01-01 00:00:00Z],
      updated_at: ~U[2024-01-01 00:00:00Z]
    }
  end

# Add another table/2 clause
def table(store, "posts") do
  users = store.tables["users"]  # Access previously inserted users

  Enum.flat_map(users, fn user ->
    for i <- 1..5 do
      %{
        id: (user.id - 1) * 5 + i,
        title: "Post #{i} by #{user.name}",
        body: "This is the content of post #{i}",
        user_id: user.id,
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end
  end)
end
```

The key insight here is that tables are inserted in the order they're added. When defining the `"posts"` table, we can access the `"users"` table data via `store.tables["users"]`. This allows us to reference user IDs when creating posts.

Run the updated seeder:

```elixir
iex> Blog.Seeders.BlogSeeder.call()
# => Inserts 100 users and 500 posts
```

## Summary

In this guide, we learned how to:

- Create a seeder module with `use Blink`
- Insert data into multiple related tables
- Access previously inserted table data via `store.tables`

## Next steps

You might also find these guides useful:

- [Using Context](using_context.html) - Share computed data across tables
- [Loading Data from Files](loading_data_from_files.html) - Learn how to load data from CSV and JSON files
- [Integrating with ExMachina](integrating_with_ex_machina.html) - Generate realistic test data
- [Configuring Batch Size](configuring_batch_size.html) - Configure batch sizes for insertion

For more information, see the [Blink API documentation](https://hexdocs.pm/blink/Blink.html).
