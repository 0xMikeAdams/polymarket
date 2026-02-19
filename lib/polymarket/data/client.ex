defmodule Polymarket.Data.Client do
  @moduledoc false

  alias Polymarket.HTTP

  def get(path, opts \\ []), do: HTTP.get(:data, path, opts)
end
