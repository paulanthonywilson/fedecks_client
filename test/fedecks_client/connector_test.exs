defmodule FedecksClient.ConnectorTest do
  use FedecksCase, async: false
  alias FedecksClient.{Connector, TokenStore}

  import Mox
  alias FedecksClient.Websockets.MintWs
  setup :verify_on_exit!

  @connection_url "wss://example.com/fedecks/websocket"
  @credentials %{"username" => "marvin", "password" => "paranoid-android"}
  @device_id "nerves123"

  setup %{name: name} do
    SimplestPubSub.subscribe(name)
    connector_name = :"#{name}.Connector"

    {:ok,
     connector_name: connector_name,
     connection_url: @connection_url,
     connect_delay: :timer.seconds(1),
     device_id: @device_id}
  end

  describe "starting up" do
    test "connector is named in the global registry", %{connector_name: connector_name} = ctx do
      {:ok, _} = start(ctx)
      # assert Process.whereis(connector_name)
    end

    test "does not attempt connect if no token is configured",
         %{name: name, connector_name: connector_name} = ctx do
      {:ok, _} = start(ctx)
      assert_receive {^name, :unregistered}
      assert :unregistered == Connector.connection_status(connector_name)
    end

    test "fails to start if the connection url is invalid", ctx do
      assert {:error, _} = start(%{ctx | connection_url: "http://example.com/wrongprotocol"})
    end

    test "schedules an attempt at connection if there is a token configured",
         %{connector_name: connector_name, name: name, token_store: token_store} = ctx do
      TokenStore.set_token(token_store, "a pretend token")

      expect(MockMintWs, :connect, fn %MintWs{}, credentials_used ->
        %{"fedecks-token" => "a pretend token"} == credentials_used
      end)

      {:ok, _} = start(%{ctx | connect_delay: 1})
      assert_receive {^name, :connecting}
      assert :connecting = Connector.connection_status(connector_name)
    end

    test "does not connect if token is configured, until after the delay" do
    end
  end

  defp start(ctx) do
    opts =
      ctx
      |> Enum.into([])

    case start_supervised({Connector, opts}) do
      {:ok, pid} ->
        {:ok, pid}

      err ->
        err
    end
  end
end
