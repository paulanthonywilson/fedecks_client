defmodule FedecksClient.Connector do
  @moduledoc false
  _doc = """
  Manages connecting, and reconnecting, to a server over websockets
  """

  use FedecksClient.Websockets.MintWsConnection

  alias FedecksClient.{TokenStore, Websockets.MintWs}

  use GenServer

  @type connection_status :: FedecksClient.connection_status()

  keys = [:broadcast_topic, :mint_ws, :connect_delay, :token_store, :ping_frequency]
  @enforce_keys keys

  defstruct [:connection_status, :connection_schedule_ref | keys]

  @type t :: %__MODULE__{
          connection_status: connection_status(),
          broadcast_topic: atom(),
          mint_ws: FedecksClient.Websockets.MintWs.t(),
          connect_delay: pos_integer(),
          token_store: atom(),
          ping_frequency: pos_integer(),
          connection_schedule_ref: reference()
        }

  def server_name(base_name), do: :"#{base_name}.Connector"

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args) do
    base_name = Keyword.fetch!(args, :name)
    GenServer.start_link(__MODULE__, args, name: server_name(base_name))
  end

  @doc """
  The current connection status
  """
  @spec connection_status(GenServer.server()) :: connection_status()
  def connection_status(server) do
    GenServer.call(server, :connection_status)
  end

  @doc """
  Send a message as any Erlang term to the server
  """
  @spec send_message(GenServer.server(), term()) :: :ok
  def send_message(server, message) do
    GenServer.cast(server, {:send_message, message})
  end

  @doc """
  Send an unencoded binary messagaas any to the server
  """
  @spec send_raw_message(GenServer.server(), binary()) :: :ok
  def send_raw_message(server, message) do
    GenServer.cast(server, {:send_raw_message, message})
  end

  @doc """
  Attempt to login with the credentials
  """
  @spec login(GenServer.server(), credentials :: term()) :: :ok
  def login(server, credentials) do
    GenServer.cast(server, {:login, credentials})
  end

  @impl GenServer
  def init(args) do
    url = Keyword.fetch!(args, :connection_url)
    device_id = Keyword.fetch!(args, :device_id)
    token_store = Keyword.fetch!(args, :token_store)
    connect_delay = Keyword.fetch!(args, :connect_delay)
    ping_frequency = Keyword.fetch!(args, :ping_frequency)

    case MintWs.new(url, device_id) do
      {:ok, mint_ws} ->
        state = %__MODULE__{
          token_store: token_store,
          broadcast_topic: Keyword.fetch!(args, :name),
          mint_ws: mint_ws,
          connect_delay: connect_delay,
          ping_frequency: ping_frequency
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
  def handle_cast(
        {:send_message, message},
        %{mint_ws: mint_ws, connection_status: :connected} = state
      ) do
    mint_ws
    |> MintWsConnection.send(message)
    |> handle_message_send_result(state)
  end

  def handle_cast(
        {:send_raw_message, message},
        %{mint_ws: mint_ws, connection_status: :connected} = state
      ) do
    mint_ws
    |> MintWsConnection.send_raw(message)
    |> handle_message_send_result(state)
  end

  def handle_cast({message_id, _}, state) when message_id in [:send_message, :send_raw_message] do
    {:noreply, state}
  end

  def handle_cast(
        {:login, credentials},
        %{token_store: token_store, connection_schedule_ref: connection_schedule_ref} = state
      ) do
    if connection_schedule_ref, do: Process.cancel_timer(connection_schedule_ref)
    TokenStore.set_token(token_store, nil)

    case attempt_connection(credentials, state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, state} ->
        {:noreply, new_connection_status(state, :unregistered)}
    end
  end

  defp handle_message_send_result({:ok, mint_ws}, state) do
    {:noreply, update_mint_ws(state, mint_ws)}
  end

  defp handle_message_send_result({:error, reason}, %{mint_ws: mint_ws} = state) do
    broadcast(state, {:connection_error, reason})
    {:ok, mint_ws} = MintWsConnection.close(mint_ws)
    {:noreply, update_mint_ws(state, mint_ws)}
  end

  @impl GenServer
  def handle_call(:connection_status, _from, %{connection_status: connection_status} = state) do
    {:reply, connection_status, state}
  end

  # Handling scheduling messages
  @impl GenServer
  def handle_info({:attempt_connection, credentials}, state) do
    case attempt_connection(credentials, state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, state} ->
        {:noreply, schedule_connection(state, credentials)}
    end
  end

  def handle_info(:request_a_new_token, %{mint_ws: mint_ws} = state) do
    {:ok, mint_ws} = MintWsConnection.request_token(mint_ws)
    {:noreply, update_mint_ws(state, mint_ws)}
  end

  def handle_info(:ping, %{mint_ws: mint_ws} = state) do
    {:ok, mint_ws} = MintWsConnection.ping(mint_ws)

    state =
      state
      |> update_mint_ws(mint_ws)
      |> schedule_ping()

    {:noreply, state}
  end

  # Handling connection messages
  def handle_info({protocol, _socket, _data} = incoming, %{mint_ws: mint_ws} = state)
      when protocol in [:tcp, :ssl] do
    case MintWsConnection.handle_in(mint_ws, incoming) do
      {:upgraded, mint_ws} ->
        send(self(), :request_a_new_token)

        state
        |> schedule_ping()
        |> update_mint_ws(mint_ws)
        |> new_connection_status(:connected)
        |> no_reply()

      {:messages, mint_ws, messages} ->
        state
        |> handle_messages(messages)
        |> update_mint_ws(mint_ws)
        |> no_reply()

      {err, reason} when err in [:error, :upgrade_error] ->
        broadcast(state, {:upgrade_failed, reason})
        {:ok, mint_ws} = MintWsConnection.close(mint_ws)

        state =
          state
          |> update_mint_ws(mint_ws)

        {:stop, :normal, state}
    end
  end

  def handle_info({closed, _socket}, state) when closed in [:tcp_closed, :ssl_closed] do
    broadcast(state, :connection_lost)
    # Socket's closed so let's just "let it die" and let the supervisor deal with
    # reconnection logic.
    {:stop, :normal, state}
  end

  defp no_reply(state), do: {:noreply, state}

  defp attempt_connection(credentials, %{mint_ws: mint_ws} = state) do
    state = new_connection_status(state, :connecting)

    case MintWsConnection.connect(mint_ws, credentials) do
      {:ok, mintws} ->
        state = update_mint_ws(state, mintws)
        {:ok, state}

      {:error, reason} ->
        broadcast(state, {:connection_failed, reason})
        {:error, state}
    end
  end

  defp handle_messages(state, messages) do
    Enum.each(messages, &handle_one_message(state, &1))
    state
  end

  defp handle_one_message(%{token_store: token_store}, {:fedecks_token, token}) do
    TokenStore.set_token(token_store, token)
  end

  defp handle_one_message(state, message) do
    broadcast(state, {:message, message})
  end

  defp schedule_ping(%{ping_frequency: ping_frequency} = state) do
    Process.send_after(self(), :ping, ping_frequency)
    state
  end

  defp schedule_connection(%{connect_delay: connect_delay} = state, credentials) do
    ref = Process.send_after(self(), {:attempt_connection, credentials}, connect_delay)
    new_connection_status(%{state | connection_schedule_ref: ref}, :connection_scheduled)
  end

  defp broadcast(%{broadcast_topic: topic}, message) do
    SimplestPubSub.publish(topic, {topic, message})
  end

  defp new_connection_status(state, connection_status) do
    broadcast(state, connection_status)
    %{state | connection_status: connection_status}
  end

  defp update_mint_ws(%__MODULE__{} = state, mint_ws) do
    %{state | mint_ws: mint_ws}
  end
end
