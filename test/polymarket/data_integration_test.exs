defmodule Polymarket.DataIntegrationTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"

    Application.put_env(:polymarket, :data_base_url, base_url)

    on_exit(fn ->
      Application.delete_env(:polymarket, :data_base_url)
    end)

    {:ok, bypass: bypass}
  end

  describe "get_positions/1" do
    test "returns positions for address", %{bypass: bypass} do
      mock_response = %{
        "positions" => [
          %{"market" => "123", "outcome" => "YES", "size" => "10"}
        ]
      }

      Bypass.expect(bypass, "GET", "/positions", fn conn ->
        assert conn.query_string =~ "address=0x1234"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, data} = Polymarket.Data.get_positions("0x1234")
      assert length(data["positions"]) == 1
    end
  end

  describe "get_trades/1" do
    test "returns trades", %{bypass: bypass} do
      mock_response = %{
        "trades" => [
          %{"price" => "0.50", "size" => "100", "side" => "buy"}
        ]
      }

      Bypass.expect(bypass, "GET", "/trades", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, data} = Polymarket.Data.get_trades(limit: 1)
      assert length(data["trades"]) == 1
    end
  end
end
