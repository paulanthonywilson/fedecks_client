defmodule FedecksServerEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :fedecks_client

  import FedecksServer.Socket, only: [fedecks_socket: 1]

  fedecks_socket(FedecksTestHandler)

  socket("/notfedecks", NonFedecksSocket,
    websocket: [connect_info: [:x_headers]],
    longpoll: false
  )
end
