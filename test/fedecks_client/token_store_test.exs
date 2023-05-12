defmodule FedecksClient.TokenStoreTest do
  use FedecksCase, async: true
  alias FedecksClient.TokenStore

  test "persistence", %{token_store: token_store} do
    :ok = TokenStore.set_token(token_store, "my saved token")
    assert "my saved token" == TokenStore.token(token_store)
    restart(token_store)
    assert "my saved token" == TokenStore.token(token_store)
  end

  test "nil persistence", %{token_store: token_store} do
    :ok = TokenStore.set_token(token_store, "token")
    :ok = TokenStore.set_token(token_store, nil)
    process_all_gen_server_messages(token_store)
    restart(token_store)
    assert nil == TokenStore.token(token_store)
  end

  test "token can be nil", %{token_store: token_store} do
    :ok = TokenStore.set_token(token_store, "my saved token")
    :ok = TokenStore.set_token(token_store, nil)
    assert nil == TokenStore.token(token_store)
  end

  defp restart(name) do
    pid = Process.whereis(name)

    Process.unlink(pid)

    ref = Process.monitor(pid)
    GenServer.stop(pid, :normal)

    assert_receive {:DOWN, ^ref, _, _, _}
    ensure_started(name)
  end

  defp ensure_started(count \\ 100, name)
  defp ensure_started(0, _name), do: flunk("Token store not restarted")

  defp ensure_started(count, name) do
    unless Process.whereis(name) do
      Process.sleep(10)
      ensure_started(count - 1, name)
    end
  end
end
