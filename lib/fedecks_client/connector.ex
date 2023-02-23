defmodule FedecksClient.Connector do
  @moduledoc """
  Starts the connection to the server.
  """
  use GenServer

  use FedecksClient.WebsocketClient

  alias FedecksClient.TokenStore

  enforced_keys = [
    :connect_after,
    :token_store,
    :topic,
    :device_id,
    :connection_uri
  ]

  @enforce_keys enforced_keys
  defstruct [:connection_status, :timer_ref, :conn, :conn_ref, :websocket | enforced_keys]

  @type connection_status :: :unregistered | :failed_registration | :connected | :connecting

  @type t :: %__MODULE__{
          connect_after: pos_integer(),
          token_store: atom(),
          topic: atom(),
          connection_status: connection_status(),
          timer_ref: nil | reference(),
          conn: nil | Mint.HTTP1,
          conn_ref: reference()
        }

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def connection_status(server) do
    GenServer.call(server, :connection_status)
  end

  @spec authenticate(atom | pid | {atom, any} | {:via, atom, any}, any) :: :ok
  def authenticate(server, credentials) do
    GenServer.cast(server, {:authenticate, credentials})
  end

  @impl GenServer
  def init(opts) do
    connect_after = Keyword.fetch!(opts, :connect_after)

    uri =
      opts
      |> Keyword.fetch!(:connection_url)
      |> URI.parse()

    state =
      %__MODULE__{
        connect_after: connect_after,
        token_store: Keyword.fetch!(opts, :token_store),
        topic: Keyword.fetch!(opts, :topic),
        connection_status: :starting,
        connection_uri: uri,
        device_id: Keyword.fetch!(opts, :device_id)
      }
      |> maybe_schedule_connection_attempt()

    {:ok, state}
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
      {:ok, conn, ref} ->
        {:noreply, connected(state, conn, ref)}

      {:error, reason} ->
        SimplestPubSub.publish(topic, {topic, {:registration_failed, reason}})
        {:noreply, %{state | connection_status: :unregistered}}
    end
  end

  @impl GenServer
  def handle_info(
        {:tcp, _port, _data} = http_reply,
        %{websocket: nil, conn: conn, conn_ref: ref} = status
      ) do
    case Mint.WebSocket.stream(conn, http_reply) do
      {:ok, conn,
       [{:status, ^ref, 101 = status_code}, {:headers, ^ref, resp_headers}, {:done, ^ref}]} ->
        {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status_code, resp_headers)
        {:noreply, %{status | websocket: websocket, conn: conn}}

      {:ok, _conn, [{:status, ^ref, 403} | _]} ->
        broadcast(status, :registration_failed)
        {:noreply, %{conn: nil, conn_ref: nil}}
    end
  end

  defp attempt_connect(
         credentials,
         %{
           connection_uri: connection_uri,
           device_id: device_id
         }
       ) do
    encoded_auth =
      credentials
      |> Enum.into(%{"fedecks-device-id" => device_id})
      |> :erlang.term_to_binary()
      |> Base.encode64()

    # todo
    {:ok, conn} = Mint.HTTP.connect(:http, connection_uri.host, connection_uri.port)

    {:ok, conn, ref} =
      Mint.WebSocket.upgrade(:ws, conn, connection_uri.path, [{"x-fedecks-auth", encoded_auth}])

    {:ok, conn, ref}
  end

  defp connected(state, conn, ref) do
    %{state | conn: conn, conn_ref: ref} |> new_connection_status(:connected)
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

  defp broadcast(%{topic: topic}, message) do
    SimplestPubSub.publish(topic, {topic, message})
  end
end
