defmodule FedecksClient.FedecksSupervisor do
  @moduledoc false
  _doc = """
  Supervises a connector and a token store
  """

  use Supervisor
  alias FedecksClient.TokenStore
  @pong_timeout :timer.seconds(30)

  def supervisor_name(base_name), do: :"#{base_name}.Supervisor"

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, {name, opts}, name: supervisor_name(name))
  end

  def init({name, args}) do
    token_directory = Keyword.fetch!(args, :token_dir)

    ping_frequency = Keyword.fetch!(args, :ping_frequency)

    children = [
      {TokenStore, name: name, directory: token_directory},
      {FedecksClient.DeadMansHandle, name: name, pong_timeout: ping_frequency},
      {FedecksClient.Connector, [{:token_store, TokenStore.server_name(name)} | args]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
