defmodule Blink.VersionPinTest do
  use ExUnit.Case, async: true

  # The install-pin convention: README and guides pin the current minor series
  # (`~> X.Y.0`), and a patch release leaves them unchanged. Pins live outside
  # the release checklist's single-file habit, and stale ones shipped in
  # v0.4.0 and v0.7.0 — this pins every occurrence to @version. Pre-release
  # versions are exempt: `~>` excludes pre-releases, so no series pin can
  # resolve during an rc cycle and pins are chosen by hand.
  test "every install pin matches the current version's series" do
    version = Version.parse!(Mix.Project.config()[:version])

    if version.pre == [] do
      expected = "~> #{version.major}.#{version.minor}.0"

      files = [
        Path.expand("../../README.md", __DIR__)
        | Path.wildcard(Path.expand("../../guides/*.md", __DIR__))
      ]

      pins =
        for file <- files,
            [_, requirement] <- Regex.scan(~r/\{:blink, "([^"]+)"/, File.read!(file)) do
          {Path.basename(file), requirement}
        end

      assert pins != []

      for {file, requirement} <- pins do
        assert requirement == expected,
               "#{file} pins {:blink, \"#{requirement}\"}, expected \"#{expected}\""
      end
    end
  end
end
