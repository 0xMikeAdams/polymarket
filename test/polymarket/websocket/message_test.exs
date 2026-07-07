defmodule Polymarket.Websocket.MessageTest do
  use ExUnit.Case, async: true

  alias Polymarket.Error
  alias Polymarket.Websocket.Message

  doctest Polymarket.Websocket.Message

  describe "subscribe/2" do
    test "accepts every documented subscription type as atom or string" do
      for type <- Message.subscription_types() do
        assert {:ok, %{"action" => "subscribe", "type" => ^type}} = Message.subscribe(type)

        assert {:ok, %{"action" => "subscribe", "type" => ^type}} =
                 Message.subscribe(String.to_atom(type))
      end
    end

    test "rejects unknown types without sending" do
      assert {:error, %Error{service: :websocket, kind: :invalid_request, message: message}} =
               Message.subscribe("orderbookz")

      assert message =~ "orderbookz"
    end

    test "rejects non-map filters" do
      assert {:error, %Error{kind: :invalid_request}} = Message.subscribe(:fills, [:not_a_map])
    end

    test "omits the filters key when filters are empty" do
      assert {:ok, payload} = Message.subscribe(:fills, %{})
      refute Map.has_key?(payload, "filters")
    end
  end

  describe "decode/1" do
    test "categorizes keepalive and lifecycle messages" do
      assert {:pong, _} = Message.decode(~s({"type":"pong"}))

      assert {:subscribed, %{"subscription_id" => "c:1"}} =
               Message.decode(~s({"type":"subscribed","subscription_id":"c:1"}))

      assert {:unsubscribed, _} = Message.decode(~s({"type":"unsubscribed"}))
      assert {:snapshot, %{"count" => 2}} = Message.decode(~s({"type":"snapshot","count":2}))

      assert {:error, %{"code" => "invalid_json"}} =
               Message.decode(~s({"type":"error","code":"invalid_json"}))
    end

    test "unknown and missing type values fall through to :event" do
      assert {:event, %{"type" => "price_feed"}} = Message.decode(~s({"type":"price_feed"}))
      assert {:event, %{"data" => 1}} = Message.decode(~s({"data":1}))
    end

    test "non-object JSON is invalid" do
      assert {:invalid, %Error{kind: :invalid_request}} = Message.decode("[1,2,3]")
    end
  end
end
