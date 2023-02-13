defmodule FedecksClient.Connector do
  @moduledoc """
  Starts the connection to the server.
  """
  use GenServer

  use FedecksClient.WebsocketClient

  alias FedecksClient.TokenStore

  enforced_keys = [
    :connect_after,
    :handler,
    :token_store,
    :topic,
    :device_id,
    :connection_url
  ]

  @enforce_keys enforced_keys
  defstruct [:connection_status, :timer_ref | enforced_keys]

  @type connection_status :: :unregistered | :failed_registration | :connected | :connecting

  @type t :: %__MODULE__{
          connect_after: pos_integer(),
          handler: atom(),
          token_store: atom(),
          topic: atom(),
          connection_status: connection_status(),
          timer_ref: nil | reference()
        }

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def connection_status(server) do
    GenServer.call(server, :connection_status)
  end

  def authenticate(server, credentials) do
    GenServer.cast(server, {:authenticate, credentials})
  end

  @impl GenServer
  def init(opts) do
    connect_after = Keyword.fetch!(opts, :connect_after)

    state =
      %__MODULE__{
        connect_after: connect_after,
        handler: Keyword.fetch!(opts, :handler),
        token_store: Keyword.fetch!(opts, :token_store),
        topic: Keyword.fetch!(opts, :topic),
        connection_status: :starting,
        connection_url: Keyword.fetch!(opts, :connection_url),
        device_id: Keyword.fetch!(opts, :device_id)
      }
      |> maybe_schedule_connection_attempt()

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:connect, token}, state) do
    case attempt_connect(%{"fedecks-token" => token}, state) do
      {:ok, _pid} ->
        {:noreply, new_connection_status(state, :connected)}

      {:error, reason} ->
        failed_to_connect(reason, state)
        {:noreply, %{state | connection_status: :failing_to_connect}}
    end
  end

  @impl GenServer
  def handle_call(:connection_status, _, %{connection_status: connection_status} = state) do
    {:reply, connection_status, state}
  end

  @impl GenServer
  def handle_cast({:authenticate, credentials}, %{topic: topic, timer_ref: timer_ref} = state) do
    if timer_ref, do: Process.cancel_timer(timer_ref)
    state = %{state | timer_ref: nil}

    case attempt_connect(credentials, state) do
      {:ok, _pid} ->
        {:noreply, new_connection_status(state, :connected)}

      {:error, reason} ->
        SimplestPubSub.publish(topic, {topic, {:registration_failed, reason}})
        {:noreply, %{state | connection_status: :unregistered}}
    end
  end

  defp attempt_connect(
         authentication,
         %{
           connection_url: connection_url,
           device_id: device_id,
           handler: handler
         }
       ) do
    encoded_auth =
      authentication
      |> Enum.into(%{"fedecks-device-id" => device_id})
      |> :erlang.term_to_binary()
      |> Base.encode64()

    WebsocketClient.start_link(connection_url, handler,
      extra_headers: [{"x-fedecks-auth", encoded_auth}]
    )
  end

  defp failed_to_connect(reason, %{topic: topic} = status) do
    maybe_schedule_connection_attempt(status)
    SimplestPubSub.publish(topic, {topic, {:connection_failed, reason}})
  end

  defp maybe_schedule_connection_attempt(
         %{connect_after: connect_after, token_store: token_store} = state
       ) do
    case TokenStore.token(token_store) do
      nil ->
        new_connection_status(state, :unregistered)

      token ->
        timer_ref = Process.send_after(self(), {:connect, token}, connect_after)
        new_connection_status(%{state | timer_ref: timer_ref}, :connecting)
    end
  end

  defp new_connection_status(%{topic: topic} = state, new_connection_status) do
    SimplestPubSub.publish(topic, {topic, new_connection_status})
    %{state | connection_status: new_connection_status}
  end
end
