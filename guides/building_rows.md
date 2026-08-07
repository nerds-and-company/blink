# Building Rows

The unit of data in Blink is the row: a plain map whose keys are column names.
This guide shows the recommended way to build rows and a canonical seeder
shape, and covers the practical questions every seeder runs into —
timestamps, defaults, lookups, naming, and testing.

The short version: **build plain maps, not schema structs.** If your rows
come from an existing struct source such as a shared ExMachina factory, see
[Integrating with ExMachina](integrating_with_ex_machina.html) for the
conversion recipe.

## COPY is not Repo.insert

`Ecto.Repo.insert/2` runs every value through the schema layer on its way to
the database. Blink hands your maps to PostgreSQL's `COPY` directly, and three
habits from `Repo.insert` do not carry over:

1. **Column selection.** `Repo.insert` knows which fields are persisted.
   Blink reads the column list from the keys of the first row, and every row
   must have exactly the same keys — a mismatch raises `Blink.RowError`. A
   map has no virtual fields, no associations, and no `__meta__`, so there is
   nothing to strip: the keys you write are the columns you get.

2. **Autogeneration.** `Repo.insert` fills primary keys and `timestamps()`
   for you. With Blink you supply them yourself — an ID is just another value
   in the map (see
   [Choosing IDs](getting_started.html#choosing-ids)).

3. **Nil handling.** `Repo.insert` omits nil fields, so database defaults
   apply. COPY inserts an explicit `NULL` for every key you send. To get a
   column's default, leave the key out of every row rather than sending nil.

Instantiating a schema struct reintroduces all three problems at once: it
materializes every field as a key — mostly nils that will override database
defaults — and the code to undo that (strip virtuals, drop nil columns, fill
defaults by hand) is longer than building the right map in the first place.

## A canonical seeder

```elixir
defmodule MyApp.Seeder do
  @moduledoc false
  use Blink

  @timestamp DateTime.truncate(~U[2026-01-01 00:00:00Z], :second)

  @users [
    %{name: "Alice", email: "alice@example.com", role: "admin"},
    %{name: "Bob", email: "bob@example.com", role: "member"}
  ]

  @sessions [
    %{name: "Project ABC", code: "1234"},
    %{name: "Project XYZ", code: "7890"}
  ]

  def call do
    new()
    |> with_table(["users", "sessions", "session_users"])
    |> run(MyApp.Repo)
  end

  @impl true
  def table(_seeder, "users") do
    Enum.map(@users, &row/1)
  end

  def table(_seeder, "sessions") do
    Enum.map(@sessions, &row/1)
  end

  def table(seeder, "session_users") do
    alice = fetch_row!(seeder, "users", email: "alice@example.com")

    Enum.map(seeder.tables["sessions"], fn session ->
      row(%{user_id: alice.id, session_id: session.id, is_creator: true})
    end)
  end

  defp row(attrs) do
    attrs
    |> Map.put_new_lazy(:id, &Ecto.UUID.generate/0)
    |> Map.merge(%{inserted_at: @timestamp, updated_at: @timestamp})
  end
end
```

The conventions at work:

  * **Fixed rows live in module attributes**; `table/2` clauses map them into
    rows. The data reads as data, and the clauses stay small.
  * **The entrypoint is `call/0`.** Parameterize it (`call(repo, opts)`) only
    when the seeder is reused across scripts or tests.
  * **Table names are strings**, matching the database and making clauses
    grep-able by table name.
  * **One timestamp for the whole seed**, defined once. Seed data does not
    need realistic insertion times, and a single value keeps rows comparable.
  * **`@impl true` on the first clause** of each callback.
  * **Rely on the run defaults.** Seeds are atomic by default; pass only the
    options that differ.

## Timestamps and calendar values

Pass `DateTime`, `NaiveDateTime`, and `Date` structs directly — the adapter
encodes them in a form PostgreSQL's timestamp parsers accept. There is no
need to format them with `Calendar.strftime/2` first. Truncate to seconds
when the column type is `:utc_datetime`, exactly as Ecto requires:

```elixir
@timestamp DateTime.truncate(~U[2026-01-01 00:00:00Z], :second)
```

The one exception is a *text* column: a calendar struct stored into `text`
keeps its JSON quotes, so call `to_string/1` there. See the notes on
`Blink.Adapter.Postgres.call/4`.

## Leaving columns to their database defaults

Omit the key — from every row — and the column's default applies:

```elixir
# schema: has_code_access defaults to false in the database
%{name: "Project ABC", code: "1234"}                        # gets the default
%{name: "Project XYZ", code: "7890", has_code_access: true} # must not mix!
```

The second row raises `Blink.RowError`: rows cannot disagree about which
columns they provide, because the column list is read from the first row. If
only some rows override a defaulted column, provide the key in all rows and
write the default's value explicitly where you want it.

## Looking rows up

Later tables usually reference earlier ones. For positional relationships,
read `seeder.tables["users"]` directly; to find a specific row, use
`fetch_row!/3`, which raises a descriptive error instead of returning `nil`:

```elixir
alice = fetch_row!(seeder, "users", email: "alice@example.com")
```

## Serial and identity primary keys

Explicit IDs do not advance a sequence. Pass `reset_sequences: true` to
`run/3` so the application's next insert does not collide with a seeded row.
`uuid` keys have no sequence and need nothing.

## Naming your entrypoint

`use Blink` defines `run/2` and `run/3` on your module. Different arities are
different functions in Elixir, so naming your entrypoint `run/0` or `run/1`
works fine. Defining `run/2` or `run/3`, however, *replaces* Blink's
implementation — that is the documented override mechanism, and it applies
whether you meant it or not. An entrypoint like `def run(repo, opts \\ [])`
defines `run/2` and silently hijacks the pipeline's own `|> run(repo)` call.
When in doubt, name the entrypoint `call/0`.

## Where Blink goes in mix.exs

If seeding is a development and test concern, scope both the dependency and
the seeder code:

```elixir
{:blink, "~> 0.9.0", only: [:dev, :test]}
```

If a production boot script seeds bootstrap data (a `prod_seeds.exs`), the
dependency must stay in `:prod` — but the demo-data seeder module can still be
kept out of the production build by placing it outside `lib/` and listing its
directory in `elixirc_paths` for dev and test only.

## Timeouts in CI

The default `:timeout` (15 seconds per database operation) is sized for
local development. CI machines are slower and seed volumes grow; a seed that
copies comfortably in 3 seconds locally can exceed 15 in CI. Bound it
explicitly rather than reaching for `:infinity` — a runaway seed should fail,
not hang the job:

```elixir
run(seeder, MyApp.Repo, timeout: :timer.minutes(5))
```

## Testing your seeder

An atomic seed (the default) copies over a single connection in the calling
process, so it enrolls in `Ecto.Adapters.SQL.Sandbox` like any other database
call — seeder tests can run `async: true`:

```elixir
defmodule MyApp.SeederTest do
  use MyApp.DataCase, async: true

  test "seeds users and sessions" do
    assert :ok = MyApp.Seeder.call()
    assert Repo.aggregate(User, :count) == 2
  end
end
```

Asserting that seeded rows load back through your schemas (`Repo.all/1` on
the schema module) is a cheap way to catch type drift between the seeder's
maps and the real columns.

## Triggers and constraints

COPY fires row-level triggers and checks constraints as each row arrives,
just like ordinary inserts. If a trigger validates relationships within a
table, order the rows so every prefix of the table satisfies it — the trigger
does not wait for the end of the COPY.
