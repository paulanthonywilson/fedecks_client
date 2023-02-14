defmodule FedecksClient.RealWebsocketClient do
  @moduledoc """
  Calls the actual websocket client
  """

  @behaviour FedecksClient.WebsocketClient

  @impl FedecksClient.WebsocketClient
  defdelegate start_link(url, handler, handler_args, opts), to: :websocket_client
end
