defmodule Polymarket.ClobIntegrationTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"

    Application.put_env(:polymarket, :clob_base_url, base_url)
    Application.put_env(:polymarket, :rpc_url, base_url)

    on_exit(fn ->
      Application.delete_env(:polymarket, :clob_base_url)
      Application.delete_env(:polymarket, :rpc_url)
    end)

    {:ok, bypass: bypass}
  end

  describe "get_markets/1" do
    test "returns CLOB markets", %{bypass: bypass} do
      mock_response = [
        %{"id" => "1", "condition_id" => "0xabc"},
        %{"id" => "2", "condition_id" => "0xdef"}
      ]

      Bypass.expect(bypass, "GET", "/markets", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, markets} = Polymarket.Clob.get_markets(limit: 2)
      assert length(markets) == 2
    end
  end

  describe "get_orderbook/2" do
    test "returns orderbook for token", %{bypass: bypass} do
      mock_response = %{
        "bids" => [%{"price" => "0.49", "size" => "100"}],
        "asks" => [%{"price" => "0.51", "size" => "100"}]
      }

      Bypass.expect(bypass, "GET", "/orderbook", fn conn ->
        assert conn.query_string =~ "tokenID=123"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, orderbook} = Polymarket.Clob.get_orderbook("123")
      assert length(orderbook["bids"]) == 1
      assert length(orderbook["asks"]) == 1
    end
  end

  describe "place_order/2" do
    test "places order successfully", %{bypass: bypass} do
      mock_response = %{
        "orderHash" => "0x123abc",
        "status" => "open"
      }

      Bypass.expect(bypass, "POST", "/order", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        order_data = Jason.decode!(body)

        assert order_data["order"]["tokenId"] == "1"
        assert order_data["order"]["side"] == "0"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      order_params = %{
        tokenId: "1",
        side: "buy",
        makerAmount: "1000000",
        takerAmount: "1",
        nonce: "0"
      }

      pk = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

      assert {:ok, result} = Polymarket.Clob.place_order(order_params, private_key: pk)
      assert result["orderHash"] == "0x123abc"
    end
  end

  describe "get_maker_nonce/1" do
    test "fetches maker nonce via eth_call", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["method"] == "eth_call"
        assert is_list(payload["params"])

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => "0x2a"})
        )
      end)

      assert {:ok, 42} =
               Polymarket.Clob.get_maker_nonce(
                 address: "0x0000000000000000000000000000000000000001"
               )
    end

    test "returns error for invalid address" do
      assert {:error, %Polymarket.Error{kind: :invalid_request}} =
               Polymarket.Clob.get_maker_nonce(address: "not-an-address")
    end
  end
end
