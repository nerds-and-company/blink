defmodule BlinkTest do
  use ExUnit.Case
  doctest Blink

  test "greets the world" do
    assert Blink.hello() == :world
  end
end
