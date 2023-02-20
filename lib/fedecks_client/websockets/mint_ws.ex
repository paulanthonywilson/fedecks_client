defmodule FedecksClient.Websockets.MintWs do
  @moduledoc """
  Testing seam for interactions with `Mint`/``MintWebsocket`.

  Note the functional approach taken by `Mint` - each operation returns a copy of this struct,
  updated (probably) by the operation.

  Connections are `active`, ie downstream messsages and responses from the server will
  be received as messages to the connecting process. Use `handle_in/2` for processing
  those messages, which are of the form `{:tcp, socket :: port(), data :: String.t()}`.


  """

  alias FedecksClient.Websockets.WebsocketUrl

  defmacro __using__(_) do
    impl =
      if apply(Mix, :env, []) == :test and apply(Mix, :target, []) != :elixir_ls do
        MockMintWs
      else
        FedecksClient.Websockets.RealMintWs
      end

    quote do
      alias unquote(impl), as: MintWs
    end
  end

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
  def new(url, device_id) do
    with {:ok, ws_url} <- WebsocketUrl.new(url) do
      {:ok, %__MODULE__{ws_url: ws_url, device_id: device_id}}
    end
  end
end
