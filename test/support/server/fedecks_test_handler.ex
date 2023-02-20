defmodule FedecksTestHandler do
  @behaviour FedecksServer.FedecksHandler

  def otp_app, do: :fedecks_client

  def authenticate?(args) do
    broadcast(:authenticate?)

    case args do
      %{"username" => "bob", "password" => "bob's password"} -> true
      _ -> false
    end
  end

  def connection_established(device_id) do
    broadcast({:connection_established, device_id})
    :ok
  end

  defp broadcast(msg) do
    SimplestPubSub.publish(__MODULE__, {__MODULE__, msg})
  end
end
