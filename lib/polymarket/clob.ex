defmodule Polymarket.Clob do
  @moduledoc """
  Wrapper for the Polymarket CLOB API.

  Includes read endpoints plus EIP-712 signing to place and cancel orders.
  """

  alias EIP712.Typed
  alias Polymarket.Clob.Client
  alias Polymarket.Error

  @contract "0x4FbF41d5B3570dEFd03C39a9A4D8dE6bD8b8982E"
  @chain_id 137
  @zero "0x0000000000000000000000000000000000000000"
  @contract_bin EIP712.Util.decode_hex!(@contract)
  @zero_bin EIP712.Util.decode_hex!(@zero)
  @maker_nonce_selector EIP712.Hash.keccak("getMakerNonce(address)") |> binary_part(0, 4)

  @order_domain %{
    name: "Polymarket CTF Exchange",
    version: "1",
    chainId: @chain_id,
    verifyingContract: @contract
  }

  @auth_domain %{
    name: "ClobAuthDomain",
    version: "1",
    chainId: @chain_id
  }

  @order_domain_types %{
    "EIP712Domain" => %Typed.Type{
      fields: [
        {"name", :string},
        {"version", :string},
        {"chainId", {:uint, 256}},
        {"verifyingContract", :address}
      ]
    }
  }

  @auth_domain_types %{
    "EIP712Domain" => %Typed.Type{
      fields: [
        {"name", :string},
        {"version", :string},
        {"chainId", {:uint, 256}}
      ]
    }
  }

  @order_types %{
    "Order" => %Typed.Type{
      fields: [
        {"salt", {:uint, 256}},
        {"maker", :address},
        {"signer", :address},
        {"taker", :address},
        {"tokenId", {:uint, 256}},
        {"makerAmount", {:uint, 256}},
        {"takerAmount", {:uint, 256}},
        {"expiration", {:uint, 256}},
        {"nonce", {:uint, 256}},
        {"feeRateBps", {:uint, 256}},
        {"side", {:uint, 8}},
        {"signatureType", {:uint, 8}}
      ]
    }
  }

  @auth_types %{
    "ClobAuth" => %Typed.Type{
      fields: [
        {"address", :address},
        {"timestamp", :string},
        {"nonce", {:uint, 256}},
        {"message", :string}
      ]
    }
  }

  @doc """
  List CLOB markets.

  Returns `{:ok, markets}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.get_markets(limit: 10)
      # => {:ok, [%{"id" => "...", ...}, ...]}

  """
  def get_markets(opts \\ []), do: Client.get("/markets", params: Enum.into(opts, %{})) |> resp()

  @doc """
  Get an orderbook for a token ID.

  Returns `{:ok, orderbook}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.get_orderbook("1", side: "buy")
      # => {:ok, %{"bids" => [...], "asks" => [...]}}

  """
  def get_orderbook(token_id, opts \\ []),
    do:
      Client.get("/orderbook", params: Map.put(Enum.into(opts, %{}), :tokenID, token_id))
      |> resp()

  @doc """
  List trades for a token ID.

  Returns `{:ok, trades}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.get_trades("1")
      # => {:ok, [%{"price" => "0.50", ...}, ...]}

  """
  def get_trades(token_id), do: Client.get("/trades", params: %{tokenID: token_id}) |> resp()

  @doc """
  Get prices for a token ID.

  Returns `{:ok, prices}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.get_prices("1")
      # => {:ok, %{"bid" => "0.49", "ask" => "0.51"}}

  """
  def get_prices(token_id), do: Client.get("/prices", params: %{tokenID: token_id}) |> resp()

  @doc """
  Get an order by order hash.

  Returns `{:ok, order}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.get_order("0xabc123...")
      # => {:ok, %{"status" => "open", ...}}

  """
  def get_order(hash), do: Client.get("/order", params: %{orderHash: hash}) |> resp()

  @doc """
  List orders for a token ID.

  Returns `{:ok, orders}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.get_orders("1", limit: 10)
      # => {:ok, [%{"price" => "0.50", ...}, ...]}

  """
  def get_orders(token_id, opts \\ []),
    do: Client.get("/orders", params: Map.put(Enum.into(opts, %{}), :tokenID, token_id)) |> resp()

  @doc """
  Fetch the current maker nonce from the CTF Exchange contract.

  This is required for valid order placement on Polymarket CLOB.

  You can provide either:
  - `address: "0x..."`
  - `private_key: "0x..."`

  RPC endpoint resolution order:
  - `opts[:rpc_url]`
  - `Application.get_env(:polymarket, :rpc_url)`
  - `POLYGON_RPC_URL`

  Returns `{:ok, nonce}` on success or `{:error, %Polymarket.Error{}}` on failure.
  """
  def get_maker_nonce(opts \\ []) do
    with {:ok, address_bin} <- nonce_address(opts),
         {:ok, rpc_url} <- rpc_url(opts),
         {:ok, rpc_result} <- rpc_maker_nonce_call(rpc_url, address_bin),
         {:ok, nonce} <- decode_nonce(rpc_result) do
      {:ok, nonce}
    end
  end

  @doc """
  Sign and place a CLOB order.

  This requires a Polygon private key, either via `POLYMARKET_PRIVATE_KEY` or by
  passing `private_key: "0x..."`.

  Returns `{:ok, order}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      order_params = %{
        tokenId: "1",
        side: "buy",
        makerAmount: "1000000",
        takerAmount: "1",
        nonce: "0"
      }
      Polymarket.Clob.place_order(order_params, private_key: "0x...")
      # => {:ok, %{"orderHash" => "0x...", ...}}

  """
  def place_order(params, opts \\ []) do
    with {:ok, private_key} <- private_key(opts),
         {:ok, order} <- build_order(params, private_key),
         {:ok, poly_sig} <- auth_signature(private_key) do
      body = %{
        order: order.value,
        signature: order.signature,
        orderType: opts[:order_type] || "GTC"
      }

      Client.post("/order", json: body, headers: [{"poly-signature", poly_sig}]) |> resp()
    end
  end

  @doc """
  Cancel a CLOB order.

  This requires a Polygon private key, either via `POLYMARKET_PRIVATE_KEY` or by
  passing `private_key: "0x..."`.

  Returns `{:ok, result}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Clob.cancel_order("0xabc123...", private_key: "0x...")
      # => {:ok, %{"status" => "cancelled"}}

  """
  def cancel_order(hash, opts \\ []) do
    with {:ok, private_key} <- private_key(opts),
         {:ok, poly_sig} <- auth_signature(private_key) do
      Client.delete("/order", params: %{orderHash: hash}, headers: [{"poly-signature", poly_sig}])
      |> resp()
    end
  end

  defp resp({:ok, body}), do: {:ok, body}
  defp resp({:error, _} = err), do: err

  defp nonce_address(opts) do
    cond do
      is_binary(opts[:address]) ->
        decode_address(opts[:address])

      true ->
        with {:ok, private_key} <- private_key(opts) do
          %{address_bin: address_bin} = address_from_private_key(private_key)
          {:ok, address_bin}
        end
    end
  end

  defp decode_address(address) when is_binary(address) do
    try do
      hex = address |> String.trim() |> String.trim_leading("0x") |> String.downcase()
      bin = Base.decode16!(hex, case: :lower)

      if byte_size(bin) == 20 do
        {:ok, bin}
      else
        {:error,
         %Error{
           service: :clob,
           kind: :invalid_request,
           message: "Invalid address length (expected 20 bytes)",
           reason: byte_size(bin)
         }}
      end
    rescue
      e ->
        {:error,
         %Error{
           service: :clob,
           kind: :invalid_request,
           message: "Invalid address",
           reason: e
         }}
    end
  end

  defp rpc_url(opts) do
    case opts[:rpc_url] || Application.get_env(:polymarket, :rpc_url) ||
           System.get_env("POLYGON_RPC_URL") do
      nil ->
        {:error,
         %Error{
           service: :clob,
           kind: :invalid_request,
           message: "RPC URL required (set :polymarket, :rpc_url or POLYGON_RPC_URL)"
         }}

      rpc_url when is_binary(rpc_url) ->
        {:ok, rpc_url}
    end
  end

  defp rpc_maker_nonce_call(rpc_url, address_bin) do
    data =
      "0x" <>
        Base.encode16(@maker_nonce_selector <> <<0::96, address_bin::binary>>, case: :lower)

    payload = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "eth_call",
      "params" => [
        %{"to" => @contract, "data" => data},
        "latest"
      ]
    }

    case Req.post(rpc_url, json: payload) do
      {:ok, %Req.Response{status: status, body: %{"result" => result}}} when status in 200..299 ->
        {:ok, result}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Error{
           service: :clob,
           kind: :http_error,
           status: status,
           body: body,
           message: "RPC HTTP #{status}"
         }}

      {:error, %Req.TransportError{} = e} ->
        {:error,
         %Error{
           service: :clob,
           kind: :transport_error,
           reason: e.reason,
           message: Exception.message(e)
         }}

      {:error, e} ->
        {:error,
         %Error{
           service: :clob,
           kind: :unexpected_error,
           reason: e,
           message: Exception.message(e)
         }}
    end
  end

  defp decode_nonce(result_hex) when is_binary(result_hex) do
    hex = result_hex |> String.trim() |> String.trim_leading("0x")

    case Integer.parse(hex, 16) do
      {nonce, ""} ->
        {:ok, nonce}

      _ ->
        {:error, %Error{service: :clob, kind: :unexpected_error, message: "Invalid nonce result"}}
    end
  end

  defp decode_nonce(_),
    do: {:error, %Error{service: :clob, kind: :unexpected_error, message: "Missing nonce result"}}

  defp private_key(opts) do
    case opts[:private_key] || Application.get_env(:polymarket, :private_key) ||
           System.get_env("POLYMARKET_PRIVATE_KEY") do
      nil ->
        {:error, %Error{service: :clob, kind: :invalid_request, message: "Private key required"}}

      priv_hex when is_binary(priv_hex) ->
        try do
          hex = priv_hex |> String.trim() |> String.trim_leading("0x") |> String.downcase()
          hex = if rem(byte_size(hex), 2) == 1, do: "0" <> hex, else: hex
          key = Base.decode16!(hex, case: :lower)

          if byte_size(key) != 32 do
            {:error,
             %Error{
               service: :clob,
               kind: :invalid_request,
               message: "Invalid private key length (expected 32 bytes)",
               reason: byte_size(key)
             }}
          else
            {:ok, key}
          end
        rescue
          e ->
            {:error,
             %Error{
               service: :clob,
               kind: :invalid_request,
               message: "Invalid private key",
               reason: e
             }}
        end
    end
  end

  defp build_order(params, private_key) when is_map(params) do
    %{address: address, address_bin: address_bin} = address_from_private_key(private_key)
    now = System.system_time(:second)

    order =
      params
      |> Map.put_new_lazy(:salt, fn ->
        :crypto.strong_rand_bytes(32) |> :binary.decode_unsigned()
      end)
      |> Map.put_new(:expiration, now + 365 * 24 * 3600)
      |> Map.put_new(:feeRateBps, "0")
      |> Map.put_new(:signatureType, "0")
      |> Map.put(:maker, address)
      |> Map.put(:signer, address)
      |> Map.put(:taker, @zero)
      |> Map.update(:side, "0", &normalize_side/1)

    required = ~w(tokenId makerAmount takerAmount nonce)a

    missing =
      required
      |> Enum.reject(&Map.has_key?(order, &1))

    if missing != [] do
      {:error,
       %Error{
         service: :clob,
         kind: :invalid_request,
         message:
           "Missing required fields: #{Enum.join(Enum.map(missing, &Atom.to_string/1), ", ")}"
       }}
    else
      order_value =
        Map.take(
          order,
          ~w(salt maker signer taker tokenId makerAmount takerAmount expiration nonce feeRateBps side signatureType)a
        )

      try do
        signature = sign_order(private_key, address_bin, order_value)
        {:ok, %{value: order_value, signature: signature}}
      rescue
        e ->
          {:error,
           %Error{
             service: :clob,
             kind: :signing_error,
             message: "Failed to sign order",
             reason: e
           }}
      end
    end
  end

  defp auth_signature(private_key) do
    %{address_bin: address_bin} = address_from_private_key(private_key)
    now = System.system_time(:second)

    value = %{
      "address" => address_bin,
      "timestamp" => Integer.to_string(now),
      "nonce" => 0,
      "message" => "This message attests that I control the given wallet"
    }

    try do
      domain_sep = auth_domain_separator()
      hash_struct = Typed.hash_struct("ClobAuth", value, @auth_types)
      digest = EIP712.Hash.keccak(<<0x19, 0x01, domain_sep::binary, hash_struct::binary>>)
      {:ok, sign_digest(private_key, digest)}
    rescue
      e ->
        {:error,
         %Error{
           service: :clob,
           kind: :signing_error,
           message: "Failed to sign auth message",
           reason: e
         }}
    end
  end

  defp normalize_side("buy"), do: "0"
  defp normalize_side("sell"), do: "1"
  defp normalize_side(:buy), do: "0"
  defp normalize_side(:sell), do: "1"
  defp normalize_side(0), do: "0"
  defp normalize_side(1), do: "1"
  defp normalize_side("0"), do: "0"
  defp normalize_side("1"), do: "1"
  defp normalize_side(other), do: other

  defp address_from_private_key(private_key) do
    key = Curvy.Key.from_privkey(private_key)
    pub = Curvy.Key.to_pubkey(key, compressed: false)
    address_bin = EIP712.Util.get_eth_address(pub)
    %{address: EIP712.Util.encode_hex(address_bin), address_bin: address_bin}
  end

  defp order_domain_separator do
    domain_value = %{
      "name" => @order_domain.name,
      "version" => @order_domain.version,
      "chainId" => @order_domain.chainId,
      "verifyingContract" => @contract_bin
    }

    Typed.hash_struct("EIP712Domain", domain_value, @order_domain_types)
  end

  defp auth_domain_separator do
    domain_value = %{
      "name" => @auth_domain.name,
      "version" => @auth_domain.version,
      "chainId" => @auth_domain.chainId
    }

    Typed.hash_struct("EIP712Domain", domain_value, @auth_domain_types)
  end

  defp sign_order(private_key, maker_address_bin, order_value) do
    value = %{
      "salt" => to_uint(order_value.salt),
      "maker" => maker_address_bin,
      "signer" => maker_address_bin,
      "taker" => @zero_bin,
      "tokenId" => to_uint(order_value.tokenId),
      "makerAmount" => to_uint(order_value.makerAmount),
      "takerAmount" => to_uint(order_value.takerAmount),
      "expiration" => to_uint(order_value.expiration),
      "nonce" => to_uint(order_value.nonce),
      "feeRateBps" => to_uint(order_value.feeRateBps),
      "side" => to_uint(order_value.side),
      "signatureType" => to_uint(order_value.signatureType)
    }

    domain_sep = order_domain_separator()
    hash_struct = Typed.hash_struct("Order", value, @order_types)
    digest = EIP712.Hash.keccak(<<0x19, 0x01, domain_sep::binary, hash_struct::binary>>)
    sign_digest(private_key, digest)
  end

  defp to_uint(value) when is_integer(value), do: value

  defp to_uint(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise ArgumentError, "expected numeric string, got: #{inspect(value)}"
    end
  end

  defp sign_digest(private_key, digest) do
    key = Curvy.Key.from_privkey(private_key)
    sig_bin = Curvy.sign(digest, key, hash: :keccak, compact: true)

    %Curvy.Signature{crv: :secp256k1, r: r, recid: recid, s: s} = Curvy.Signature.parse(sig_bin)

    v = 27 + recid

    sig =
      EIP712.Util.encode_bytes(r, 32) <>
        EIP712.Util.encode_bytes(s, 32) <>
        EIP712.Util.encode_bytes(v, 1)

    EIP712.Util.encode_hex(sig)
  end
end
