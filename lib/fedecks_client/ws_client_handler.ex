# credo:disable-for-this-file
defmodule FedecksClient.WsClientHandler do
  @moduledoc """
  For testing with the server for now
  """
  @behaviour :websocket_client_handler

  def init(a, b) do
    IO.inspect({a, b}, label: :ws_init)
    {:ok, %{}}
  end

  def websocket_handle(msg, _req, state) do
    IO.inspect(msg, label: :ws_websocket_handle)
    {:ok, state}
  end

  def websocket_info(msg, _req, state) do
    IO.inspect(msg, label: :ws_websocket_info)
    {:ok, state}
  end

  def websocket_terminate(_, _connection_state, _state) do
    IO.inspect(:terminaed, label: :ws_websocket_terminate)
    :ok
  end
end
