# Polymarket Elixir

An Elixir client library for interacting with the Polymarket APIs:

- **Gamma API** – Read-only market and event data (https://gamma-api.polymarket.com)
- **Data API** – User positions, trades, activity, holders, and portfolio value (https://data-api.polymarket.com)
- **CLOB API** – Full read and write trading operations on the Polymarket Conditional Tokens Framework exchange (https://clob.polymarket.com)
- **CLOB WebSocket** – Free, official realtime orderbook data and order/trade updates (wss://ws-subscriptions-clob.polymarket.com)
- **PolyNode WebSocket** – Enriched realtime fills, settlements, wallet activity, and oracle events via [PolyNode](https://docs.polynode.dev/websocket/overview) (wss://ws.polynode.dev, third-party, paid tiers)

The library supports **EIP-712 order signing** using your Polygon private key, allowing you to place and cancel orders directly.

## Features

- Clean, idiomatic Elixir interface
- Automatic JSON decoding with `Req` and `Jason`
- Post-processing of Gamma API JSON-string fields (`outcomes`, `outcomePrices`, etc.)
- Full CLOB order signing (EIP-712) via `eip712`
- Private key loading from `POLYMARKET_PRIVATE_KEY` environment variable or explicit option
- Comprehensive read endpoints for all three APIs
- Write support for placing and canceling orders on the CLOB
- Realtime event streaming over WebSocket (PolyNode) with automatic reconnection and gap backfill

## Installation

Add `polymarket` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:polymarket, "~> 0.4.0"},
    # or for the latest from Hex (when published)
    # {:polymarket, "~> 0.4"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Dependencies

The library depends on:

- `req ~> 0.4` – HTTP client
- `jason ~> 1.4` – JSON encoding/decoding
- `eip712 ~> 0.2.0` – EIP-712 signing and address derivation
- `fresh ~> 0.4` – WebSocket client (built on Mint)

## Usage

### Gamma API (Markets & Events)

```elixir
# List active markets
{:ok, markets} = Polymarket.list_markets(closed: false, limit: 20)

# Get a specific market
{:ok, market} = Polymarket.get_market("will-bitcoin-hit-100k-in-2025")

# List events
{:ok, events} = Polymarket.list_events(limit: 10)

# Get a specific event
{:ok, event} = Polymarket.get_event("us-presidential-election-2024")

# Tags and sports
{:ok, tags} = Polymarket.list_tags()
{:ok, sports} = Polymarket.list_sports()
```

### Data API (User & Trade Data)

```elixir
{:ok, positions} = Polymarket.get_positions("0x742d35Cc6634C0532925a3b844Bc454e4438f44e")
{:ok, trades} = Polymarket.get_trades(limit: 50)
{:ok, activity} = Polymarket.get_activity("0xYourAddress")
{:ok, holders} = Polymarket.get_holders("some-market-id")
{:ok, value} = Polymarket.get_value("0xYourAddress")
```

### CLOB API (Trading)

#### Read Operations

```elixir
{:ok, markets} = Polymarket.get_clob_markets(limit: 10)
{:ok, book} = Polymarket.get_orderbook("987654321", side: "buy")
{:ok, trades} = Polymarket.get_clob_trades("987654321")
{:ok, prices} = Polymarket.get_prices("987654321")
{:ok, orders} = Polymarket.get_orders("987654321", user: "0xYourAddress")
```

#### Write Operations (Placing & Canceling Orders)

Set your Polygon private key (hex string, with or without 0x prefix):

```bash
export POLYMARKET_PRIVATE_KEY="your_private_key_here"
```

Or pass it explicitly in calls.

Place an order (example: buy 50 outcome shares with 100 USDC):


```elixir
order_params = %{
  tokenId: "987654321",           # Token ID of the outcome
  side: "buy",                    # or "sell"
  makerAmount: "100000000",       # Amount in base units (e.g., 100 USDC = 100 * 10^6)
  takerAmount: "5000000000",      # Amount of outcome tokens (adjust decimals)
  nonce: "123"                    # Must be current on-chain nonce for your address
}

{:ok, response} = Polymarket.place_order(order_params)
# response includes orderHash, status, etc.
```

Cancel an order:

```elixir
{:ok, response} = Polymarket.cancel_order("0xorderhashhere")
```

### CLOB WebSocket Streaming (Official, Free)

Stream orderbook data for specific tokens straight from Polymarket — no API key needed:

```elixir
{:ok, ws} = Polymarket.Websocket.Clob.start_link(assets_ids: ["71321045679252212594626385532706912750332728571942532289631379312455583992563"])

receive do
  {:polymarket_clob_ws, :book, book} -> rebuild_orderbook(book)
  {:polymarket_clob_ws, :price_change, change} -> apply_change(change)
  {:polymarket_clob_ws, :last_trade_price, trade} -> track_trade(trade)
end

# Add or remove tokens without reconnecting
:ok = Polymarket.Websocket.Clob.subscribe(ws, ["another_token_id"])
:ok = Polymarket.Websocket.Clob.unsubscribe(ws, ["a_token_id"])
```

For your own order and fill updates, use the authenticated user channel with your CLOB API credentials (also via `POLYMARKET_CLOB_API_KEY` / `POLYMARKET_CLOB_SECRET` / `POLYMARKET_CLOB_PASSPHRASE`):

```elixir
{:ok, ws} =
  Polymarket.Websocket.Clob.start_link(
    channel: :user,
    markets: ["0xcondition_id..."],
    api_key: "...", secret: "...", passphrase: "..."
  )

receive do
  {:polymarket_clob_ws, :order, order} -> handle_order_update(order)
  {:polymarket_clob_ws, :trade, trade} -> handle_fill(trade)
end
```

The client sends the required `PING` keepalive every 10 seconds and reconnects automatically with exponential backoff, re-subscribing to all tracked tokens; the server replays full `book` snapshots on subscribe, so orderbook state can be rebuilt after any `:disconnected` message.

### PolyNode WebSocket Streaming (Enriched, Third-Party)

For enriched events the official feeds don't offer — pre-confirmation fills, arbitrary wallet tracking, whale alerts, settlement bundles, UMA oracle lifecycle — use the [PolyNode WebSocket API](https://docs.polynode.dev/websocket/overview). You need a PolyNode API key (`pn_live_...`):

```bash
export POLYNODE_API_KEY="pn_live_your_key_here"
```

Or set it via `:polymarket, :polynode_api_key` application env, or pass `api_key:` to `start_link/1`.

```elixir
# Start a connection; events are sent to the handler pid (defaults to the caller)
{:ok, ws} =
  Polymarket.Websocket.start_link(
    subscriptions: [
      :fills,
      {:large_trades, %{min_size: 5000}},
      {:wallets, %{wallets: ["0x742d35Cc6634C0532925a3b844Bc454e4438f44e"]}}
    ]
  )

# Handle incoming messages
receive do
  {:polymarket_ws, :event, event} ->
    # %{"type" => "event", "data" => %{"side" => "BUY", "price" => 0.85, ...}}
    handle_event(event)

  {:polymarket_ws, :subscribed, %{"subscription_id" => id}} ->
    # Save the id if you want to unsubscribe later
    track(id)
end

# Manage subscriptions at runtime
:ok = Polymarket.Websocket.subscribe(ws, :oracle)
:ok = Polymarket.Websocket.unsubscribe(ws, "subscription-id")
```

Available subscription types: `fills`, `settlements`, `trades`, `prices`, `combos`, `dome`, `blocks`, `wallets`, `redemptions`, `markets`, `deposits`, `large_trades`, `global`, `oracle`, `chainlink`. Filters (`tokens`, `slugs`, `condition_ids`, `wallets`, `side`, `min_size`, `event_types`, ...) follow the [PolyNode filter schema](https://docs.polynode.dev/websocket/subscribing).

On disconnect the client reconnects automatically with exponential backoff and re-establishes all subscriptions with a `since` filter set to the disconnect time, so missed events are backfilled (within your [PolyNode plan's](https://docs.polynode.dev) lookback window). Keepalive pings and server heartbeats are handled internally.


> Important: The nonce must be the current maker nonce from the CTF Exchange
> contract (`getMakerNonce(address)`). You can fetch it with
> `Polymarket.get_maker_nonce/1` by passing `address:` or `private_key:` and
> configuring an RPC endpoint (`rpc_url` option, `:polymarket, :rpc_url`, or
> `POLYGON_RPC_URL`).

## Configuration

- Private Key: Set `POLYMARKET_PRIVATE_KEY` in your environment, or pass `private_key: "0x..."` as an option to `place_order/2` or `cancel_order/2`.

- Order Defaults: Salt, expiration (1 year), feeRateBps (0), and signatureType (0 = EIP-712) are set automatically if not provided.

- HTTP Options: You can override base URLs and Req options via application env:
  - `:polymarket, :gamma_base_url`, `:polymarket, :data_base_url`, `:polymarket, :clob_base_url`
  - `:polymarket, :req_options` (global) and `:polymarket, :gamma_req_options` / `:data_req_options` / `:clob_req_options`

- CLOB WebSocket: No credentials needed for the market channel. The user channel takes `api_key:` / `secret:` / `passphrase:` options or `POLYMARKET_CLOB_API_KEY` / `POLYMARKET_CLOB_SECRET` / `POLYMARKET_CLOB_PASSPHRASE`. The endpoint can be overridden with `:polymarket, :clob_ws_url` or the `url:` option.

- PolyNode WebSocket: Set `POLYNODE_API_KEY` (or `:polymarket, :polynode_api_key`, or the `api_key:` option). The endpoint can be overridden with `:polymarket, :polynode_ws_url` or the `url:` option.

## Testing

The library includes unit doctests and integration tests under `test/polymarket/*`.
Integration tests use `Bypass` to stub HTTP responses for Gamma/Data/CLOB and
do not require live network calls.

```bash
mix test
```

## License

MIT License – see `LICENSE` for details.

## Contributing

Contributions are welcome! Feel free to open issues or pull requests.

## Disclaimer

This library interacts with live financial markets. Use at your own risk. Always test on small amounts first and verify order parameters carefully.
