defmodule Polymarket.WebsocketTest do
  use ExUnit.Case, async: true

  alias Polymarket.Error
  alias Polymarket.Test.WSServer
  alias Polymarket.Websocket

  defp start_client(port, opts \\ []) do
    opts =
      Keyword.merge(
        [
          url: "ws://localhost:#{port}/ws",
          api_key: "pn_live_test",
          backoff_initial: 50,
          backoff_max: 200,
          error_logging: false,
          info_logging: false
        ],
        opts
      )

    {:ok, client} = Websocket.start_link(opts)
    client
  end

  test "start_link without an API key returns an error" do
    assert {:error, %Error{service: :websocket, kind: :invalid_request, message: message}} =
             Websocket.start_link(url: "ws://localhost:1/ws")

    assert message =~ "POLYNODE_API_KEY"
  end

  test "start_link with an invalid initial subscription returns an error" do
    assert {:error, %Error{kind: :invalid_request}} =
             Websocket.start_link(api_key: "pn_live_test", subscriptions: [:bogus])
  end

  test "appends the API key to the URL" do
    {_server, port} = WSServer.start(self())
    start_client(port, api_key: "pn_live_secret?&")

    # The server accepted the upgrade, so the URI (including the encoded key)
    # was well-formed.
    assert_receive {:ws_server, :connected, _conn}, 1_000
  end

  test "establishes initial subscriptions and streams events to the handler" do
    {_server, port} = WSServer.start(self())
    start_client(port, subscriptions: [{:wallets, %{"wallets" => ["0xabc"]}}])

    assert_receive {:ws_server, :connected, conn}, 1_000

    assert_receive {:ws_server, :subscribe_request,
                    %{
                      "action" => "subscribe",
                      "type" => "wallets",
                      "filters" => %{"wallets" => ["0xabc"]}
                    }},
                   1_000

    assert_receive {:polymarket_ws, :snapshot, %{"count" => 0}}, 1_000
    assert_receive {:polymarket_ws, :subscribed, %{"subscription_id" => "conn:0"}}, 1_000

    send(conn, {:push, %{"type" => "event", "data" => %{"side" => "BUY"}}})
    assert_receive {:polymarket_ws, :event, %{"data" => %{"side" => "BUY"}}}, 1_000
  end

  test "subscribe/3 and unsubscribe/2 round-trip at runtime" do
    {_server, port} = WSServer.start(self())
    client = start_client(port)

    assert_receive {:ws_server, :connected, _conn}, 1_000

    assert :ok = Websocket.subscribe(client, :large_trades, %{"min_size" => 5000})

    assert_receive {:ws_server, :subscribe_request,
                    %{"type" => "large_trades", "filters" => %{"min_size" => 5000}}},
                   1_000

    assert_receive {:polymarket_ws, :subscribed, %{"subscription_id" => id}}, 1_000

    assert :ok = Websocket.unsubscribe(client, id)
    assert_receive {:ws_server, :unsubscribe_request, %{"subscription_id" => ^id}}, 1_000
    assert_receive {:polymarket_ws, :unsubscribed, %{"subscription_id" => ^id}}, 1_000
  end

  test "invalid runtime subscription is rejected without sending" do
    {_server, port} = WSServer.start(self())
    client = start_client(port)

    assert_receive {:ws_server, :connected, _conn}, 1_000
    assert {:error, %Error{kind: :invalid_request}} = Websocket.subscribe(client, :bogus)
    refute_receive {:ws_server, :subscribe_request, _}, 200
  end

  test "reconnects after a server close and resubscribes with a since filter" do
    {_server, port} = WSServer.start(self())
    start_client(port, subscriptions: [:fills])

    assert_receive {:ws_server, :connected, conn}, 1_000
    assert_receive {:ws_server, :subscribe_request, request}, 1_000
    refute Map.has_key?(request, "filters")
    assert_receive {:polymarket_ws, :subscribed, _}, 1_000

    before_close = System.system_time(:millisecond)
    send(conn, {:close, 1012})

    assert_receive {:polymarket_ws, :disconnected, _}, 1_000
    assert_receive {:ws_server, :connected, _new_conn}, 1_000

    assert_receive {:ws_server, :subscribe_request,
                    %{"type" => "fills", "filters" => %{"since" => since}}},
                   1_000

    assert is_integer(since)
    assert since >= before_close
    assert_receive {:polymarket_ws, :subscribed, _}, 1_000
  end
end
