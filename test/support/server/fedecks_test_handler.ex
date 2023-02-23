defmodule FedecksTestHandler do
  @moduledoc false
  alias FedecksServer.FedecksHandler
  @behaviour FedecksHandler

  @impl FedecksHandler
  def otp_app, do: :fedecks_client

  @impl FedecksHandler
  def authenticate?(args) do
    broadcast(:authenticate?)

    case args do
      %{"username" => "bob", "password" => "bob's password"} -> true
      _ -> false
    end
  end

  @impl FedecksHandler
  def connection_established(device_id) do
    broadcast({:connection_established, device_id})
    SimplestPubSub.subscribe({:message_to, device_id})
    :ok
  end

  @impl FedecksHandler
  def handle_info(_device_id, message) do
    {:push, message}
  end

  @impl FedecksHandler
  def handle_in(_device_id, message) do
    broadcast({:server_received, message})
    :ok
  end

  @impl FedecksHandler
  def handle_raw_in(_device_id, message) do
    broadcast({:server_received_raw, message})
    :ok
  end

  defp broadcast(msg) do
    SimplestPubSub.publish(__MODULE__, {__MODULE__, msg})
  end
end
