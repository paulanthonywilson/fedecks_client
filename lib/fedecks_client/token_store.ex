defmodule FedecksClient.TokenStore do
  @moduledoc """
  Persistant store for the connection token. Implemented as a simple GenServer
  """
  use GenServer

  keys = [:directory, :filename, :token]
  @enforce_keys keys
  defstruct keys
  @type t :: %__MODULE__{directory: String.t(), filename: String.t(), token: nil | String.t()}

  def server_name(base_name), do: :"#{base_name}.TokenStore"

  def start_link(opts) do
    base_name = Keyword.fetch!(opts, :name)
    name = server_name(base_name)
    directory = Keyword.fetch!(opts, :directory)
    GenServer.start_link(__MODULE__, {directory, name}, name: name)
  end

  @spec init(
          {binary
           | maybe_improper_list(
               binary | maybe_improper_list(any, binary | []) | char,
               binary | []
             ), any}
        ) :: {:ok, FedecksClient.TokenStore.t()}
  def init({directory, name}) do
    file = Path.join(directory, to_string(name))

    token =
      case File.read(file) do
        {:ok, contents} -> :erlang.binary_to_term(contents, [:safe])
        _ -> nil
      end

    {:ok, %__MODULE__{directory: directory, filename: file, token: token}}
  end

  def set_token(server, token) do
    GenServer.cast(server, {:set_token, token})
  end

  def token(server) do
    GenServer.call(server, :get_token)
  end

  def handle_cast({:set_token, token}, %{filename: filename, directory: directory} = state) do
    File.mkdir_p!(directory)
    File.write!(filename, :erlang.term_to_binary(token))
    {:noreply, %{state | token: token}}
  end

  def handle_call(:get_token, _from, %{token: token} = state) do
    {:reply, token, state}
  end
end
