defmodule FedecksClient.Websockets.MintWs do
  @moduledoc false
  _doc = """
  Holds a MintWs connection and associated  websocket and Fedecks inforrmation.

  Note the functional approach taken by `Mint` - each operation returns a copy of this struct,
  updated (probably) by the operation.

  Connections are `active`, ie downstream messsages and responses from the server will
  be received as messages to the connecting process. Use `handle_in/2` for processing
  those messages, which are of the form `{:tcp, socket :: port(), data :: String.t()}`.


  """

  alias FedecksClient.Websockets.WebsocketUrl

  required_keys = [:ws_url, :device_id]
  @enforce_keys required_keys
  defstruct [:websocket, :conn, :ref | required_keys]

  @type t :: %__MODULE__{
          ws_url: FedecksClient.Websockets.WebsocketUrl.t(),
          device_id: String.t(),
          websocket: nil | Mint.WebSocket.t(),
          conn: nil | Mint.HTTP.t(),
          ref: nil | reference()
        }

  @doc """
  Just creates the struct ready for connection, but not connected. URL validation
  takes place and requires the scheme to be "ws" or "wss"
  """
  def new(url, device_id) do
    with {:ok, ws_url} <- WebsocketUrl.new(url) do
      {:ok, %__MODULE__{ws_url: ws_url, device_id: device_id}}
    end
  end
end
