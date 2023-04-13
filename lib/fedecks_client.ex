defmodule FedecksClient do
  @moduledoc """
  Establishes a websocket connection to the server.

  Eg :

  ```
  defmodule MyApp.MyClient do
    use FedecksClient
      def device_id do
        {:ok, name} = :inet.hostname()
        to_string(name)
      end

      def connection_url do
        Application.fetch_env!(:my_app, :fedecks_server_path)
      end
  end
  ```

  Include in your supervision tree.

  eg
  ```
  defmodule MyApp.Application do
    children = [
      MyApp.MyClient
    ]
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```

  Initial authentication to the server with `c:FedecksClient.login/1`. Subsequent
  connections will authenticate with a token provided by the server, persisting between reboots,
  until the token expires or otherwise becomes invalid.

  """

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      @connector FedecksClient.Connector.server_name(__MODULE__)
      def start_link(_) do
        maybe_val = fn fun, default ->
          if function_exported?(__MODULE__, fun, 0) do
            apply(__MODULE__, fun, [])
          else
            default
          end
        end

        FedecksClient.FedecksSupervisor.start_link(
          name: __MODULE__,
          token_dir: maybe_val.(:token_dir, unquote(__MODULE__).default_token_dir()),
          connection_url: connection_url(),
          device_id: device_id(),
          connect_delay: maybe_val.(:connect_delay, unquote(__MODULE__).default_connect_delay()),
          ping_frequency:
            maybe_val.(:ping_frequency, unquote(__MODULE__).default_ping_frequency())
        )
      end

      @impl unquote(__MODULE__)
      def login(credentials) do
        FedecksClient.Connector.login(@connector, credentials)
      end

      @impl unquote(__MODULE__)
      def subscribe do
        SimplestPubSub.subscribe(__MODULE__)
      end

      @impl unquote(__MODULE__)
      def send(message) do
        FedecksClient.Connector.send_message(@connector, message)
      end

      @impl unquote(__MODULE__)
      def send_raw(message) do
        FedecksClient.Connector.send_raw_message(@connector, message)
      end

      @impl unquote(__MODULE__)
      def connection_status do
        FedecksClient.Connector.connection_status(@connector)
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end
    end
  end

  @doc """
  Server websocket URL. Must start with "ws://" or "wss://".

  Remeber to append "/websocket" if using a Phoenix (ie Fedecks) websocket.
  """
  @callback connection_url :: String.t()

  @doc """
  Device id to identify this device when communicating with the server
  """
  @callback device_id :: String.t()

  @doc """
  Initiate a login to the server.

  Implementation provided by the `__using__` macro
  """
  @callback login(credentials :: term()) :: :ok

  @doc """
  Subscribe to Fedecks events. Messages are sent in the form `{ModuleName, message}`.
  See module doc for messages


  Implementation provided by the `__using__` macro
  """
  @callback subscribe :: :ok

  @doc """
  Send an encoded message to the server. Note that the server will use safe decoding so it is best to avoid
  atoms.


  Implementation provided by the `__using__` macro
  """
  @callback send(message :: term()) :: :ok

  @doc """
  Send an raw binary message to the server.


  Implementation provided by the `__using__` macro
  """
  @callback send_raw(message :: term()) :: :ok

  @doc """
  Send an raw binary message to the server.


  Implementation provided by the `__using__` macro
  """
  @callback connection_status :: FedecksClient.Connector.connection_status()

  @doc """
  Directory to store the Fedecks Token. Optional and defaults to `FedecksClient.default_token_dir/0`
  """
  @callback token_dir :: String.t()

  @doc """
  How long to wait before and between connection attempts. Bear in mind that it my take some time
  for a network connection to be established if using Nerves Networking and WiFi

  Optional and defaults to 10 seconds
  """
  @callback connect_delay :: pos_integer()

  @doc """
  How often to ping the server to maintain the connection. Bear in mind that the server will drop the connection
  after 1 minute of inactivity.

  Optional and defaults to 19 seconds
  """
  @callback ping_frequency :: pos_integer()

  @optional_callbacks [token_dir: 0, connect_delay: 0, ping_frequency: 0]

  @default_connect_delay :timer.seconds(10)
  @default_ping_frequency :timer.seconds(19)

  @mix_env Mix.env()
  @mix_target Mix.target()

  @dev_token_dir "#{System.tmp_dir!()}/#{__MODULE__}"

  @doc """
  The default directory for Fedecks tokens. Value is depenendend on the mix environment and target and
  assumes you are using this for Nerves.
  * If the env is `:test` or target is `:host` then it is the module name under the system temp directory.
  * Otherwise "/root/fedecks"
  """
  @spec default_token_dir() :: String.t()
  def default_token_dir(mix_env \\ @mix_env, mix_target \\ @mix_target)
  def default_token_dir(:test, _), do: @dev_token_dir
  def default_token_dir(_, :host), do: @dev_token_dir
  def default_token_dir(_, _), do: "/root/fedecks"

  def default_connect_delay, do: @default_connect_delay
  def default_ping_frequency, do: @default_ping_frequency
end
