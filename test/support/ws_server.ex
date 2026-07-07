defmodule Polymarket.Test.WSServer do
  @moduledoc """
  A local WebSocket server speaking a minimal version of the PolyNode
  protocol, used to test `Polymarket.Websocket` offline.

  Every client message is reported to the test process as
  `{:ws_server, tag, payload}`; the test process can drive the server-side
  connection by sending `{:push, map}` or `{:close, code}` to the connection
  pid it receives in `{:ws_server, :connected, pid}`.
  """

  def start(test_pid) do
    {:ok, server} =
      Bandit.start_link(
        plug: {__MODULE__.Plug, test_pid},
        port: 0,
        ip: :loopback,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {server, port}
  end

  defmodule Plug do
    @moduledoc false
    @behaviour Elixir.Plug

    @impl true
    def init(test_pid), do: test_pid

    @impl true
    def call(conn, test_pid) do
      WebSockAdapter.upgrade(
        conn,
        Polymarket.Test.WSServer.Handler,
        %{test_pid: test_pid, counter: 0},
        []
      )
    end
  end

  defmodule Handler do
    @moduledoc false
    @behaviour WebSock

    @impl true
    def init(state) do
      send(state.test_pid, {:ws_server, :connected, self()})
      {:ok, state}
    end

    @impl true
    def handle_in({text, opcode: :text}, state) do
      case Jason.decode!(text) do
        %{"action" => "subscribe"} = request ->
          send(state.test_pid, {:ws_server, :subscribe_request, request})

          snapshot = %{"type" => "snapshot", "count" => 0, "events" => []}

          confirmation = %{
            "type" => "subscribed",
            "subscriber_id" => "conn",
            "subscription_id" => "conn:#{state.counter}",
            "subscription_type" => request["type"],
            "warnings" => []
          }

          {:push, [{:text, Jason.encode!(snapshot)}, {:text, Jason.encode!(confirmation)}],
           %{state | counter: state.counter + 1}}

        %{"action" => "unsubscribe"} = request ->
          send(state.test_pid, {:ws_server, :unsubscribe_request, request})

          confirmation =
            case request do
              %{"subscription_id" => id} ->
                %{"type" => "unsubscribed", "subscriber_id" => "conn", "subscription_id" => id}

              _ ->
                %{"type" => "unsubscribed", "subscriber_id" => "conn"}
            end

          {:push, {:text, Jason.encode!(confirmation)}, state}

        %{"action" => "ping"} ->
          send(state.test_pid, {:ws_server, :ping_request, %{}})
          {:push, {:text, Jason.encode!(%{"type" => "pong"})}, state}

        other ->
          send(state.test_pid, {:ws_server, :unknown_request, other})
          {:ok, state}
      end
    end

    @impl true
    def handle_info({:push, map}, state), do: {:push, {:text, Jason.encode!(map)}, state}
    def handle_info({:close, code}, state), do: {:stop, :normal, {code, "closing"}, state}
    def handle_info(_message, state), do: {:ok, state}

    @impl true
    def terminate(_reason, _state), do: :ok
  end
end
