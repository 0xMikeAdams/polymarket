defmodule Polymarket.Websocket do
  @moduledoc """
  Realtime Polymarket event streaming over the PolyNode WebSocket API.

  Connects to `wss://ws.polynode.dev/ws` and streams Polymarket fills,
  settlements, trades, prices, oracle resolutions, and more. See
  https://docs.polynode.dev/websocket/overview for the protocol and
  https://docs.polynode.dev for API keys and plan limits.

  ## Usage

      {:ok, ws} =
        Polymarket.Websocket.start_link(
          api_key: "pn_live_...",
          subscriptions: [:fills, {:wallets, %{wallets: ["0xabc..."]}}]
        )

      # Messages arrive at the handler process (defaults to the caller):
      receive do
        {:polymarket_ws, :event, event} -> handle_fill(event)
        {:polymarket_ws, :subscribed, confirmation} -> track_subscription(confirmation)
      end

  Subscriptions can also be managed at runtime:

      :ok = Polymarket.Websocket.subscribe(ws, :large_trades, %{min_size: 5000})
      :ok = Polymarket.Websocket.unsubscribe(ws, "subscription-id")

  ## Handler messages

  The handler pid receives `{:polymarket_ws, category, message}` tuples where
  `category` is one of:

    * `:event` – any data-bearing message (fills, settlements, trades, blocks,
      oracle events, price feeds, ...); `message` is the decoded JSON map
    * `:snapshot` – recent events replayed right after subscribing
    * `:subscribed` / `:unsubscribed` – subscription confirmations (save
      `message["subscription_id"]` for `unsubscribe/2`)
    * `:error` – a structured server-side error map
    * `:invalid` – a frame that could not be decoded (`message` is a
      `Polymarket.Error`)
    * `:disconnected` – the connection dropped (a reconnect follows
      automatically)
    * `:transport_error` – a connection-level error (`message` is a
      `Polymarket.Error`; a reconnect follows automatically)

  Server keepalive traffic (`heartbeat`/`pong`) is handled internally and not
  forwarded.

  ## Reconnection

  On disconnect the client reconnects with exponential backoff (via `Fresh`)
  and re-establishes all subscriptions, adding a `since` filter set to the
  disconnect time so missed events are backfilled within your plan's lookback
  window.

  ## Configuration

  The API key is resolved from the `:api_key` option, the
  `:polymarket, :polynode_api_key` application env, or the `POLYNODE_API_KEY`
  environment variable. The endpoint can be overridden with the `:url` option
  or `:polymarket, :polynode_ws_url`.
  """

  use Fresh

  alias Polymarket.Error
  alias Polymarket.Websocket.Message

  @default_url "wss://ws.polynode.dev/ws"

  # PolyNode closes idle connections after 5 minutes and recommends an
  # application-level ping every 30-60 seconds.
  @keepalive_interval 30_000

  defmodule State do
    @moduledoc false
    # connected?: set once handle_connect has run (the upgrade handshake is
    # complete) — frames must not be sent before that, or after a disconnect.
    defstruct handler: nil,
              subscriptions: [],
              disconnected_at: nil,
              ping_timer: nil,
              connected?: false
  end

  @type client :: pid() | atom()

  @doc """
  Start a PolyNode WebSocket connection.

  ## Options

    * `:api_key` – PolyNode API key (falls back to the
      `:polymarket, :polynode_api_key` application env, then the
      `POLYNODE_API_KEY` environment variable)
    * `:handler` – pid that receives `{:polymarket_ws, category, message}`
      tuples (defaults to the calling process)
    * `:subscriptions` – initial subscriptions, each a type
      (e.g. `:fills`) or a `{type, filters}` tuple
    * `:url` – endpoint override (defaults to `#{@default_url}`, or
      `:polymarket, :polynode_ws_url`)
    * `:name` – process registration, e.g. `{:local, MyApp.PolymarketWS}`

  Remaining options (`:ping_interval`, `:backoff_initial`, `:backoff_max`,
  `:error_logging`, `:info_logging`, `:transport_opts`, `:mint_upgrade_opts`,
  `:hibernate_after`) are passed through to `Fresh`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    handler = Keyword.get(opts, :handler, self())

    with {:ok, api_key} <- fetch_api_key(opts),
         {:ok, subscriptions} <- build_specs(Keyword.get(opts, :subscriptions, [])) do
      state = %State{handler: handler, subscriptions: subscriptions}
      Fresh.start_link(build_uri(opts, api_key), __MODULE__, state, fresh_opts(opts))
    end
  end

  @doc """
  Add a subscription on a running connection.

  Returns `:ok` once the request is dispatched; the server confirms with a
  `{:polymarket_ws, :subscribed, message}` handler message carrying the
  `subscription_id`. Returns `{:error, %Polymarket.Error{}}` for an unknown
  subscription type or invalid filters (nothing is sent).
  """
  @spec subscribe(client(), Message.subscription_type(), map()) :: :ok | {:error, Error.t()}
  def subscribe(client, type, filters \\ %{}) do
    with {:ok, _payload} <- Message.subscribe(type, filters) do
      send(client, {:subscribe, %{type: to_string(type), filters: filters, id: nil}})
      :ok
    end
  end

  @doc """
  Remove a subscription by its `subscription_id`, or all subscriptions when
  called without an id.

  The server confirms with a `{:polymarket_ws, :unsubscribed, message}`
  handler message.
  """
  @spec unsubscribe(client(), String.t() | nil) :: :ok
  def unsubscribe(client, subscription_id \\ nil)
      when is_binary(subscription_id) or is_nil(subscription_id) do
    send(client, {:unsubscribe, subscription_id})
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
    state = schedule_keepalive(state)
    subscriptions = Enum.map(state.subscriptions, &%{&1 | id: nil})
    frames = Enum.map(subscriptions, &subscribe_frame(&1, state.disconnected_at))
    state = %{state | subscriptions: subscriptions, disconnected_at: nil, connected?: true}

    case frames do
      [] -> {:ok, state}
      frames -> {:reply, frames, state}
    end
  end

  @impl true
  def handle_in({:text, frame}, %State{} = state) do
    case Message.decode(frame) do
      {category, _message} when category in [:heartbeat, :pong] ->
        {:ok, state}

      {:subscribed, message} ->
        notify(state, :subscribed, message)
        {:ok, %{state | subscriptions: confirm(state.subscriptions, message)}}

      {:unsubscribed, message} ->
        notify(state, :unsubscribed, message)
        {:ok, %{state | subscriptions: drop(state.subscriptions, message)}}

      {category, message} ->
        notify(state, category, message)
        {:ok, state}
    end
  end

  def handle_in(_frame, state), do: {:ok, state}

  @impl true
  def handle_control(_frame, state), do: {:ok, state}

  @impl true
  def handle_info(:keepalive, %State{connected?: true} = state) do
    state = schedule_keepalive(state)
    {:reply, {:text, Jason.encode!(Message.ping())}, state}
  end

  def handle_info(:keepalive, %State{} = state), do: {:ok, state}

  def handle_info({:subscribe, spec}, %State{} = state) do
    state = %{state | subscriptions: state.subscriptions ++ [spec]}

    if state.connected? do
      {:reply, subscribe_frame(spec, nil), state}
    else
      # Not connected yet (or reconnecting): handle_connect will send it.
      {:ok, state}
    end
  end

  def handle_info({:unsubscribe, subscription_id}, %State{connected?: true} = state) do
    {:reply, {:text, Jason.encode!(Message.unsubscribe(subscription_id))}, state}
  end

  def handle_info({:unsubscribe, nil}, %State{} = state) do
    # Not connected: drop locally so handle_connect does not resubscribe.
    {:ok, %{state | subscriptions: []}}
  end

  def handle_info({:unsubscribe, subscription_id}, %State{} = state) do
    subscriptions = Enum.reject(state.subscriptions, &(&1.id == subscription_id))
    {:ok, %{state | subscriptions: subscriptions}}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def handle_disconnect(code, reason, %State{} = state) do
    notify(state, :disconnected, %{code: code, reason: reason})

    state = %{
      cancel_keepalive(state)
      | disconnected_at: state.disconnected_at || System.system_time(:millisecond),
        connected?: false
    }

    {:reconnect, state}
  end

  @impl true
  def handle_error(error, %State{} = state) do
    notify(state, :transport_error, %Error{
      service: :websocket,
      kind: :transport_error,
      reason: error,
      message: "websocket connection error"
    })

    state = %{
      cancel_keepalive(state)
      | disconnected_at: state.disconnected_at || System.system_time(:millisecond),
        connected?: false
    }

    {:reconnect, state}
  end

  @impl true
  def handle_terminate(_reason, _state), do: :ok

  ## Helpers

  defp fetch_api_key(opts) do
    key =
      Keyword.get(opts, :api_key) ||
        Application.get_env(:polymarket, :polynode_api_key) ||
        System.get_env("POLYNODE_API_KEY")

    if key in [nil, ""] do
      {:error,
       %Error{
         service: :websocket,
         kind: :invalid_request,
         message:
           "missing PolyNode API key: pass api_key:, set :polymarket, :polynode_api_key, " <>
             "or export POLYNODE_API_KEY"
       }}
    else
      {:ok, key}
    end
  end

  defp build_uri(opts, api_key) do
    base =
      Keyword.get(opts, :url) ||
        Application.get_env(:polymarket, :polynode_ws_url, @default_url)

    separator = if String.contains?(base, "?"), do: "&", else: "?"
    base <> separator <> "key=" <> URI.encode_www_form(api_key)
  end

  defp build_specs(subscriptions) do
    subscriptions
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      {type, filters} =
        case entry do
          {type, filters} -> {type, filters}
          type -> {type, %{}}
        end

      case Message.subscribe(type, filters) do
        {:ok, _payload} ->
          {:cont, {:ok, [%{type: to_string(type), filters: filters, id: nil} | acc]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
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

  defp subscribe_frame(%{type: type, filters: filters}, since) do
    filters =
      if since do
        filters |> Map.drop([:since, "since"]) |> Map.put("since", since)
      else
        filters
      end

    {:ok, payload} = Message.subscribe(type, filters)
    {:text, Jason.encode!(payload)}
  end

  # Confirmations arrive in the order subscribe requests were sent, so assign
  # the subscription_id to the oldest unconfirmed subscription.
  defp confirm(subscriptions, %{"subscription_id" => id}) do
    case Enum.find_index(subscriptions, &is_nil(&1.id)) do
      nil -> subscriptions
      index -> List.update_at(subscriptions, index, &%{&1 | id: id})
    end
  end

  defp confirm(subscriptions, _message), do: subscriptions

  defp drop(subscriptions, %{"subscription_id" => id}),
    do: Enum.reject(subscriptions, &(&1.id == id))

  # An unsubscribed confirmation without a subscription_id means all
  # subscriptions were removed.
  defp drop(_subscriptions, _message), do: []

  defp notify(%State{handler: handler}, category, message) do
    send(handler, {:polymarket_ws, category, message})
  end

  defp schedule_keepalive(%State{} = state) do
    state = cancel_keepalive(state)
    %{state | ping_timer: Process.send_after(self(), :keepalive, @keepalive_interval)}
  end

  defp cancel_keepalive(%State{ping_timer: nil} = state), do: state

  defp cancel_keepalive(%State{ping_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | ping_timer: nil}
  end
end
