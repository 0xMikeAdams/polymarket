defmodule Polymarket do
  @moduledoc """
  Elixir client for Polymarket APIs (Gamma, Data, CLOB) with built-in order signing.

  All functions return `{:ok, result}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Realtime streaming

  Realtime Polymarket events (fills, settlements, trades, prices, oracle
  resolutions, ...) are available through the PolyNode WebSocket API via
  `Polymarket.Websocket`:

      {:ok, ws} =
        Polymarket.Websocket.start_link(
          api_key: "pn_live_...",
          subscriptions: [:fills]
        )

      receive do
        {:polymarket_ws, :event, event} -> handle_fill(event)
      end

  See `Polymarket.Websocket` for subscriptions, filters, and reconnection
  behavior.
  """

  alias Polymarket.Gamma
  alias Polymarket.Data
  alias Polymarket.Clob

  @type result(t) :: {:ok, t} | {:error, Polymarket.Error.t()}

  @doc """
  List Gamma markets.

  Returns `{:ok, markets}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.list_markets(limit: 10)
      # => {:ok, [%{"id" => "...", "question" => "...", ...}, ...]}

  """
  defdelegate list_markets(opts \\ []), to: Gamma

  @doc """
  Get a Gamma market by slug.

  Returns `{:ok, market}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_market("will-trump-win-the-2024-us-presidential-election")
      # => {:ok, %{"id" => "...", "question" => "...", ...}}

  """
  defdelegate get_market(slug), to: Gamma

  @doc """
  List Gamma events.

  Returns `{:ok, events}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.list_events(limit: 10)
      # => {:ok, [%{"id" => "...", "title" => "...", ...}, ...]}

  """
  defdelegate list_events(opts \\ []), to: Gamma

  @doc """
  Get a Gamma event by slug.

  Returns `{:ok, event}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_event("us-presidential-election-2024")
      # => {:ok, %{"id" => "...", "title" => "...", ...}}

  """
  defdelegate get_event(slug), to: Gamma

  @doc """
  List Gamma tags.

  Returns `{:ok, tags}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.list_tags()
      # => {:ok, [%{"id" => "...", "name" => "...", ...}, ...]}

  """
  defdelegate list_tags, to: Gamma

  @doc """
  List Gamma sports.

  Returns `{:ok, sports}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.list_sports()
      # => {:ok, [%{"id" => "...", "name" => "...", ...}, ...]}

  """
  defdelegate list_sports, to: Gamma

  @doc """
  Get Data API positions for an address.

  Returns `{:ok, positions}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_positions("0x1234...")
      # => {:ok, %{"positions" => [...]}}

  """
  defdelegate get_positions(address), to: Data

  @doc """
  List Data API trades.

  Returns `{:ok, trades}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_trades(limit: 10)
      # => {:ok, %{"trades" => [...]}}

  """
  defdelegate get_trades(opts \\ []), to: Data

  @doc """
  Get Data API activity for an address.

  Returns `{:ok, activity}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_activity("0x1234...")
      # => {:ok, %{"activity" => [...]}}

  """
  defdelegate get_activity(address), to: Data

  @doc """
  Get Data API holders for a market.

  Returns `{:ok, holders}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_holders("will-trump-win-the-2024-us-presidential-election")
      # => {:ok, %{"holders" => [...]}}

  """
  defdelegate get_holders(market), to: Data

  @doc """
  Get Data API portfolio value for an address.

  Returns `{:ok, value}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_value("0x1234...")
      # => {:ok, %{"value" => 1000.50}}

  """
  defdelegate get_value(address), to: Data

  @doc """
  List CLOB markets.

  Returns `{:ok, markets}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_clob_markets(limit: 10)
      # => {:ok, [%{"id" => "...", ...}, ...]}

  """
  defdelegate get_clob_markets(opts \\ []), to: Clob, as: :get_markets

  @doc """
  Fetch a CLOB orderbook for a token.

  Returns `{:ok, orderbook}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_orderbook("1", side: "buy")
      # => {:ok, %{"bids" => [...], "asks" => [...]}}

  """
  defdelegate get_orderbook(token_id, opts \\ []), to: Clob

  @doc """
  List CLOB trades for a token.

  Returns `{:ok, trades}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_clob_trades("1")
      # => {:ok, [%{"price" => "0.50", ...}, ...]}

  """
  defdelegate get_clob_trades(token_id), to: Clob, as: :get_trades

  @doc """
  Fetch CLOB prices for a token.

  Returns `{:ok, prices}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_prices("1")
      # => {:ok, %{"bid" => "0.49", "ask" => "0.51"}}

  """
  defdelegate get_prices(token_id), to: Clob

  @doc """
  Fetch a CLOB order by order hash.

  Returns `{:ok, order}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_order("0xabc123...")
      # => {:ok, %{"status" => "open", ...}}

  """
  defdelegate get_order(order_hash), to: Clob

  @doc """
  List CLOB orders for a token.

  Returns `{:ok, orders}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_orders("1", limit: 10)
      # => {:ok, [%{"price" => "0.50", ...}, ...]}

  """
  defdelegate get_orders(token_id, opts \\ []), to: Clob

  @doc """
  Fetch current maker nonce from the CTF Exchange contract.

  Returns `{:ok, nonce}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.get_maker_nonce(address: "0x1234...")
      # => {:ok, 0}

  """
  defdelegate get_maker_nonce(opts \\ []), to: Clob

  @doc """
  Sign and place a CLOB order.

  This requires a Polygon private key, either via `POLYMARKET_PRIVATE_KEY` or by
  passing `private_key: "0x..."`.

  Returns `{:ok, order}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      order_params = %{
        tokenId: "1",
        side: "buy",
        makerAmount: "1000000",
        takerAmount: "1",
        nonce: "0"
      }
      Polymarket.place_order(order_params, private_key: "0x...")
      # => {:ok, %{"orderHash" => "0x...", ...}}

  """
  defdelegate place_order(params, opts \\ []), to: Clob

  @doc """
  Cancel a CLOB order.

  This requires a Polygon private key, either via `POLYMARKET_PRIVATE_KEY` or by
  passing `private_key: "0x..."`.

  Returns `{:ok, result}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.cancel_order("0xabc123...", private_key: "0x...")
      # => {:ok, %{"status" => "cancelled"}}

  """
  defdelegate cancel_order(order_hash, opts \\ []), to: Clob
end
