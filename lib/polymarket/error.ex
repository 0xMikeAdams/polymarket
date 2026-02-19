defmodule Polymarket.Error do
  @moduledoc """
  Error struct returned by this library.

  The goal is to provide a consistent shape for API and transport errors across
  all Polymarket services (Gamma, Data, CLOB).

  ## Examples

      iex> error = %Polymarket.Error{service: :gamma, kind: :http_error, message: "Not found", status: 404}
      iex> error.service
      :gamma
      iex> error.kind
      :http_error

  """

  @enforce_keys [:service, :kind]
  defstruct [:service, :kind, :message, :status, :body, :reason]

  @type service :: :gamma | :data | :clob
  @type kind ::
          :http_error | :transport_error | :invalid_request | :signing_error | :unexpected_error

  @type t :: %__MODULE__{
          service: service(),
          kind: kind(),
          message: String.t() | nil,
          status: non_neg_integer() | nil,
          body: term(),
          reason: term()
        }
end
