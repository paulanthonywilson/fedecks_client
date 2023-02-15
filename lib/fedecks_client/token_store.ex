defmodule FedecksClient.TokenStore do
  @moduledoc """
  Persistant store for the connection token. Implemented as a simple GenServer
  """
  use GenServer

  defstruct [:filename, :token]
  @type t :: %__MODULE__{filename: String.t(), token: String.t()}

  def start_link({_directory, name} = args) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def init({directory, name}) do
    file = Path.join(directory, to_string(name))

    token =
      case File.read(file) do
        {:ok, contents} -> :erlang.binary_to_term(contents, [:safe])
        _ -> nil
      end

    {:ok, %__MODULE__{filename: file, token: token}}
  end

  def set_token(server, token) do
    GenServer.cast(server, {:set_token, token})
  end

  def token(server) do
    GenServer.call(server, :get_token)
  end

  def handle_cast({:set_token, token}, %{filename: filename} = state) do
    File.write!(filename, :erlang.term_to_binary(token))
    {:noreply, %{state | token: token}}
  end

  def handle_call(:get_token, _from, %{token: token} = state) do
    {:reply, token, state}
  end
end
