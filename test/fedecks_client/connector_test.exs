defmodule FedecksClient.ConnectorTest do
  use FedecksCase, async: true
  alias FedecksClient.{Connector, TokenStore, Websockets.MintWs}

  import Mox
  setup :verify_on_exit!

  @connection_url "wss://example.com/fedecks/websocket"
  @device_id "nerves123"
  @defaults %{
    connection_url: @connection_url,
    connect_delay: :timer.seconds(1),
    ping_frequency: :timer.seconds(30),
    device_id: @device_id
  }
  setup %{name: name} do
    SimplestPubSub.subscribe(name)
    connector_name = :"#{name}.Connector"

    {:ok, Map.put(@defaults, :connector_name, connector_name)}
  end

  setup do
    stub(MockMintWsConnection, :ping, fn mint_ws -> {:ok, mint_ws} end)
    :ok
  end

  describe "starting up" do
    test "connector is named in the global registry", %{connector_name: connector_name} = ctx do
      {:ok, _} = start(ctx)
      assert Process.whereis(connector_name)
    end

    test "fails to start if the connection url is invalid", ctx do
      assert {:error, _} = start(%{ctx | connection_url: "http://example.com/wrongprotocol"})
    end
  end

  describe "on init" do
    # calling the `init/1` callback directly here as we want to establish the
    # behaviour of scheduling a connection with a scheduled message. Zooming out
    # to encompass the `handle_info/2` is problematic with the timing `Mox.allow/1`
    # and actions that take part as part of process initiation.
    #
    # I don't like using Mox in global mode even though async tests are not going to
    # be an issue in this small library. I like to exercise techniques that avoid that
    # cop-out so they can be deployed in bigger projects.
    #
    # Judge all you like, it's my party!

    test "does not attempt connect if no token is configured",
         %{name: name} = ctx do
      {:ok, _} = start(ctx)

      assert {:ok, %Connector{connection_status: :unregistered}} =
               ctx |> Map.to_list() |> Connector.init()

      assert_receive {^name, :unregistered}
      refute_receive {:attempt_connection, _}
    end

    test "schedules an attempt at connection if there is a token configured",
         %{name: name, token_store: token_store} = ctx do
      TokenStore.set_token(token_store, "a pretend token")

      assert {:ok, %Connector{connection_status: :connection_scheduled}} =
               %{ctx | connect_delay: 1}
               |> Map.to_list()
               |> Connector.init()

      assert_receive {^name, :connection_scheduled}
      assert_receive {:attempt_connection, %{"fedecks-token" => "a pretend token"}}
    end

    test "connection attempt does not occur until scheduled", %{token_store: token_store} = ctx do
      TokenStore.set_token(token_store, "a pretend token")

      {:ok, %{connection_status: :connection_scheduled}} =
        %{ctx | connect_delay: :timer.seconds(10)} |> Map.to_list() |> Connector.init()

      refute_receive {:attempt_connection, _}
    end
  end

  describe "on initiating connection" do
    test "attempts to connect and upgrade", %{name: name} = ctx do
      {:ok, pid} = start(ctx)

      ref = :erlang.list_to_ref('#Ref<0.1.2.3>')

      expect(MockMintWsConnection, :connect, fn mintws, credentials ->
        assert %MintWs{device_id: @device_id} = mintws
        assert %{"fedecks-token" => "a token"} = credentials
        {:ok, %{mintws | ref: ref}}
      end)

      send(pid, {:attempt_connection, %{"fedecks-token" => "a token"}})
      assert %{mint_ws: %{ref: ^ref}} = :sys.get_state(pid)
      assert_receive {^name, :connecting}
      assert :connecting = Connector.connection_status(pid)
    end

    test "when connection fails, notifies listeners of failure", %{name: name} = ctx do
      {:ok, pid} = start(ctx)

      expect(MockMintWsConnection, :connect, fn _mintws, _credentials ->
        {:error, "some failure"}
      end)

      send(pid, {:attempt_connection, %{"fedecks-token" => "a token"}})

      assert_receive {^name, {:connection_failed, "some failure"}}
      assert_receive {^name, :connection_scheduled}
      assert :connection_scheduled = Connector.connection_status(pid)
    end

    test "reschedules a new connection attempt on failure" do
      credentials = %{"fedecks-token" => "a token"}

      stub(MockMintWsConnection, :connect, fn _, _ ->
        {:error, "failure"}
      end)

      Connector.handle_info(
        {:attempt_connection, credentials},
        connector_state(%{connect_delay: 1})
      )

      assert_receive {:attempt_connection, ^credentials}
    end

    test "rescheduled new connection on failure is scheduled using the `connect_delay` value" do
      stub(MockMintWsConnection, :connect, fn _, _ ->
        {:error, "failure"}
      end)

      Connector.handle_info(
        {:attempt_connection, %{}},
        connector_state(%{connect_delay: :timer.seconds(60)})
      )

      refute_receive {:attempt_connection, _}
    end
  end

  describe "explicit login" do
    test "cancels any scheduled connection attempts", %{token_store: token_store} = ctx do
      TokenStore.set_token(token_store, "hello")
      {:ok, state} = %{ctx | connect_delay: 50} |> Map.to_list() |> Connector.init()

      stub(MockMintWsConnection, :connect, fn mintws, _credentials ->
        {:ok, mintws}
      end)

      {:noreply, _} = Connector.handle_cast({:login, %{}}, state)
      refute_receive {:attempt_connection, _}
    end

    test "attempts to connect  and upgrade", %{name: name} = ctx do
      {:ok, pid} = start(ctx)

      ref = :erlang.list_to_ref('#Ref<0.1.2.3>')

      expect(MockMintWsConnection, :connect, fn mintws, credentials ->
        assert %MintWs{device_id: @device_id} = mintws
        assert %{"username" => "bob", "password" => "marvelous"} = credentials
        {:ok, %{mintws | ref: ref}}
      end)

      Connector.login(pid, %{"username" => "bob", "password" => "marvelous"})
      assert %{mint_ws: %{ref: ^ref}} = :sys.get_state(pid)

      assert_receive {^name, :connecting}
      assert :connecting = Connector.connection_status(pid)
    end

    test "blanks the token", %{token_store: token_store} = ctx do
      {:ok, pid} = start(ctx)
      stub(MockMintWsConnection, :connect, fn mintws, _ -> {:ok, mintws} end)
      TokenStore.set_token(token_store, "wibble")
      Connector.login(pid, %{"username" => "bob", "password" => "marvelous"})
      process_all_gen_server_messages(pid)
      assert nil == TokenStore.token(token_store)
    end

    test "on error, broadcats connection failed but does not attempt reconnection",
         %{name: name} = ctx do
      {:ok, pid} = start(ctx)

      expect(MockMintWsConnection, :connect, fn _mintws, _credentials ->
        {:error, :failure}
      end)

      Connector.login(pid, %{"username" => "bob", "password" => "marvelous"})
      assert_receive {^name, {:connection_failed, :failure}}
      refute_receive {^name, :connection_scheduled}
      assert :unregistered = Connector.connection_status(pid)
    end
  end

  describe "receiving connection upgrade" do
    setup ctx do
      {:ok, pid} = start(ctx)
      {:ok, connector: pid}
    end

    test "if successful, notifies marks the connection upgraded", %{name: name, connector: pid} do
      data_msg = {:tcp, fake_socket(), "the data"}
      new_ref = a_ref()
      stub(MockMintWsConnection, :request_token, fn mint_ws -> {:ok, mint_ws} end)

      expect(MockMintWsConnection, :handle_in, fn %MintWs{} = mint_ws, data ->
        assert data == data_msg
        {:upgraded, %{mint_ws | ref: new_ref}}
      end)

      send(pid, data_msg)
      assert_receive {^name, :connected}
      assert :connected = Connector.connection_status(pid)
      assert %{mint_ws: %{ref: ^new_ref}} = :sys.get_state(pid)
    end

    test "requests token after upgrade", %{connector: pid} do
      expect(MockMintWsConnection, :request_token, fn %MintWs{} = mint_ws -> {:ok, mint_ws} end)

      upgrade_connection(pid)
      process_all_gen_server_messages(pid)
    end

    test "if   errors, notifies, blanks token, and marks as unregistered", ctx do
      check_exits_on_upgrade_failure(ctx, :error)
    end

    test "if upgrade errors, notifies, and exits", ctx do
      check_exits_on_upgrade_failure(ctx, :upgrade_error)
    end

    defp check_exits_on_upgrade_failure(%{connector: pid, name: name}, error_type) do
      stub(MockMintWsConnection, :handle_in, fn _, _ ->
        {error_type, :unknown}
      end)

      expect(MockMintWsConnection, :close, fn %MintWs{} = mint_ws -> {:ok, mint_ws} end)

      ref = Process.monitor(pid)

      send(pid, {:tcp, fake_socket(), "blah blah"})
      assert_receive {^name, {:upgrade_failed, :unknown}}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  describe "receiving messages" do
    setup ctx do
      pid = start_upgraded_connection(ctx)
      clear_process_inbox()
      {:ok, connector: pid}
    end

    test "updates stored token when fedecks token received", %{
      connector: pid,
      token_store: token_store
    } do
      expect(MockMintWsConnection, :handle_in, fn %MintWs{} = mint_ws, {_, _, "yyy"} ->
        {:messages, mint_ws, [{:fedecks_token, "a new token"}]}
      end)

      send(pid, {:tcp, fake_socket(), "yyy"})
      process_all_gen_server_messages(pid)
      assert "a new token" == TokenStore.token(token_store)
    end

    test "notifies listeners of every message", %{connector: pid, name: name} do
      expect(MockMintWsConnection, :handle_in, fn %MintWs{} = mint_ws, {_, _, "yyy"} ->
        {:messages, mint_ws, ["hello matey", %{"hello" => "matey"}]}
      end)

      send(pid, {:tcp, fake_socket(), "yyy"})
      assert_receive {^name, {:message, "hello matey"}}
      assert_receive {^name, {:message, %{"hello" => "matey"}}}
    end

    test "normal messages mixed with tokens are handled", %{
      connector: pid,
      name: name,
      token_store: token_store
    } do
      expect(MockMintWsConnection, :handle_in, fn %MintWs{} = mint_ws, {_, _, "yyy"} ->
        {:messages, mint_ws, ["hello matey", {:fedecks_token, "some token or other"}]}
      end)

      send(pid, {:tcp, fake_socket(), "yyy"})
      assert_receive {^name, {:message, "hello matey"}}
      process_all_gen_server_messages(token_store)

      assert "some token or other" == TokenStore.token(token_store)
    end

    test "handles ssl messages", %{connector: pid, name: name} do
      expect(MockMintWsConnection, :handle_in, fn %MintWs{} = mint_ws, {_, _, "yyy"} ->
        {:messages, mint_ws, ["hello matey"]}
      end)

      send(pid, {:ssl, fake_socket(), "yyy"})
      assert_receive {^name, {:message, "hello matey"}}
    end
  end

  describe "sending" do
    setup ctx do
      if ctx[:skip_start] do
        :ok
      else
        {:ok, connector: start_upgraded_connection(ctx)}
      end
    end

    test "a normal message, sends a normal message", %{connector: pid} do
      expect(MockMintWsConnection, :send, fn %MintWs{} = mint_ws, {"hello", "matey"} ->
        {:ok, mint_ws}
      end)

      assert :ok = Connector.send_message(pid, {"hello", "matey"})
      process_all_gen_server_messages(pid)
    end

    test "closes connection on normal sending error", %{connector: pid, name: name} do
      expect(MockMintWsConnection, :send, fn %MintWs{}, {"hello", "matey"} ->
        {:error, "an error"}
      end)

      expect(MockMintWsConnection, :close, fn %MintWs{} = mint_ws -> {:ok, mint_ws} end)

      assert :ok = Connector.send_message(pid, {"hello", "matey"})
      process_all_gen_server_messages(pid)

      assert_receive {^name, {:connection_error, "an error"}}
    end

    test "a raw messages, sends a raw message", %{connector: pid} do
      expect(MockMintWsConnection, :send_raw, fn %MintWs{} = mint_ws, "hello matey" ->
        {:ok, mint_ws}
      end)

      assert :ok = Connector.send_raw_message(pid, "hello matey")
      process_all_gen_server_messages(pid)
    end

    test "closes connection on raw sending error", %{connector: pid, name: name} do
      expect(MockMintWsConnection, :send_raw, fn %MintWs{}, "hello matey" ->
        {:error, "another error"}
      end)

      expect(MockMintWsConnection, :close, fn %MintWs{} = mint_ws -> {:ok, mint_ws} end)

      assert :ok = Connector.send_raw_message(pid, "hello matey")
      process_all_gen_server_messages(pid)

      assert_receive {^name, {:connection_error, "another error"}}
    end

    @tag :skip_start
    test "will not send or raw send if not connected", ctx do
      expect(MockMintWsConnection, :send, 0, fn mintws, _ -> {:ok, mintws} end)
      expect(MockMintWsConnection, :send_raw, 0, fn mintws, _ -> {:ok, mintws} end)
      {:ok, pid} = start(ctx)

      assert :ok = Connector.send_message(pid, "hello")
      assert :ok = Connector.send_raw_message(pid, "hello")
      process_all_gen_server_messages(pid)
    end
  end

  describe "pinging" do
    setup do
      stub(MockMintWsConnection, :handle_in, fn mint_ws, {:tcp, _, "upgrade"} ->
        {:upgraded, mint_ws}
      end)

      :ok
    end

    test "schedules pings on upgrade" do
      Connector.handle_info(
        {:tcp, fake_socket(), "upgrade"},
        connector_state(%{ping_frequency: 1})
      )

      assert_receive :ping
    end

    test "pinging sends a ping and reschedules" do
      expect(MockMintWsConnection, :ping, fn %MintWs{} = mint_ws -> {:ok, mint_ws} end)
      Connector.handle_info(:ping, connector_state(%{ping_frequency: 1}))

      assert_receive :ping
    end

    test "pinging on scheduled using the ping frequency " do
      Connector.handle_info(
        {:tcp, fake_socket(), "upgrade"},
        connector_state(%{ping_frequency: 5_000})
      )

      refute_receive :ping
      Connector.handle_info(:ping, connector_state(%{ping_frequency: 5_000}))
      refute_receive :ping
    end
  end

  describe "disconnection" do
    setup ctx do
      pid = start_upgraded_connection(ctx)
      clear_process_inbox()
      {:ok, connector: pid}
    end

    test "notifies listeners", %{name: name, connector: pid} do
      send(pid, {:tcp_closed, fake_socket()})
      assert_receive {^name, :connection_lost}
    end

    test "supports ssl", %{name: name, connector: pid} do
      send(pid, {:ssl_closed, fake_socket()})
      assert_receive {^name, :connection_lost}
    end

    test "exits the genserver normally", %{connector: pid} do
      assert {:stop, :normal, _} =
               Connector.handle_info({:tcp_closed, fake_socket()}, :sys.get_state(pid))
    end
  end

  defp start_upgraded_connection(ctx) do
    {:ok, pid} = start(ctx)
    upgrade_connection(pid)
    pid
  end

  def upgrade_connection(pid) do
    stub(MockMintWsConnection, :request_token, fn mint_ws -> {:ok, mint_ws} end)

    expect(MockMintWsConnection, :handle_in, fn mint_ws, _ ->
      {:upgraded,
       %{mint_ws | ref: :erlang.list_to_ref('#Ref<0.1.2.3>'), websocket: %Mint.WebSocket{}}}
    end)

    send(pid, {:tcp, fake_socket(), "xxx"})

    assert_receive {_, :connected}
    pid
  end

  defp start(ctx) do
    opts =
      ctx
      |> Enum.into([])

    case start_supervised({Connector, opts}) do
      {:ok, pid} ->
        Mox.allow(MockMintWsConnection, self(), pid)
        {:ok, pid}

      err ->
        err
    end
  end

  defp fake_socket do
    # Ports (or references) can't be attributes
    # https://furlough.merecomplexities.com/elixir/2023/03/10/a-fun-but-trivial-limitation-in-exunit-macros.html
    :erlang.list_to_port('#Port<0.1234>')
  end

  defp a_ref do
    :erlang.list_to_ref('#Ref<0.1.2.8>')
  end

  defp connector_state(args) do
    broadcast_topic = Map.get(args, :name, :some_topic)
    {:ok, mint_ws} = MintWs.new(@connection_url, @device_id)

    args
    |> Enum.into(%{
      connection_status: :connecting,
      broadcast_topic: broadcast_topic,
      mint_ws: mint_ws,
      connect_delay: 60_000,
      connection_schedule_ref: nil
    })
    |> Map.put(:__struct__, Connector)
  end
end
