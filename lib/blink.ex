defmodule Blink do
  @moduledoc """
  Fast data seeding in Ecto projects with `Blink`.
  """

  alias Blink.Parcel

  @doc "Creates an empty parcel"
  @spec new_parcel() :: Parcel.t()
  def new_parcel do
    %Parcel{}
  end
end
