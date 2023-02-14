defmodule FedecksClient.ConnectorTest do
  use FedecksCase

  alias FedecksClient.{Connector, TokenStore}
  import Mox

  setup :verify_on_exit!

  setup %{name: name} do
    SimplestPubSub.subscribe(name)
    connector_name = :"#{name}.Connector"

    {:ok, connector_name: connector_name}
  end

  describe "starting up" do
    test "connector is named", %{name: name} = ctx do
      start(ctx)
      assert Process.whereis(:"#{name}.Connector")
    end

    test "does not attempt to connect if there is no token configured",
         %{
           name: name,
           connector_name: connector_name
         } = ctx do
      expect(MockWebsocketClient, :start_link, 0, fn _, _, _, _ -> nil end)

      start(ctx)
      assert_receive {^name, :unregistered}
      assert :unregistered == Connector.connection_status(connector_name)
    end

    test "connects if there is a token configured",
         %{token_store: token_store, name: name, connector_name: connector_name} = ctx do
      TokenStore.set_token(token_store, "a token")
      test_pid = self()

      expect(MockWebsocketClient, :start_link, fn url, handler, _, opts ->
        send(test_pid, {:start_link, url, handler, opts})
        start_link_a_process()
      end)

      start(ctx)

      assert_receive {:start_link, url, handler, opts}
      assert "wss://mything.com/fedecks/websocket" == url
      assert MockWebsocketHandler == handler
      assert [extra_headers: [{"x-fedecks-auth", encoded_token}]] = opts

      assert %{"fedecks-device-id" => "nerves-123a", "fedecks-token" => "a token"} ==
               encoded_token |> Base.decode64!() |> :erlang.binary_to_term()

      assert_receive {^name, :connected}
      assert :connected == Connector.connection_status(connector_name)
    end

    test "reports and schedules a retry on failure to connect",
         %{token_store: token_store, name: name, connector_name: connector_name} = ctx do
      TokenStore.set_token(token_store, "some token")
      stub(MockWebsocketClient, :start_link, fn _, _, _, _ -> {:error, "some reason"} end)
      start(ctx)

      assert_receive {^name, {:connection_failed, "some reason"}}

      # should see retries in the mailbox with a 10ms connect_after
      assert_receive {^name, {:connection_failed, "some reason"}}

      assert :failing_to_connect = Connector.connection_status(connector_name)
    end

    test "does not attempt connection until after the connect_after period",
         %{token_store: token_store, name: name, connector_name: connector_name} = ctx do
      TokenStore.set_token(token_store, "some token")

      expect(MockWebsocketClient, :start_link, 0, fn _, _, _, _ -> {:error, "nothing"} end)
      start(ctx, 500)
      assert_receive {^name, :connecting}
      refute_receive {^name, _}
      assert :connecting = Connector.connection_status(connector_name)
    end
  end

  describe "authorising with credentials" do
    setup ctx do
      start(ctx)
      :ok
    end

    test "when successful, connects just like a token", %{
      name: name,
      connector_name: connector_name
    } do
      test_pid = self()

      expect(MockWebsocketClient, :start_link, fn url, handler, _, opts ->
        send(test_pid, {:start_link, url, handler, opts})
        start_link_a_process()
      end)

      Connector.authenticate(connector_name, %{"username" => "bob", "password" => "monkey"})

      assert_receive {:start_link, url, handler, opts}
      assert "wss://mything.com/fedecks/websocket" == url
      assert MockWebsocketHandler == handler
      assert [extra_headers: [{"x-fedecks-auth", encoded_token}]] = opts

      assert %{"fedecks-device-id" => "nerves-123a", "username" => "bob", "password" => "monkey"} ==
               encoded_token |> Base.decode64!() |> :erlang.binary_to_term()

      assert_receive {^name, :connected}
      assert :connected == Connector.connection_status(connector_name)
    end

    test "on failure, state is unregistered and notification of failure received", %{
      name: name,
      connector_name: connector_name
    } do
      stub(MockWebsocketClient, :start_link, fn _, _, _, _ -> {:error, "whatever"} end)

      Connector.authenticate(connector_name, %{"username" => "bob", "password" => "shark"})

      assert_receive {^name, {:registration_failed, "whatever"}}
      assert :unregistered == Connector.connection_status(connector_name)
    end
  end

  describe "reauthorising when a token is saved" do
    setup %{token_store: token_store} do
      TokenStore.set_token(token_store, "existing token")
      :ok
    end

    test "connection timer is cancelled if connection has not yet happened",
         %{
           name: name,
           connector_name: connector_name
         } = ctx do
      expect(MockWebsocketClient, :start_link, fn _, _, _, _ -> start_link_a_process() end)

      start(ctx, 50)

      Connector.authenticate(connector_name, %{"some_credential" => "hello matey"})
      assert_receive {^name, :connected}

      # Just the one connection
      refute_receive {^name, :connected}
    end
  end

  defp start(
         %{name: topic, connector_name: connector_name, token_store: token_store},
         connect_after \\ 10
       ) do
    Connector.start_link(
      name: connector_name,
      connect_after: connect_after,
      connection_url: "wss://mything.com/fedecks/websocket",
      device_id: "nerves-123a",
      handler: MockWebsocketHandler,
      token_store: token_store,
      topic: topic
    )

    allow(MockWebsocketClient, self(), connector_name)
  end

  defp start_link_a_process do
    Task.start_link(fn ->
      receive do
        _ -> :ok
      after
        5_000 -> :ok
      end
    end)
  end

  # todo
  # * websocket terminated!
  # * (re) authorisation when connected
end
