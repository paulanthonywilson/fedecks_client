defmodule FedecksClient.Connector do
  @moduledoc """
  Manages connecting, and reconnecting, to a server over websockets
  """
  use FedecksClient.Websockets.MintWsConnection

  alias FedecksClient.{TokenStore, Websockets.MintWs}

  use GenServer

  @type connection_status ::
          :unregistered | :connecting | :connection_scheduled | :failed_registration | :connected

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
    connect_delay = Keyword.fetch!(args, :connect_delay)

    case MintWs.new(url, device_id) do
      {:ok, mint_ws} ->
        state = %__MODULE__{
          broadcast_topic: Keyword.fetch!(args, :name),
          mint_ws: mint_ws,
          connect_delay: connect_delay
        }

        state =
          case TokenStore.token(token_store) do
            nil ->
              new_connection_status(state, :unregistered)

            token ->
              schedule_connection(state, %{"fedecks-token" => token})
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

  @impl GenServer
  def handle_info({:attempt_connection, credentials}, %{mint_ws: mint_ws} = state) do
    state = new_connection_status(state, :connecting)

    state =
      case MintWsConnection.connect(mint_ws, credentials) do
        {:ok, mintws} ->
          update_mint_ws(state, mintws)

        {:error, reason} ->
          broadcast(state, {:connection_failed, reason})
          schedule_connection(state, credentials)
      end

    {:noreply, state}
  end

  def handle_info({:tcp, _socket, _data} = incomong, %{mint_ws: mint_ws} = state) do
    state =
      case MockMintWsConnection.handle_in(mint_ws, incomong) do
        {:upgraded, mint_ws} ->
          state
          |> update_mint_ws(mint_ws)
          |> new_connection_status(:connected)
      end

    {:noreply, state}
  end

  defp schedule_connection(%{connect_delay: connect_delay} = state, credentials) do
    Process.send_after(self(), {:attempt_connection, credentials}, connect_delay)
    new_connection_status(state, :connection_scheduled)
  end

  defp broadcast(%{broadcast_topic: topic}, message) do
    SimplestPubSub.publish(topic, {topic, message})
  end

  # todo - test which forces this uncommenting (?)
  # defp new_connection_status(%{connection_status: connection_status} = state, connection_status) do
  #   state
  # end

  defp new_connection_status(state, connection_status) do
    broadcast(state, connection_status)
    %{state | connection_status: connection_status}
  end

  defp update_mint_ws(%__MODULE__{} = state, %MintWs{} = mint_ws) do
    %{state | mint_ws: mint_ws}
  end
end
