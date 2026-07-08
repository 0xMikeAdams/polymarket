defmodule Polymarket.Test.ClobWSServer do
  @moduledoc """
  A local WebSocket server speaking a minimal version of the official CLOB
  WebSocket protocol, used to test `Polymarket.Websocket.Clob` offline.

  Client messages are reported to the test process as
  `{:clob_server, tag, payload}` (including the request path on connect);
  the test process can push frames with `{:push, map_or_list}` or force a
  close with `{:close, code}` via the connection pid.
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
        Polymarket.Test.ClobWSServer.Handler,
        %{test_pid: test_pid, path: conn.request_path},
        []
      )
    end
  end

  defmodule Handler do
    @moduledoc false
    @behaviour WebSock

    @impl true
    def init(state) do
      send(state.test_pid, {:clob_server, :connected, {self(), state.path}})
      {:ok, state}
    end

    @impl true
    def handle_in({"PING", opcode: :text}, state) do
      send(state.test_pid, {:clob_server, :ping, %{}})
      {:push, {:text, "PONG"}, state}
    end

    def handle_in({text, opcode: :text}, state) do
      send(state.test_pid, {:clob_server, :message, Jason.decode!(text)})
      {:ok, state}
    end

    @impl true
    def handle_info({:push, data}, state), do: {:push, {:text, Jason.encode!(data)}, state}
    def handle_info({:close, code}, state), do: {:stop, :normal, {code, "closing"}, state}
    def handle_info(_message, state), do: {:ok, state}

    @impl true
    def terminate(_reason, _state), do: :ok
  end
end
