defmodule Polymarket.Clob.Client do
  @moduledoc false

  alias Polymarket.HTTP

  def get(path, opts \\ []), do: HTTP.get(:clob, path, opts)
  def post(path, opts \\ []), do: HTTP.post(:clob, path, opts)
  def delete(path, opts \\ []), do: HTTP.delete(:clob, path, opts)
end
