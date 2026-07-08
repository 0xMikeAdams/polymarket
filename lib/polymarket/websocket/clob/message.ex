defmodule Polymarket.Websocket.Clob.Message do
  @moduledoc """
  Builds and decodes messages for the official Polymarket CLOB WebSocket API.

  See https://docs.polymarket.com/developers/CLOB/websocket/wss-overview for
  the protocol reference.
  """

  alias Polymarket.Error

  @event_categories %{
    "book" => :book,
    "price_change" => :price_change,
    "tick_size_change" => :tick_size_change,
    "last_trade_price" => :last_trade_price,
    "best_bid_ask" => :best_bid_ask,
    "new_market" => :new_market,
    "market_resolved" => :market_resolved,
    "trade" => :trade,
    "order" => :order
  }

  @typedoc "A decoded CLOB event category; unknown event types fall through to `:event`."
  @type category ::
          :book
          | :price_change
          | :tick_size_change
          | :last_trade_price
          | :best_bid_ask
          | :new_market
          | :market_resolved
          | :trade
          | :order
          | :event

  @doc """
  Build the initial subscription payload for the market channel.

  ## Examples

      iex> Polymarket.Websocket.Clob.Message.market_subscription(["123"], false)
      %{"type" => "market", "assets_ids" => ["123"]}

      iex> Polymarket.Websocket.Clob.Message.market_subscription(["123"], true)
      %{"type" => "market", "assets_ids" => ["123"], "custom_feature_enabled" => true}

  """
  @spec market_subscription([String.t()], boolean()) :: map()
  def market_subscription(assets_ids, custom_features?) when is_list(assets_ids) do
    %{"type" => "market", "assets_ids" => assets_ids}
    |> put_custom_features(custom_features?)
  end

  @doc """
  Build the initial subscription payload for the authenticated user channel.

  `markets` is a list of condition IDs; `auth` holds the CLOB API credentials.

  ## Examples

      iex> Polymarket.Websocket.Clob.Message.user_subscription(
      ...>   ["0xabc"],
      ...>   %{api_key: "k", secret: "s", passphrase: "p"}
      ...> )
      %{
        "type" => "user",
        "markets" => ["0xabc"],
        "auth" => %{"apiKey" => "k", "secret" => "s", "passphrase" => "p"}
      }

  """
  @spec user_subscription([String.t()], %{
          api_key: String.t(),
          secret: String.t(),
          passphrase: String.t()
        }) :: map()
  def user_subscription(markets, %{api_key: api_key, secret: secret, passphrase: passphrase})
      when is_list(markets) do
    %{
      "type" => "user",
      "markets" => markets,
      "auth" => %{"apiKey" => api_key, "secret" => secret, "passphrase" => passphrase}
    }
  end

  @doc """
  Build a dynamic subscribe/unsubscribe payload for the market channel.

  ## Examples

      iex> Polymarket.Websocket.Clob.Message.operation(:subscribe, ["123"], false)
      %{"operation" => "subscribe", "assets_ids" => ["123"]}

      iex> Polymarket.Websocket.Clob.Message.operation(:unsubscribe, ["123"], false)
      %{"operation" => "unsubscribe", "assets_ids" => ["123"]}

  """
  @spec operation(:subscribe | :unsubscribe, [String.t()], boolean()) :: map()
  def operation(operation, assets_ids, custom_features?)
      when operation in [:subscribe, :unsubscribe] and is_list(assets_ids) do
    %{"operation" => to_string(operation), "assets_ids" => assets_ids}
    |> put_custom_features(custom_features? and operation == :subscribe)
  end

  @doc """
  The keepalive frame text. The CLOB WebSocket expects a literal `PING`
  roughly every 10 seconds and answers with `PONG`.

  ## Examples

      iex> Polymarket.Websocket.Clob.Message.ping()
      "PING"

  """
  @spec ping() :: String.t()
  def ping, do: "PING"

  @doc """
  Decode a text frame from the server.

  The CLOB WebSocket delivers events either as a single JSON object or as a
  JSON array of objects (e.g. the initial `book` snapshots), plus literal
  `PONG` keepalive replies. Returns:

    * `:pong` – keepalive reply, handled internally
    * `{:messages, [{category, message}]}` – decoded events; `category` is
      the `"event_type"` mapped to an atom (unknown types become `:event`)
    * `{:invalid, error}` – the frame was not valid JSON

  ## Examples

      iex> Polymarket.Websocket.Clob.Message.decode("PONG")
      :pong

      iex> Polymarket.Websocket.Clob.Message.decode(~s({"event_type":"book","asset_id":"1"}))
      {:messages, [{:book, %{"event_type" => "book", "asset_id" => "1"}}]}

      iex> Polymarket.Websocket.Clob.Message.decode(~s([{"event_type":"trade"},{"event_type":"odd"}]))
      {:messages, [{:trade, %{"event_type" => "trade"}}, {:event, %{"event_type" => "odd"}}]}

      iex> {:invalid, %Polymarket.Error{kind: :invalid_request}} =
      ...>   Polymarket.Websocket.Clob.Message.decode("not json")

  """
  @spec decode(binary()) :: :pong | {:messages, [{category(), map()}]} | {:invalid, Error.t()}
  def decode("PONG"), do: :pong

  def decode(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, messages} when is_list(messages) ->
        {:messages, Enum.map(messages, &categorize/1)}

      {:ok, message} when is_map(message) ->
        {:messages, [categorize(message)]}

      {:ok, other} ->
        {:invalid,
         %Error{
           service: :websocket,
           kind: :invalid_request,
           body: other,
           message: "unexpected frame shape"
         }}

      {:error, reason} ->
        {:invalid,
         %Error{
           service: :websocket,
           kind: :invalid_request,
           reason: reason,
           body: text,
           message: "failed to decode frame as JSON"
         }}
    end
  end

  defp categorize(%{"event_type" => type} = message),
    do: {Map.get(@event_categories, type, :event), message}

  defp categorize(message), do: {:event, message}

  defp put_custom_features(payload, true), do: Map.put(payload, "custom_feature_enabled", true)
  defp put_custom_features(payload, false), do: payload
end
