ExUnit.start()

# Start the test repo
{:ok, _} = BlinkTest.Repo.start_link()

# Set up sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(BlinkTest.Repo, :manual)
