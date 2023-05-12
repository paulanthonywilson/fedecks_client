defmodule FedecksClient.FedecksSupervisorTest do
  use ExUnit.Case, async: true
  alias FedecksClient.{Connector, DeadMansHandle, FedecksSupervisor, TokenStore}

  import FedecksHelpers

  setup do
    name = generate_unique_name()
    token_dir = "#{System.tmp_dir()}/#{name}"

    {:ok, _pid} =
      start_supervised(
        {FedecksSupervisor,
         name: name,
         token_dir: token_dir,
         connection_url: "wss://example.com/fedecks/websocket",
         device_id: "dev123",
         connect_delay: 5_000,
         ping_frequency: 30_000}
      )

    on_exit(fn -> File.rm_rf!(token_dir) end)
    {:ok, name: name, token_dir: token_dir, token_store: TokenStore.server_name(name)}
  end

  test "supervisor is started", %{name: name} do
    assert Process.whereis(:"#{name}.Supervisor")
  end

  test "token store is started", %{token_store: token_store, token_dir: token_dir} do
    assert pid = Process.whereis(token_store)
    %{filename: token_file} = :sys.get_state(pid)
    assert token_file =~ token_dir
  end

  test "connector is started", %{name: name, token_store: token_store} do
    assert pid = Process.whereis(:"#{name}.Connector")

    assert %{
             broadcast_topic: ^name,
             connect_delay: 5_000,
             token_store: ^token_store,
             ping_frequency: 30_000
           } = :sys.get_state(pid)
  end

  test "dead man's handle", %{name: name} do
    assert pid = name |> DeadMansHandle.server_name() |> Process.whereis()
    assert %{timeout: 30_000} = :sys.get_state(pid)
  end

  test "dead man's handle exit also takes out the connector", %{name: name} do
    dead_man = name |> DeadMansHandle.server_name() |> Process.whereis()
    connector = name |> Connector.server_name() |> Process.whereis()

    ref = Process.monitor(connector)

    Process.exit(dead_man, :kill)

    assert_receive {:DOWN, ^ref, _, _, _}, 1_000
  end
end
