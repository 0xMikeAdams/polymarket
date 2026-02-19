defmodule Polymarket.Gamma do
  @moduledoc """
  Wrapper for the Polymarket Gamma API (read-only markets/events metadata).
  """

  alias Polymarket.Gamma.Client

  @doc """
  List markets.

  Returns `{:ok, markets}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Gamma.list_markets(limit: 10)
      # => {:ok, [%{"id" => "...", "question" => "...", ...}, ...]}

  """
  def list_markets(opts \\ []) do
    params = if Keyword.keyword?(opts), do: Enum.into(opts, %{}), else: opts
    Client.get("/markets", params: params) |> process_response()
  end

  @doc """
  Get a market by slug.

  Returns `{:ok, market}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Gamma.get_market("will-trump-win-the-2024-us-presidential-election")
      # => {:ok, %{"id" => "...", "question" => "...", ...}}

  """
  def get_market(slug), do: Client.get("/markets/slug/#{slug}") |> process_response()

  @doc """
  List events.

  Returns `{:ok, events}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Gamma.list_events(limit: 10)
      # => {:ok, [%{"id" => "...", "title" => "...", ...}, ...]}

  """
  def list_events(opts \\ []) do
    params = if Keyword.keyword?(opts), do: Enum.into(opts, %{}), else: opts
    Client.get("/events", params: params) |> process_response()
  end

  @doc """
  Get an event by slug.

  Returns `{:ok, event}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Gamma.get_event("us-presidential-election-2024")
      # => {:ok, %{"id" => "...", "title" => "...", ...}}

  """
  def get_event(slug), do: Client.get("/events/slug/#{slug}") |> process_response()

  @doc """
  List tags.

  Returns `{:ok, tags}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Gamma.list_tags()
      # => {:ok, [%{"id" => "...", "name" => "...", ...}, ...]}

  """
  def list_tags, do: Client.get("/tags") |> process_response()

  @doc """
  List sports.

  Returns `{:ok, sports}` on success or `{:error, %Polymarket.Error{}}` on failure.

  ## Examples

      Polymarket.Gamma.list_sports()
      # => {:ok, [%{"id" => "...", "name" => "...", ...}, ...]}

  """
  def list_sports, do: Client.get("/sports") |> process_response()

  defp process_response({:ok, body}), do: {:ok, post_process(body)}
  defp process_response({:error, _} = err), do: err

  defp post_process(data) when is_list(data), do: Enum.map(data, &post_process/1)

  defp post_process(map) when is_map(map) do
    map =
      case fetch_key(map, :markets) do
        {:ok, markets} when is_list(markets) -> put_key(map, :markets, post_process(markets))
        _ -> map
      end

    map
    |> decode(:outcomes)
    |> decode(:outcomePrices)
    |> decode(:clobTokenIds)
    |> decode(:umaResolutionStatuses)
  end

  defp post_process(other), do: other

  defp decode(map, key) do
    case fetch_key(map, key) do
      :error ->
        map

      {:ok, str} when is_binary(str) ->
        case Jason.decode(str) do
          {:ok, decoded} -> put_key(map, key, decoded)
          _ -> map
        end

      _ ->
        map
    end
  end

  defp fetch_key(map, key) when is_atom(key) do
    cond do
      Map.has_key?(map, key) -> {:ok, Map.get(map, key)}
      Map.has_key?(map, Atom.to_string(key)) -> {:ok, Map.get(map, Atom.to_string(key))}
      true -> :error
    end
  end

  defp put_key(map, key, value) when is_atom(key) do
    cond do
      Map.has_key?(map, key) -> Map.put(map, key, value)
      Map.has_key?(map, Atom.to_string(key)) -> Map.put(map, Atom.to_string(key), value)
      true -> Map.put(map, Atom.to_string(key), value)
    end
  end
end
