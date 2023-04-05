defmodule FedecksClient.FedecksSupervisor do
  @moduledoc """
  Supervises a connector and a token store
  """
  use Supervisor
  alias FedecksClient.TokenStore

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, {name, opts}, name: :"#{name}.Supervisor")
  end

  def init({name, args}) do
    token_directory = Keyword.fetch!(args, :token_dir)

    children = [
      {TokenStore, name: name, directory: token_directory},
      {FedecksClient.Connector, [{:token_store, TokenStore.server_name(name)} | args]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
