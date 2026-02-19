defmodule Polymarket.Data do
  @moduledoc """
  Wrapper for the Polymarket Data API (user positions, trades, activity, holders, portfolio value).
  """

  alias Polymarket.Data.Client

  @doc """
  Get positions for an address.

  Returns `{:ok, positions}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Data.get_positions("0x1234...")
      # => {:ok, %{"positions" => [...]}}

  """
  def get_positions(address),
    do: Client.get("/positions", params: [address: address]) |> process()

  @doc """
  Get trades.

  Returns `{:ok, trades}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Data.get_trades(limit: 10)
      # => {:ok, %{"trades" => [...]}}

  """
  def get_trades(opts \\ []), do: Client.get("/trades", params: Enum.into(opts, %{})) |> process()

  @doc """
  Get activity for an address.

  Returns `{:ok, activity}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Data.get_activity("0x1234...")
      # => {:ok, %{"activity" => [...]}}

  """
  def get_activity(address), do: Client.get("/activity", params: [address: address]) |> process()

  @doc """
  Get holders for a market.

  Returns `{:ok, holders}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Data.get_holders("will-trump-win-the-2024-us-presidential-election")
      # => {:ok, %{"holders" => [...]}}

  """
  def get_holders(market), do: Client.get("/holders", params: [market: market]) |> process()

  @doc """
  Get portfolio value for an address.

  Returns `{:ok, value}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Data.get_value("0x1234...")
      # => {:ok, %{"value" => 1000.50}}

  """
  def get_value(address), do: Client.get("/value", params: [address: address]) |> process()

  defp process({:ok, body}), do: {:ok, body}
  defp process({:error, _} = err), do: err
end
