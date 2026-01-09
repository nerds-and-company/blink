# Using Context

Sometimes you need to compute data once and share it across multiple tables. Blink provides the context feature for this purpose. Context data is not inserted into the database, but is available when building your table data.

## What is context?

Context is arbitrary data stored in `store.context` that you can access from any `table/2` or `context/2` callback. It's useful for:

- Sharing computed values across tables (e.g., timestamps, IDs)
- Pre-generating data that multiple tables need
- Storing lookup tables or reference data
- Avoiding redundant computations

## Basic example

Let's say we want to generate consistent timestamps and use them across multiple tables:

```elixir
defmodule Blog.Seeders.BlogSeeder do
  use Blink

  def call do
    new()
    |> add_context("timestamps")  # Register context first
    |> add_table("users")
    |> add_table("posts")
    |> insert(Blog.Repo)
  end

  def context(_store, "timestamps") do
    # Generate 30 days of timestamps
    base = ~U[2024-01-01 00:00:00Z]
    for day <- 0..29, do: DateTime.add(base, day, :day)
  end

  def table(store, "users") do
    timestamps = store.context["timestamps"]

    for i <- 1..100 do
      %{
        id: i,
        name: "User #{i}",
        email: "user#{i}@example.com",
        inserted_at: Enum.random(timestamps),
        updated_at: Enum.random(timestamps)
      }
    end
  end

  def table(store, "posts") do
    users = store.tables["users"]
    timestamps = store.context["timestamps"]

    Enum.flat_map(users, fn user ->
      for i <- 1..5 do
        %{
          id: (user.id - 1) * 5 + i,
          title: "Post #{i}",
          body: "Content here",
          user_id: user.id,
          inserted_at: Enum.random(timestamps),
          updated_at: Enum.random(timestamps)
        }
      end
    end)
  end
end
```

In this example, we generate timestamps once and reuse them across both the users and posts tables.

## Context with relationships

Context can help maintain referential integrity by providing consistent reference data:

```elixir
def call do
  new()
  |> add_context("user_ids")
  |> add_table("users")
  |> add_table("posts")
  |> add_table("comments")
  |> insert(Blog.Repo)
end

def context(_store, "user_ids") do
  # Generate a pool of user IDs
  Enum.to_list(1..1000)
end

def table(store, "users") do
  user_ids = store.context["user_ids"]

  for id <- user_ids do
    %{
      id: id,
      name: "User #{id}",
      email: "user#{id}@example.com",
      inserted_at: ~U[2024-01-01 00:00:00Z],
      updated_at: ~U[2024-01-01 00:00:00Z]
    }
  end
end

def table(store, "posts") do
  user_ids = store.context["user_ids"]

  for i <- 1..5000 do
    %{
      id: i,
      title: "Post #{i}",
      body: "Content",
      user_id: Enum.random(user_ids),
      inserted_at: ~U[2024-01-01 00:00:00Z],
      updated_at: ~U[2024-01-01 00:00:00Z]
    }
  end
end

def table(store, "comments") do
  user_ids = store.context["user_ids"]
  posts = store.tables["posts"]

  Enum.flat_map(posts, fn post ->
    for i <- 1..3 do
      %{
        id: (post.id - 1) * 3 + i,
        body: "Comment #{i}",
        post_id: post.id,
        user_id: Enum.random(user_ids),
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      }
    end
  end)
end
```

## Context for realistic data

Use context to generate realistic, consistent data:

```elixir
def call do
  new()
  |> add_context("timestamps")
  |> add_table("users")
  |> add_table("posts")
  |> insert(Blog.Repo)
end

def context(_store, "timestamps") do
  base = ~U[2024-01-01 00:00:00Z]
  for day <- 0..29, do: DateTime.add(base, day, :day)
end

def table(store, "users") do
  timestamps = store.context["timestamps"]

  for i <- 1..100 do
    %{
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      inserted_at: Enum.random(timestamps),
      updated_at: Enum.random(timestamps)
    }
  end
end

def table(store, "posts") do
  users = store.tables["users"]
  timestamps = store.context["timestamps"]

  Enum.flat_map(users, fn user ->
    # Only use timestamps after the user was created
    valid_timestamps =
      Enum.filter(timestamps, fn ts ->
        DateTime.compare(ts, user.inserted_at) == :gt
      end)

    for i <- 1..5 do
      %{
        id: (user.id - 1) * 5 + i,
        title: "Post #{i}",
        body: "Content here",
        user_id: user.id,
        inserted_at: Enum.random(valid_timestamps),
        updated_at: Enum.random(valid_timestamps)
      }
    end
  end)
end
```

In this example, we ensure posts are created after their associated user by filtering the available timestamps.

## Summary

In this guide, we learned how to:

- Add context data with `add_context/2`
- Define context callbacks with `context/2`
- Access context from table callbacks via `store.context`

For more information, see the [Blink API documentation](https://hexdocs.pm/blink/Blink.html).
