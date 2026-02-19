defmodule Polymarket.HTTP do
  @moduledoc false

  alias Polymarket.Error

  @type service :: Error.service()
  @type method :: :get | :post | :delete

  @spec request(service(), method(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def request(service, method, path, opts \\ []) when is_atom(service) and is_atom(method) do
    req = Req.new(req_options(service))

    request_opts =
      opts
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, path)

    case Req.request(req, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %Error{
           service: service,
           kind: :http_error,
           status: status,
           body: body,
           message: "HTTP #{status}"
         }}

      {:error, %Req.TransportError{} = e} ->
        {:error,
         %Error{
           service: service,
           kind: :transport_error,
           reason: e.reason,
           message: Exception.message(e)
         }}

      {:error, e} ->
        {:error,
         %Error{
           service: service,
           kind: :unexpected_error,
           reason: e,
           message: exception_message(e)
         }}
    end
  end

  @spec get(service(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def get(service, path, opts \\ []), do: request(service, :get, path, opts)

  @spec post(service(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def post(service, path, opts \\ []), do: request(service, :post, path, opts)

  @spec delete(service(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def delete(service, path, opts \\ []), do: request(service, :delete, path, opts)

  defp req_options(service) do
    base_url =
      case service do
        :gamma ->
          Application.get_env(:polymarket, :gamma_base_url, "https://gamma-api.polymarket.com")

        :data ->
          Application.get_env(:polymarket, :data_base_url, "https://data-api.polymarket.com")

        :clob ->
          Application.get_env(:polymarket, :clob_base_url, "https://clob.polymarket.com")
      end

    default_headers = [{"user-agent", "polymarket-elixir"}]

    global_opts = Application.get_env(:polymarket, :req_options, [])
    service_opts = Application.get_env(:polymarket, :"#{service}_req_options", [])

    Keyword.merge(
      [base_url: base_url, headers: default_headers],
      Keyword.merge(global_opts, service_opts)
    )
  end

  defp exception_message(%_{} = e), do: Exception.message(e)
  defp exception_message(e), do: inspect(e)
end
