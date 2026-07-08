defmodule Polymarket.Websocket.Clob.MessageTest do
  use ExUnit.Case, async: true

  alias Polymarket.Websocket.Clob.Message

  doctest Polymarket.Websocket.Clob.Message

  test "custom_feature_enabled is never sent on unsubscribe operations" do
    refute Map.has_key?(Message.operation(:unsubscribe, ["1"], true), "custom_feature_enabled")
    assert Message.operation(:subscribe, ["1"], true)["custom_feature_enabled"] == true
  end

  test "objects without an event_type decode as :event" do
    assert {:messages, [{:event, %{"data" => 1}}]} = Message.decode(~s({"data":1}))
  end
end
