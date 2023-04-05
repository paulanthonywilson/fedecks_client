defmodule FedecksClient.FedecksSupervisorTest do
  use ExUnit.Case
  alias FedecksClient.{FedecksSupervisor, TokenStore}

  import FedecksHelpers

  setup do
    name = generate_unique_name()
    token_dir = "#{System.tmp_dir()}/#{name}"

    {:ok, _pid} =
      FedecksSupervisor.start_link(
        name: name,
        token_dir: token_dir,
        connection_url: "wss://example.com/fedecks/websocket",
        device_id: "dev123",
        connect_delay: 5_000,
        ping_frequency: 30_000
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
end
