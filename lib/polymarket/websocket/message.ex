defmodule Polymarket.Websocket.Message do
  @moduledoc """
  Builds and decodes messages for the PolyNode Polymarket WebSocket API.

  See https://docs.polynode.dev/websocket/overview for the protocol reference.
  """

  alias Polymarket.Error

  @subscription_types ~w(
    fills settlements trades prices combos dome blocks wallets redemptions
    markets deposits large_trades global oracle chainlink
  )

  @typedoc "A PolyNode subscription type, e.g. `:fills` or `\"large_trades\"`."
  @type subscription_type :: atom() | String.t()

  @typedoc "A decoded server message category."
  @type category ::
          :heartbeat | :pong | :subscribed | :unsubscribed | :snapshot | :error | :event

  @doc """
  All subscription types supported by PolyNode.

  ## Examples

      iex> "fills" in Polymarket.Websocket.Message.subscription_types()
      true

  """
  @spec subscription_types() :: [String.t()]
  def subscription_types, do: @subscription_types

  @doc """
  Build a subscribe payload for the given subscription type and filters.

  Filters follow the PolyNode filter schema (`wallets`, `slugs`, `tokens`,
  `condition_ids`, `side`, `min_size`, `max_size`, `event_types`,
  `snapshot_count`, `since`, ...).

  ## Examples

      iex> Polymarket.Websocket.Message.subscribe(:fills)
      {:ok, %{"action" => "subscribe", "type" => "fills"}}

      iex> Polymarket.Websocket.Message.subscribe(:wallets, %{wallets: ["0xabc"]})
      {:ok, %{"action" => "subscribe", "type" => "wallets", "filters" => %{wallets: ["0xabc"]}}}

      iex> {:error, %Polymarket.Error{kind: :invalid_request}} =
      ...>   Polymarket.Websocket.Message.subscribe(:bogus)

  """
  @spec subscribe(subscription_type(), map()) :: {:ok, map()} | {:error, Error.t()}
  def subscribe(type, filters \\ %{}) do
    type = to_string(type)

    cond do
      type not in @subscription_types ->
        {:error,
         %Error{
           service: :websocket,
           kind: :invalid_request,
           message:
             "unknown subscription type #{inspect(type)}, expected one of: " <>
               Enum.join(@subscription_types, ", ")
         }}

      not is_map(filters) ->
        {:error,
         %Error{
           service: :websocket,
           kind: :invalid_request,
           message: "filters must be a map, got: #{inspect(filters)}"
         }}

      filters == %{} ->
        {:ok, %{"action" => "subscribe", "type" => type}}

      true ->
        {:ok, %{"action" => "subscribe", "type" => type, "filters" => filters}}
    end
  end

  @doc """
  Build an unsubscribe payload.

  With a `subscription_id` only that subscription is removed; with `nil` all
  subscriptions on the connection are removed.

  ## Examples

      iex> Polymarket.Websocket.Message.unsubscribe("conn-id:1")
      %{"action" => "unsubscribe", "subscription_id" => "conn-id:1"}

      iex> Polymarket.Websocket.Message.unsubscribe(nil)
      %{"action" => "unsubscribe"}

  """
  @spec unsubscribe(String.t() | nil) :: map()
  def unsubscribe(nil), do: %{"action" => "unsubscribe"}

  def unsubscribe(subscription_id) when is_binary(subscription_id),
    do: %{"action" => "unsubscribe", "subscription_id" => subscription_id}

  @doc """
  Build an application-level ping payload (keepalive).

  ## Examples

      iex> Polymarket.Websocket.Message.ping()
      %{"action" => "ping"}

  """
  @spec ping() :: map()
  def ping, do: %{"action" => "ping"}

  @doc """
  Decode a text frame from the server into a categorized message.

  Returns:

    * `{:heartbeat, message}` / `{:pong, message}` – keepalive traffic
    * `{:subscribed, message}` / `{:unsubscribed, message}` – subscription lifecycle
    * `{:snapshot, message}` – recent events replayed right after subscribing
    * `{:error, message}` – a structured server-side error
    * `{:event, message}` – any data-bearing message (`event`, `settlement`,
      `trade`, `block`, `oracle`, `price_feed`, ...)
    * `{:invalid, error}` – the frame was not a JSON object

  ## Examples

      iex> Polymarket.Websocket.Message.decode(~s({"type":"heartbeat","ts":1}))
      {:heartbeat, %{"type" => "heartbeat", "ts" => 1}}

      iex> {:event, %{"type" => "settlement"}} =
      ...>   Polymarket.Websocket.Message.decode(~s({"type":"settlement"}))

      iex> {:invalid, %Polymarket.Error{kind: :invalid_request}} =
      ...>   Polymarket.Websocket.Message.decode("not json")

  """
  @spec decode(binary()) :: {category(), map()} | {:invalid, Error.t()}
  def decode(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, %{"type" => type} = message} ->
        {categorize(type), message}

      {:ok, message} when is_map(message) ->
        {:event, message}

      {:ok, other} ->
        {:invalid,
         %Error{
           service: :websocket,
           kind: :invalid_request,
           body: other,
           message: "unexpected non-object frame"
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

  defp categorize("heartbeat"), do: :heartbeat
  defp categorize("pong"), do: :pong
  defp categorize("subscribed"), do: :subscribed
  defp categorize("unsubscribed"), do: :unsubscribed
  defp categorize("snapshot"), do: :snapshot
  defp categorize("error"), do: :error
  defp categorize(_), do: :event
end
