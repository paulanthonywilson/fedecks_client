defmodule AClient do
  use FedecksClient

  def device_id, do: "device-123"

  def connection_url, do: "ws://localhost:4000/fedecks/websocket"

end
