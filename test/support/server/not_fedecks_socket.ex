defmodule NonFedecksSocket do
  @moduledoc false
  _doc = """
  For sending non-fedecks messages to be ignored
  """

  alias Phoenix.Socket.Transport
  @behaviour Transport

  @impl Transport
  def child_spec(_) do
    %{
      id: :"#{__MODULE__}.#{}.Task",
      start: {Task, :start_link, [fn -> :ok end]},
      restart: :transient
    }
  end

  @impl Transport
  def init(%{device_id: device_id} = state) do
    SimplestPubSub.subscribe({:non_fedecks_message_to, device_id})
    {:ok, state}
  end

  @impl Transport
  def connect(%{connect_info: %{x_headers: [{"x-fedecks-auth", auth}]}}) do
    %{"fedecks-device-id" => device_id} =
      auth
      |> Base.decode64!()
      |> :erlang.binary_to_term([:safe])

    {:ok, %{device_id: device_id}}
  end

  @impl Transport
  def handle_in(_, state) do
    {:ok, state}
  end

  @impl Transport
  def handle_info(msg, state) do
    {:push, msg, state}
  end

  @impl Transport
  def terminate(_reason, _state) do
    :ok
  end
end
