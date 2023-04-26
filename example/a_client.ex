defmodule AClient do
  @moduledoc false
  use FedecksClient

  @impl FedecksClient
  def device_id, do: "device-123"

  @impl FedecksClient
  def connection_url do
    System.get_env("FEDECKS_SERVER", "ws://localhost:4000/fedecks/websocket")
  end
end
