# Using Context

Sometimes you need to compute data once and share it across multiple tables. Blink provides the context feature for this purpose. Context data is not inserted into the database, but is available when building your table data.

In this example, we generate timestamps once and share them across tables, filtering so posts are created after their user.

```elixir
def call do
  new()
  |> with_context("timestamps")
  |> with_table("users")
  |> with_table("posts")
  |> run(Blog.Repo)
end

def context(_seeder, "timestamps") do
  base = ~U[2024-01-01 00:00:00Z]
  for day <- 0..29, do: DateTime.add(base, day, :day)
end

def table(seeder, "users") do
  timestamps = seeder.context["timestamps"]

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

def table(seeder, "posts") do
  users = seeder.tables["users"]
  timestamps = seeder.context["timestamps"]

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
