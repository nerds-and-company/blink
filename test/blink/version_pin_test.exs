defmodule Blink.VersionPinTest do
  use ExUnit.Case, async: true

  # The install-pin convention: README and guides pin the current minor series
  # (`~> X.Y.0`), and a patch release leaves them unchanged. Pins live outside
  # the release checklist's single-file habit, and stale ones shipped in both
  # the 0.6.x and 0.8.0 cycles — this pins every occurrence to @version.
  test "every install pin matches the current version's series" do
    [major, minor | _] = Mix.Project.config()[:version] |> String.split(".")
    expected = "~> #{major}.#{minor}.0"

    pins =
      for file <- ["README.md" | Path.wildcard("guides/*.md")],
          [_, requirement] <- Regex.scan(~r/\{:blink, "([^"]+)"/, File.read!(file)) do
        {file, requirement}
      end

    assert pins != []

    for {file, requirement} <- pins do
      assert requirement == expected,
             "#{file} pins {:blink, \"#{requirement}\"}, expected \"#{expected}\""
    end
  end
end
