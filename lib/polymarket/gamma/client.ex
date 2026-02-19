defmodule Polymarket.Gamma.Client do
  @moduledoc false

  alias Polymarket.HTTP

  def get(path, opts \\ []), do: HTTP.get(:gamma, path, opts)
end
