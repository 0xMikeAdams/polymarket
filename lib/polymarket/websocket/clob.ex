defmodule Polymarket.Websocket.Clob do
  @moduledoc """
  Realtime orderbook and order streaming over the official Polymarket CLOB
  WebSocket API (`wss://ws-subscriptions-clob.polymarket.com`).

  Unlike `Polymarket.Websocket` (the PolyNode firehose), this connects
  directly to Polymarket, is free, and needs no third-party API key. It
  offers two channels:

    * `:market` (default) – public orderbook data for specific token IDs:
      `book` snapshots, `price_change`, `tick_size_change`,
      `last_trade_price` (plus `best_bid_ask`, `new_market`, and
      `market_resolved` when `custom_features: true`)
    * `:user` – your own `order` and `trade` lifecycle updates; requires
      CLOB API credentials and a list of condition IDs

  ## Usage

      # Public market data
      {:ok, ws} = Polymarket.Websocket.Clob.start_link(assets_ids: ["7132107..."])

      receive do
        {:polymarket_clob_ws, :book, book} -> rebuild_orderbook(book)
        {:polymarket_clob_ws, :price_change, change} -> apply_change(change)
      end

      # Add/remove tokens without reconnecting (market channel only)
      :ok = Polymarket.Websocket.Clob.subscribe(ws, ["other_token_id"])
      :ok = Polymarket.Websocket.Clob.unsubscribe(ws, ["7132107..."])

      # Your own orders and fills
      {:ok, ws} =
        Polymarket.Websocket.Clob.start_link(
          channel: :user,
          markets: ["0xcondition_id..."],
          api_key: "...",
          secret: "...",
          passphrase: "..."
        )

  ## Handler messages

  The handler pid receives `{:polymarket_clob_ws, category, message}` tuples
  where `category` is the event type as an atom (`:book`, `:price_change`,
  `:tick_size_change`, `:last_trade_price`, `:best_bid_ask`, `:new_market`,
  `:market_resolved`, `:trade`, `:order`; unknown types arrive as `:event`),
  or one of:

    * `:invalid` – a frame that could not be decoded (`message` is a
      `Polymarket.Error`)
    * `:disconnected` – the connection dropped (a reconnect follows
      automatically)
    * `:transport_error` – a connection-level error (`message` is a
      `Polymarket.Error`; a reconnect follows automatically)

  ## Reconnection and keepalive

  The client sends the required `PING` keepalive every 10 seconds and
  reconnects with exponential backoff, re-sending the subscription for all
  currently tracked tokens (or markets). The server replays full `book`
  snapshots on subscribe, so orderbook state can always be rebuilt after a
  `:disconnected` message.

  ## Credentials (user channel)

  CLOB API credentials are resolved from the `:api_key`, `:secret`, and
  `:passphrase` options, falling back to the `POLYMARKET_CLOB_API_KEY`,
  `POLYMARKET_CLOB_SECRET`, and `POLYMARKET_CLOB_PASSPHRASE` environment
  variables.
  """

  use Fresh

  alias Polymarket.Error
  alias Polymarket.Websocket.Clob.Message

  @default_url "wss://ws-subscriptions-clob.polymarket.com/ws"

  # The CLOB WebSocket expects a literal PING roughly every 10 seconds.
  @keepalive_interval 10_000

  defmodule State do
    @moduledoc false
    defstruct handler: nil,
              channel: :market,
              assets_ids: [],
              markets: [],
              auth: nil,
              custom_features: false,
              keepalive_interval: nil,
              ping_timer: nil,
              connected?: false
  end

  @type client :: pid() | atom()

  @doc """
  Start a CLOB WebSocket connection.

  ## Options

    * `:channel` – `:market` (default) or `:user`
    * `:assets_ids` – token IDs to stream (market channel)
    * `:markets` – condition IDs to stream (user channel)
    * `:api_key` / `:secret` / `:passphrase` – CLOB API credentials
      (user channel; fall back to `POLYMARKET_CLOB_API_KEY`,
      `POLYMARKET_CLOB_SECRET`, `POLYMARKET_CLOB_PASSPHRASE`)
    * `:custom_features` – opt into `best_bid_ask`, `new_market`, and
      `market_resolved` events (market channel, defaults to `false`)
    * `:handler` – pid that receives `{:polymarket_clob_ws, category, message}`
      tuples (defaults to the calling process)
    * `:url` – endpoint override (defaults to `#{@default_url}`, or
      `:polymarket, :clob_ws_url`); the channel is appended as the path
    * `:name` – process registration, e.g. `{:local, MyApp.ClobWS}`

  Remaining options (`:ping_interval`, `:backoff_initial`, `:backoff_max`,
  `:error_logging`, `:info_logging`, `:transport_opts`, `:mint_upgrade_opts`,
  `:hibernate_after`) are passed through to `Fresh`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    channel = Keyword.get(opts, :channel, :market)

    with :ok <- validate_channel(channel),
         {:ok, auth} <- fetch_auth(channel, opts) do
      state = %State{
        handler: Keyword.get(opts, :handler, self()),
        channel: channel,
        assets_ids: Enum.uniq(Keyword.get(opts, :assets_ids, [])),
        markets: Keyword.get(opts, :markets, []),
        auth: auth,
        custom_features: Keyword.get(opts, :custom_features, false),
        keepalive_interval: Keyword.get(opts, :keepalive_interval, @keepalive_interval)
      }

      Fresh.start_link(build_uri(opts, channel), __MODULE__, state, fresh_opts(opts))
    end
  end

  @doc """
  Stream additional token IDs on a running market-channel connection.

  The server replies with `book` snapshots for the new tokens. Ignored on
  the user channel.
  """
  @spec subscribe(client(), [String.t()]) :: :ok
  def subscribe(client, assets_ids) when is_list(assets_ids) do
    send(client, {:subscribe_assets, assets_ids})
    :ok
  end

  @doc """
  Stop streaming the given token IDs on a running market-channel connection.
  Ignored on the user channel.
  """
  @spec unsubscribe(client(), [String.t()]) :: :ok
  def unsubscribe(client, assets_ids) when is_list(assets_ids) do
    send(client, {:unsubscribe_assets, assets_ids})
    :ok
  end

  @doc """
  Whether the underlying WebSocket connection is currently open.
  """
  @spec open?(client()) :: boolean()
  defdelegate open?(client), to: Fresh

  ## Fresh callbacks

  @impl true
  def handle_connect(_status, _headers, %State{} = state) do
    state = %{schedule_keepalive(state) | connected?: true}

    case initial_subscription(state) do
      nil -> {:ok, state}
      payload -> {:reply, {:text, Jason.encode!(payload)}, state}
    end
  end

  @impl true
  def handle_in({:text, frame}, %State{} = state) do
    case Message.decode(frame) do
      :pong ->
        {:ok, state}

      {:messages, messages} ->
        Enum.each(messages, fn {category, message} -> notify(state, category, message) end)
        {:ok, state}

      {:invalid, error} ->
        notify(state, :invalid, error)
        {:ok, state}
    end
  end

  def handle_in(_frame, state), do: {:ok, state}

  @impl true
  def handle_control(_frame, state), do: {:ok, state}

  @impl true
  def handle_info(:keepalive, %State{connected?: true} = state) do
    state = schedule_keepalive(state)
    {:reply, {:text, Message.ping()}, state}
  end

  def handle_info(:keepalive, %State{} = state), do: {:ok, state}

  def handle_info({:subscribe_assets, ids}, %State{channel: :market} = state) do
    state = %{state | assets_ids: Enum.uniq(state.assets_ids ++ ids)}

    if state.connected? do
      payload = Message.operation(:subscribe, ids, state.custom_features)
      {:reply, {:text, Jason.encode!(payload)}, state}
    else
      # Not connected yet (or reconnecting): handle_connect will include them.
      {:ok, state}
    end
  end

  def handle_info({:unsubscribe_assets, ids}, %State{channel: :market} = state) do
    state = %{state | assets_ids: state.assets_ids -- ids}

    if state.connected? do
      payload = Message.operation(:unsubscribe, ids, state.custom_features)
      {:reply, {:text, Jason.encode!(payload)}, state}
    else
      {:ok, state}
    end
  end

  # Dynamic subscription changes are only documented for the market channel.
  def handle_info({op, _ids}, %State{} = state)
      when op in [:subscribe_assets, :unsubscribe_assets],
      do: {:ok, state}

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def handle_disconnect(code, reason, %State{} = state) do
    notify(state, :disconnected, %{code: code, reason: reason})
    {:reconnect, %{cancel_keepalive(state) | connected?: false}}
  end

  @impl true
  def handle_error(error, %State{} = state) do
    notify(state, :transport_error, %Error{
      service: :websocket,
      kind: :transport_error,
      reason: error,
      message: "websocket connection error"
    })

    {:reconnect, %{cancel_keepalive(state) | connected?: false}}
  end

  @impl true
  def handle_terminate(_reason, _state), do: :ok

  ## Helpers

  defp validate_channel(channel) when channel in [:market, :user], do: :ok

  defp validate_channel(other) do
    {:error,
     %Error{
       service: :websocket,
       kind: :invalid_request,
       message: "unknown channel #{inspect(other)}, expected :market or :user"
     }}
  end

  defp fetch_auth(:market, _opts), do: {:ok, nil}

  defp fetch_auth(:user, opts) do
    auth = %{
      api_key: Keyword.get(opts, :api_key) || System.get_env("POLYMARKET_CLOB_API_KEY"),
      secret: Keyword.get(opts, :secret) || System.get_env("POLYMARKET_CLOB_SECRET"),
      passphrase: Keyword.get(opts, :passphrase) || System.get_env("POLYMARKET_CLOB_PASSPHRASE")
    }

    missing = for {key, value} <- auth, value in [nil, ""], do: key

    if missing == [] do
      {:ok, auth}
    else
      {:error,
       %Error{
         service: :websocket,
         kind: :invalid_request,
         message:
           "missing CLOB API credentials for the user channel: #{inspect(missing)} " <>
             "(pass options or set POLYMARKET_CLOB_API_KEY / POLYMARKET_CLOB_SECRET / " <>
             "POLYMARKET_CLOB_PASSPHRASE)"
       }}
    end
  end

  defp build_uri(opts, channel) do
    base =
      Keyword.get(opts, :url) ||
        Application.get_env(:polymarket, :clob_ws_url, @default_url)

    String.trim_trailing(base, "/") <> "/" <> to_string(channel)
  end

  defp fresh_opts(opts) do
    Keyword.take(opts, [
      :name,
      :ping_interval,
      :backoff_initial,
      :backoff_max,
      :error_logging,
      :info_logging,
      :transport_opts,
      :mint_upgrade_opts,
      :hibernate_after
    ])
  end

  defp initial_subscription(%State{channel: :market, assets_ids: []}), do: nil

  defp initial_subscription(%State{channel: :market} = state),
    do: Message.market_subscription(state.assets_ids, state.custom_features)

  defp initial_subscription(%State{channel: :user} = state),
    do: Message.user_subscription(state.markets, state.auth)

  defp notify(%State{handler: handler}, category, message) do
    send(handler, {:polymarket_clob_ws, category, message})
  end

  defp schedule_keepalive(%State{} = state) do
    state = cancel_keepalive(state)
    %{state | ping_timer: Process.send_after(self(), :keepalive, state.keepalive_interval)}
  end

  defp cancel_keepalive(%State{ping_timer: nil} = state), do: state

  defp cancel_keepalive(%State{ping_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | ping_timer: nil}
  end
end
