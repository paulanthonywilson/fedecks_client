defmodule FedecksClient.Websockets.MintWsConnection do
  @moduledoc """
  Testing seam for interactions with `Mint`/``MintWebsocket`.

  Note the functional approach taken by `Mint` - each operation returns a copy of this struct,
  updated (probably) by the operation.

  Connections are `active`, ie downstream messsages and responses from the server will
  be received as messages to the connecting process. Use `handle_in/2` for processing
  those messages, which are of the form `{:tcp, socket :: port(), data :: String.t()}`.
  """

  alias FedecksClient.CompileEnv
  alias FedecksClient.Websockets.MintWs

  defmacro __using__(_) do
    impl =
      if CompileEnv.test?(),
        do: MockMintWsConnection,
        else: FedecksClient.Websockets.RealMintWsConnection

    quote do
      alias unquote(impl), as: MintWsConnection
    end
  end

  @doc """
  Connect and initiates  a websocket connection.  Takes a credentials
  map.

  Note that the upgrade will not complete in this call, but will be
  received

  """
  @callback connect(mint_ws :: MintWs.t(), credentials :: map()) ::
              {:ok, MintWs.t()} | {:error, Mint.WebSocket.error()}

  @doc """
  Handle downstream responses / pushes from the websocket.

  Upgrades populate's the returned struct's websocket field
  """
  @callback handle_in(MintWs.t(), message :: {:tcp, socket :: port(), data :: binary()}) ::
              {:messages, MintWs.t(), list(term())}
              | {:upgraded, MintWs.t()}
              | {:upgrade_error, status_code :: integer()}
              | {:error, Mint.Types.error() | :unknown}

  @doc """
  Sends a structured message to the server (encoded as a binary term, which `FedecksServer` will
  turn back into a term). Be aware that on the other side only **safe** decoding will
  be done avoiding atoms is advisable.
  """
  @callback send(MintWs.t(), message :: term()) :: {:ok, MintWs.t()} | {:error, reason :: term()}

  @doc """
  Sends the raw binary to the server
  """
  @callback send_raw(MintWs.t(), binary()) :: {:ok, MintWs.t()} | {:error, reason :: term()}

  @doc """
  Request that a token be returned from server side
  """
  @callback request_token(MintWs.t()) :: {:ok, MintWs.t()} | {:error, reason :: term()}

  @doc """
  Close the connection
  """
  @callback close(MintWs.t()) :: {:ok, MintWs.t()}
end
