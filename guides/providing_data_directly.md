# Providing Data Directly

When you already have your rows or context values in hand, Blink's `put_context`
and `put_table` helpers let you add them to a seeder without defining `table/2`
or `context/2` callbacks.

In this guide, we will:

- Add context values with `put_context`
- Add tables with `put_table`
- Mix eager `put_*` helpers with callback-based `with_*`

## When to use put_* vs with_*

`with_table/2` and `with_context/2` are the default. Their callbacks run when
the table or key is declared, so they receive the seeder built so far and can
derive rows from earlier tables and context — that is what keeps the pipeline
declarative.

Reach for `put_table` and `put_context` in the narrower case where the data is
already available at the call site and no callback is needed — typically when
the rows were passed into the seeder from outside. Both helpers are imported by
`use Blink`, so you call them unqualified.

## Adding context with put_context

`put_context/3` stores a single value under a key. Context is auxiliary data: it
is never inserted, but it stays available to later callbacks via
`seeder.context`.

```elixir
defmodule Blog.Seeder do
  use Blink

  def call(users) do
    new()
    |> put_context(:generated_at, DateTime.utc_now())
    |> put_table("users", users)
    |> run(Blog.Repo)
  end
end
```

To add several values at once, pass a keyword list to `put_context/2`. Pairs are
applied in order:

```elixir
new()
|> put_context(user_id: user_id, project_indices: project_indices)
```

## Adding tables with put_table

`put_table/3` adds rows under a table name. `rows` may be a list or a stream,
and a stream is stored without being materialized:

```elixir
new()
|> put_table("users", users)
|> run(Blog.Repo)
```

Add several tables at once with `put_table/2`. List order becomes insertion
order, so declare parents before children:

```elixir
new()
|> put_table(users: users, posts: posts, comments: comments)
|> run(Blog.Repo)
```

For per-table options — or a large table you want to stream — use `put_table/4`.
It accepts the same per-table `:batch_size`, `:concurrency`, and
`:reset_sequences` options as `with_table/3`, and per-table values override
the ones passed to `run/3`. The
keyword form cannot carry options:

```elixir
events = Stream.map(1..1_000_000, fn i -> %{id: i, name: "Event #{i}"} end)

new()
|> put_table("users", users)
|> put_table("events", events, batch_size: 1_000, concurrency: 2)
|> run(Blog.Repo)
```

## Mixing put_* with callbacks

Eager and callback-based declarations interoperate. A later `table/2` callback
reads earlier rows and context off the seeder:

```elixir
def call(users) do
  new()
  |> put_context(:tenant_id, 42)
  |> put_table("users", users)
  |> with_table("posts")
  |> run(Blog.Repo)
end

def table(seeder, "posts") do
  Enum.map(seeder.tables["users"], fn user ->
    %{title: "Welcome, #{user.name}", user_id: user.id, tenant_id: seeder.context[:tenant_id]}
  end)
end
```

## Error handling

`put_context` and `put_table` raise `ArgumentError` when:

- A key or table name already exists.
- The same key appears twice within one keyword list, e.g. `put_table(dup: [], dup: [])`.

Detection is string-normalized, so a string name and the atom keyword form count
as the same table:

```elixir
# ** (ArgumentError) key already exists in `:tables` of Seeder: users
new()
|> put_table("users", users)
|> put_table(users: more_users)
```

The keyword `/2` forms are atom-keyed and carry no options. Use `/3` or `/4` for
string table names, per-table options, or to add a single table — a bare list of
rows is treated as pairs and will not work.

## Summary

In this guide, we learned how to:

- Add context values with `put_context/2` and `put_context/3`
- Add tables with `put_table/2`, `put_table/3`, and `put_table/4`
- Combine eager `put_*` helpers with callback-based `with_table/2` and `with_context/2`
