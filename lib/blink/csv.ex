defmodule Blink.CSV do
  @moduledoc false

  NimbleCSV.define(Blink.CSVParser, separator: ",", escape: "\"")
end
