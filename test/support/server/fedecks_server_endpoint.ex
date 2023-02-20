defmodule FedecksServerEndpoint do
  use Phoenix.Endpoint, otp_app: :fedecks_client

  import FedecksServer.Socket, only: [fedecks_socket: 1]

  fedecks_socket(FedecksTestHandler)
end
