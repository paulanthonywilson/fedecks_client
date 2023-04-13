defmodule FedecksClientTest do
  use ExUnit.Case, async: true

  import FedecksHelpers
  import Mox

  setup :verify_on_exit!

  alias FedecksClient.{Connector, FedecksSupervisor, TokenStore}

  defmodule FullyCustomised do
    use FedecksClient
    @alt_token_dir "#{System.tmp_dir!()}/#{__MODULE__}"

    def token_dir, do: @alt_token_dir
    def connection_url, do: "wss://example.com/somewhere/websocket"
    def device_id, do: "some-device"
    def connect_delay, do: 123_456
    def ping_frequency, do: 12_000
  end

  defmodule MinimumConfig do
    use FedecksClient

    def connection_url, do: "wss://example.com/somewhere/websocket"
    def device_id, do: "some-device"
  end

  setup do
    on_exit(fn -> File.rm_rf!(FullyCustomised.token_dir()) end)
    :ok
  end

  test "full configuration" do
    assert {:ok, pid} = FullyCustomised.start_link([])
    assert pid == FullyCustomised |> FedecksSupervisor.supervisor_name() |> Process.whereis()

    assert connector_pid = FullyCustomised |> Connector.server_name() |> Process.whereis()

    token_store = TokenStore.server_name(FullyCustomised)

    assert %{
             broadcast_topic: FullyCustomised,
             connect_delay: 123_456,
             token_store: ^token_store,
             ping_frequency: 12_000
           } = :sys.get_state(connector_pid)

    assert Process.whereis(token_store)

    assert %{directory: token_dir} = :sys.get_state(token_store)
    assert token_dir == FullyCustomised.token_dir()
  end

  test "child spec" do
    assert %{start: {MinimumConfig, :start_link, [:opts]}} = MinimumConfig.child_spec(:opts)
  end

  describe "connection functions" do
    setup do
      {:ok, _pid} = MinimumConfig.start_link([])
      allow(MockMintWsConnection, self(), MinimumConfig.Connector)
      :ok
    end

    test "login" do
      creds = %{"username" => "bob", "password" => "mavis"}
      expect(MockMintWsConnection, :connect, fn mintws, ^creds -> {:ok, mintws} end)
      assert :ok = MinimumConfig.login(creds)
      process_all_gen_server_messages(MinimumConfig.Connector)
    end

    test "subscribe" do
      assert :ok = MinimumConfig.subscribe()
      SimplestPubSub.publish(MinimumConfig, "yep")
      assert_receive "yep"
    end

    test "send message" do
      expect(MockMintWsConnection, :send, fn mintws, {"hello", "matey"} -> {:ok, mintws} end)
      assert :ok = MinimumConfig.send({"hello", "matey"})
      process_all_gen_server_messages(MinimumConfig.Connector)
    end

    test "send raw message" do
      expect(MockMintWsConnection, :send_raw, fn mintws, "hello" -> {:ok, mintws} end)
      assert :ok = MinimumConfig.send_raw("hello")
      process_all_gen_server_messages(MinimumConfig.Connector)
    end

    test "connection_status" do
      assert :unregistered == MinimumConfig.connection_status()
    end
  end

  test "mimimum configuration" do
    assert {:ok, pid} = MinimumConfig.start_link([])
    assert pid == MinimumConfig |> FedecksSupervisor.supervisor_name() |> Process.whereis()

    assert connector_pid = MinimumConfig |> Connector.server_name() |> Process.whereis()

    token_store = TokenStore.server_name(MinimumConfig)

    assert %{
             broadcast_topic: MinimumConfig,
             connect_delay: 10_000,
             token_store: ^token_store,
             ping_frequency: 19_000
           } = :sys.get_state(connector_pid)

    assert Process.whereis(token_store)

    assert %{directory: token_dir} = :sys.get_state(token_store)
    assert token_dir == FedecksClient.default_token_dir()
  end

  test "default token dir" do
    assert FedecksClient.default_token_dir(:test, :host) =~ System.tmp_dir()
    assert FedecksClient.default_token_dir(:test, nil) =~ System.tmp_dir()
    assert FedecksClient.default_token_dir(:dev, :host) =~ System.tmp_dir()
    assert FedecksClient.default_token_dir(:prod, :host) =~ System.tmp_dir()
    assert FedecksClient.default_token_dir(:prod, :rpi0) =~ "/root/fedecks"
    assert FedecksClient.default_token_dir(:dev, :rpi0) =~ "/root/fedecks"
  end
end
