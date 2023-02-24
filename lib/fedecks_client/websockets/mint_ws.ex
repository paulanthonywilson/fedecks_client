defmodule FedecksClient.Websockets.MintWs do
  @moduledoc """
  Testing seam for interactions with `Mint`/``MintWebsocket`.

  Note the functional approach taken by `Mint` - each operation returns a copy of this struct,
  updated (probably) by the operation.

  Connections are `active`, ie downstream messsages and responses from the server will
  be received as messages to the connecting process. Use `handle_in/2` for processing
  those messages, which are of the form `{:tcp, socket :: port(), data :: String.t()}`.


  """

  required_keys = [:ws_url, :device_id]
  @enforce_keys required_keys
  defstruct [:websocket, :conn, :ref | required_keys]

  @type t :: %__MODULE__{
          ws_url: FedecksClient.Websockets.WebsocketUrl.t(),
          device_id: String.t(),
          conn: Mint.HTTP.t(),
          ref: reference()
        }

  @doc """
  Just creates the struct ready for connection, but not connected. URL validation
  takes place and requires the scheme to be "ws" or "wss"
  """
  @callback new(url :: String.t(), device_id :: String.t()) ::
              {:ok, %__MODULE__{}} | {:error, String.t()}

  @doc """
  Connect and initiates  a websocket connection.  Takes a credentials
  map.

  Note that the upgrade will not complete in this call, but will be
  received

  """
  @callback connect(mint_ws :: t(), credentials :: map()) ::
              {:ok, t()} | {:error, Mint.WebSocket.error()}

  @doc """
  Handle downstream responses / pushes from the websocket.

  Upgrades populate's the returned struct's websocket field
  """
  @callback handle_in(t(), message :: {:tcp, socket :: port(), data :: String.t()}) ::
              {:ok, t()}
              | {:upgrade_error, status_code :: integer()}
              | {:error, Mint.Types.error() | :unknown}

  @doc """
  Sends a structured message to the server (encoded as a binary term, which `FedecksServer` will
  turn back into a term). Be aware that on the other side only **safe** decoding will
  be done avoiding atoms is advisable.
  """
  @callback send(t(), message :: term()) :: {:ok, t()} | {:error, reason :: term()}

  @doc """
  Sends the raw binary to the server
  """
  @callback send_raw(t(), binary()) :: {:ok, t()} | {:error, reason :: term()}

  @doc """
  Request that a token be returned from server side
  """
  @callback request_token(t()) :: {:ok, t()} | {:error, reason :: term()}

  @doc """
  Close the connection
  """
  @callback close(t()) :: {:ok, t()}
end
