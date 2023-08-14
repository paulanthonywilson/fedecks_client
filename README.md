# FedecksClient

This is the client side of Fedecks for device to Phoenix communication over binary websockets. _Fedecks Client_ communicates with Phoenix application using [Fedecks Server](https://hexdocs.pm/fedecks_server/readme.html).

It is written with [Nerves Projects](https://hexdocs.pm/nerves/getting-started.html) in mind. Connecting your Nerves boxes to a server in the cloud with Websockets gives you efficient two way communication from off your personal projects. 


## Installation

Install from Hex.

```elixir
def deps do
  [ {:fedecks_client, "~> 0.1"} ]
end
```

## Using

### First Create a client

eg
```
defmodule MyApp.MyClient do
  use FedecksClient

  @impl FedecksClient
  def device_id do
    {:ok, name} = :inet.hostname()
    to_string(name)
  end

  @impl FedecksClient
  def connection_url do
    Application.fetch_env!(:my_app, :fedecks_server_path)
  end
end
```

Only the `c:FedecksClient.device_id/0` and `c:FedecksClient.connection_url/0` callbacks are required to identify your device to the server, and to locate the Websocket path to the server. The url needs to be in String form and lead with the _wss_ a or _ws_ protocol.

You can implement Other optional callbacks to further configure the client: `c:FedecksClient.token_dir/0`, `c:FedecksClient.connect_delay/0`, `c:FedecksClient.ping_frequency/0`.

### Step 3 Add to your supervision tree

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

### Step 4 - Authenticate

Your Nerves installation will need to authenticate with Fedecks Server at least once. You can do this with the provided implenentation `c:FedecksClient.login/1`. The nature of the credentials is not fixed by Fedecks but is defined by the [handler implemented on the Fedecks Server](https://hexdocs.pm/fedecks_server/FedecksServer.FedecksHandler.html#c:authenticate?/1).

Authentication serving suggestion:

```
def login(username, password) do
  MyApp.MyClient.login(%{"username" => username, "password" => password})
end
```

How you get the authentication credentials to your installation is up to you. I typically run a Phoenix server in my Nerves projects for local access and this kind of configuration. Subsequent reconnections will happen automatically, even between reboots and firmware upgrades. 

Note that your credentials are not stored locally. _Fedecks Server_ provides and refreshed a signed authentication token to the client which _is_ stored in the filesystem and held in memory. The default token expiry is currently 4 weeks, which is arguably too long. It is [configurable on the server side, though](https://hexdocs.pm/fedecks_server/FedecksServer.FedecksHandler.html).


### Use it.


Send messages up the connection with `c:FedecksClient.send/1` and `c:FedecksClient.send_raw/1`. Subscribe your process to messages received from the server with `c:FedecksClient.subscribe/0`. See `c:FedecksClient.subscribe/0` for a list of messages you can expect.


## Behind the curtain

_Fedecks Client_ uses [Mint Websocket](https://hexdocs.pm/mint_web_socket/Mint.WebSocket.html) to connect to the server.

Non-raw messages are sent in either direction as Binary Erlang Terms. You could send any message, however decoding is done with the `safe` option which will not decode any message containing an unknown atom.  Out of caution I would suggest avoiding using atoms.
