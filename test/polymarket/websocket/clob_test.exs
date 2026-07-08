defmodule Polymarket.Websocket.ClobTest do
  use ExUnit.Case, async: true

  alias Polymarket.Error
  alias Polymarket.Test.ClobWSServer
  alias Polymarket.Websocket.Clob

  defp start_client(port, opts) do
    opts =
      Keyword.merge(
        [
          url: "ws://localhost:#{port}/ws",
          backoff_initial: 50,
          backoff_max: 200,
          error_logging: false,
          info_logging: false
        ],
        opts
      )

    {:ok, client} = Clob.start_link(opts)
    client
  end

  test "rejects an unknown channel" do
    assert {:error, %Error{kind: :invalid_request, message: message}} =
             Clob.start_link(channel: :sports)

    assert message =~ ":sports"
  end

  test "user channel requires credentials" do
    assert {:error, %Error{kind: :invalid_request, message: message}} =
             Clob.start_link(channel: :user, markets: ["0xabc"], api_key: "k")

    assert message =~ ":secret"
    assert message =~ ":passphrase"
  end

  test "market channel connects to /market and subscribes to the given tokens" do
    {_server, port} = ClobWSServer.start(self())
    start_client(port, assets_ids: ["1", "2", "1"])

    assert_receive {:clob_server, :connected, {_conn, "/ws/market"}}, 1_000

    assert_receive {:clob_server, :message,
                    %{"type" => "market", "assets_ids" => ["1", "2"]} = subscription},
                   1_000

    refute Map.has_key?(subscription, "custom_feature_enabled")
  end

  test "custom_features flag is included in the subscription" do
    {_server, port} = ClobWSServer.start(self())
    start_client(port, assets_ids: ["1"], custom_features: true)

    assert_receive {:clob_server, :message, %{"custom_feature_enabled" => true}}, 1_000
  end

  test "delivers single events and event batches to the handler" do
    {_server, port} = ClobWSServer.start(self())
    start_client(port, assets_ids: ["1"])

    assert_receive {:clob_server, :connected, {conn, _path}}, 1_000

    send(conn, {:push, [%{"event_type" => "book", "asset_id" => "1", "bids" => []}]})
    assert_receive {:polymarket_clob_ws, :book, %{"asset_id" => "1"}}, 1_000

    send(conn, {:push, %{"event_type" => "price_change", "asset_id" => "1"}})
    assert_receive {:polymarket_clob_ws, :price_change, _}, 1_000

    send(conn, {:push, %{"event_type" => "something_new"}})
    assert_receive {:polymarket_clob_ws, :event, %{"event_type" => "something_new"}}, 1_000
  end

  test "subscribe/2 and unsubscribe/2 send dynamic operations" do
    {_server, port} = ClobWSServer.start(self())
    client = start_client(port, assets_ids: ["1"])

    assert_receive {:clob_server, :message, %{"type" => "market"}}, 1_000

    assert :ok = Clob.subscribe(client, ["2"])

    assert_receive {:clob_server, :message, %{"operation" => "subscribe", "assets_ids" => ["2"]}},
                   1_000

    assert :ok = Clob.unsubscribe(client, ["1"])

    assert_receive {:clob_server, :message,
                    %{"operation" => "unsubscribe", "assets_ids" => ["1"]}},
                   1_000
  end

  test "sends PING keepalives and survives the PONG reply" do
    {_server, port} = ClobWSServer.start(self())
    start_client(port, assets_ids: ["1"], keepalive_interval: 50)

    assert_receive {:clob_server, :connected, {conn, _path}}, 1_000
    assert_receive {:clob_server, :ping, _}, 1_000
    assert_receive {:clob_server, :ping, _}, 1_000

    # Still alive and streaming after the PONGs came back.
    send(conn, {:push, %{"event_type" => "book"}})
    assert_receive {:polymarket_clob_ws, :book, _}, 1_000
  end

  test "reconnects after a server close and resubscribes with current tokens" do
    {_server, port} = ClobWSServer.start(self())
    client = start_client(port, assets_ids: ["1"])

    assert_receive {:clob_server, :connected, {conn, _path}}, 1_000
    assert_receive {:clob_server, :message, %{"type" => "market", "assets_ids" => ["1"]}}, 1_000

    # Change subscriptions, then drop the connection.
    assert :ok = Clob.subscribe(client, ["2"])
    assert_receive {:clob_server, :message, %{"operation" => "subscribe"}}, 1_000

    send(conn, {:close, 1012})
    assert_receive {:polymarket_clob_ws, :disconnected, _}, 1_000

    assert_receive {:clob_server, :connected, {_new_conn, _path}}, 1_000

    assert_receive {:clob_server, :message, %{"type" => "market", "assets_ids" => ["1", "2"]}},
                   1_000
  end

  test "user channel connects to /user with auth and markets" do
    {_server, port} = ClobWSServer.start(self())

    start_client(port,
      channel: :user,
      markets: ["0xabc"],
      api_key: "key",
      secret: "sec",
      passphrase: "pass"
    )

    assert_receive {:clob_server, :connected, {conn, "/ws/user"}}, 1_000

    assert_receive {:clob_server, :message,
                    %{
                      "type" => "user",
                      "markets" => ["0xabc"],
                      "auth" => %{"apiKey" => "key", "secret" => "sec", "passphrase" => "pass"}
                    }},
                   1_000

    send(conn, {:push, %{"event_type" => "order", "id" => "0xdef"}})
    assert_receive {:polymarket_clob_ws, :order, %{"id" => "0xdef"}}, 1_000
  end
end
