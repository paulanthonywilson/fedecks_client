defmodule FedecksClient.DeadMansHandle do
  @moduledoc false
  _doc = """
  Listens for pong responses from the connection. Dies if it does not receive a
  response, after a ping, in timeout time.

  This will go ahead of the connectior in supervision order, taking it down with it.
  """

  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: server_name(name))
  end

  @impl GenServer
  def init(opts) do
    timeout = Keyword.fetch!(opts, :pong_timeout)

    opts
    |> Keyword.fetch!(:name)
    |> server_name()
    |> SimplestPubSub.subscribe()

    {:ok, %{timeout: timeout}}
  end

  @impl GenServer
  def handle_info(:ping, %{timeout: timeout} = state) do
    {:noreply, state, timeout}
  end

  def handle_info(:pong, state) do
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  @spec server_name(String.t()) :: atom
  def server_name(base_name), do: :"#{base_name}.DeadMansHandle"
end
