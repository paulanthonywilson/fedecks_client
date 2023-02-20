defmodule FedecksClient.Connector do
  @moduledoc """
  Manages connecting, and reconnecting, to a server over websockets
  """
  use FedecksClient.Websockets.MintWs

  alias FedecksClient.TokenStore

  use GenServer

  @type connection_status :: :unregistered | :failed_registration | :connected | :connecting

  keys = [:broadcast_topic, :mint_ws, :connect_delay]
  @enforce_keys keys

  defstruct [:connection_status | keys]

  @type t :: %__MODULE__{
          broadcast_topic: atom(),
          connection_status: connection_status(),
          mint_ws: FedecksClient.Websockets.MintWs.t(),
          connect_delay: non_neg_integer()
        }

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args) do
    name = Keyword.fetch!(args, :connector_name)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def connection_status(server) do
    GenServer.call(server, :connection_status)
  end

  @impl GenServer
  def init(args) do
    url = Keyword.fetch!(args, :connection_url)
    device_id = Keyword.fetch!(args, :device_id)
    token_store = Keyword.fetch!(args, :token_store)

    case MintWs.new(url, device_id) do
      {:ok, mint_ws} ->
        IO.inspect(mint_ws)

        state = %__MODULE__{
          broadcast_topic: Keyword.fetch!(args, :name),
          mint_ws: nil,
          connect_delay: nil
        }

        state =
          case TokenStore.token(token_store) do
            nil ->
              new_connection_status(state, :unregistered)

            token ->
              IO.inspect(MintWs)
              MintWs.connect(mint_ws, %{"fedecks-token" => token})
              new_connection_status(state, :connecting)
          end

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:connection_status, _from, %{connection_status: connection_status} = state) do
    {:reply, connection_status, state}
  end

  defp broadcast(%{broadcast_topic: topic}, message) do
    SimplestPubSub.publish(topic, {topic, message})
  end

  # defp new_connection_status(%{connection_status: connection_status} = state, connection_status) do
  #   state
  # end

  defp new_connection_status(state, connection_status) do
    broadcast(state, connection_status)
    %{state | connection_status: connection_status}
  end
end
