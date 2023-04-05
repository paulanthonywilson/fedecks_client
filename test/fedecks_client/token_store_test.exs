defmodule FedecksClient.TokenStoreTest do
  use FedecksCase
  alias FedecksClient.TokenStore

  test "saving and retreiving", %{token_store: token_store} do
    assert nil == TokenStore.token(token_store)
    :ok = TokenStore.set_token(token_store, "my token")
    assert("my token" == TokenStore.token(token_store))
  end

  test "persistence", %{token_store: token_store, name: name} do
    :ok = TokenStore.set_token(token_store, "my saved token")
    assert "my saved token" == TokenStore.token(token_store)
    ensure_killed(token_store)
    {:ok, _pid} = TokenStore.start_link(directory: System.tmp_dir(), name: name)
    assert "my saved token" == TokenStore.token(token_store)
  end

  test "token can be nil", %{token_store: token_store} do
    :ok = TokenStore.set_token(token_store, "my saved token")
    :ok = TokenStore.set_token(token_store, nil)
    assert nil == TokenStore.token(token_store)
  end

  defp ensure_killed(name) do
    pid = Process.whereis(name)
    Process.unlink(pid)
    Process.exit(pid, :kill)

    ensure_unregistered(name)
  end

  defp ensure_unregistered(name, countdown \\ 1000)
  defp ensure_unregistered(_name, 0), do: flunk("Failed to unregister token store")

  defp ensure_unregistered(name, countdown) do
    if Process.whereis(name) do
      Process.sleep(1)
      ensure_unregistered(name, countdown - 1)
    else
      {:ok, countdown}
    end
  end
end
