defmodule Polymarket.GammaIntegrationTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"

    # Configure the test to use the bypass server
    Application.put_env(:polymarket, :gamma_base_url, base_url)

    on_exit(fn ->
      Application.delete_env(:polymarket, :gamma_base_url)
    end)

    {:ok, bypass: bypass}
  end

  describe "list_markets/1" do
    test "returns markets successfully", %{bypass: bypass} do
      mock_response = [
        %{
          "id" => "123",
          "question" => "Will Bitcoin hit $100k?",
          "outcomes" => ["YES", "NO"],
          "outcomePrices" => ["0.48", "0.52"]
        }
      ]

      Bypass.expect(bypass, "GET", "/markets", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, markets} = Polymarket.Gamma.list_markets(limit: 1)
      assert length(markets) == 1
      assert hd(markets)["question"] == "Will Bitcoin hit $100k?"
    end

    test "handles API errors", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/markets", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: "Internal server error"}))
      end)

      assert {:error, %Polymarket.Error{kind: :http_error, status: 500}} =
               Polymarket.Gamma.list_markets()
    end
  end

  describe "get_market/1" do
    test "returns market by slug", %{bypass: bypass} do
      mock_response = %{
        "id" => "456",
        "question" => "Will Trump win 2024?",
        "slug" => "will-trump-win-2024"
      }

      Bypass.expect(bypass, "GET", "/markets/slug/will-trump-win-2024", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, market} = Polymarket.Gamma.get_market("will-trump-win-2024")
      assert market["question"] == "Will Trump win 2024?"
    end
  end
end
