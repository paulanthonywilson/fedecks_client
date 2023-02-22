defmodule FedecksClient.Websockets.MintWsTest do
  use ExUnit.Case, async: false
  alias FedecksClient.Websockets.{MintWs, WebsocketUrl}

  @test_url "ws://localhost:12833/fedecks/websocket"
  @device_id "id345"

  setup do
    {:ok, _} = start_supervised(FedecksServerEndpoint)
    :ok
  end

  describe "new" do
    test "with valid url" do
      assert {:ok, %MintWs{ws_url: %WebsocketUrl{host: "localhost"}, device_id: "id123"}} =
               MintWs.new(@test_url, "id123")
    end

    test "with invalid url" do
      assert {:error, "Not a websocket" <> _} = MintWs.new("http://localhost", "123")
    end
  end

  describe "connect" do
    test "to valid server" do
      %{ws_url: url} = mint_ws = new(@test_url)

      assert {:ok,
              %MintWs{
                ws_url: ^url,
                conn: %Mint.HTTP1{request: %{ref: ref}},
                ref: ref,
                websocket: nil
              } = mint_ws} = MintWs.connect(mint_ws, %{})

      MintWs.close(mint_ws)
    end

    test "and upgrade valid server with valid credentials" do
      assert {:ok, %{ref: ref} = mint_ws} =
               @test_url
               |> new()
               |> MintWs.connect(%{"username" => "bob", "password" => "bob's password"})

      # From Mint websocket upgrade
      assert_receive {:tcp, _port, mint_data} = mint_message

      assert mint_data =~ "Switching Protocols"

      assert {:upgraded, mint_ws} = MintWs.handle_in(mint_ws, mint_message)

      assert %MintWs{ref: ^ref, websocket: %Mint.WebSocket{}} = mint_ws
      MintWs.close(mint_ws)
    end

    test "can not only process ugrade message when already upgraded" do
      {:ok, not_upgraded_mint_ws} =
        @test_url
        |> new()
        |> MintWs.connect(%{"username" => "bob", "password" => "bob's password"})

      # From Mint websocket upgrade
      assert_receive {:tcp, _port, _} = upgrade_message

      {:upgraded, _mint_ws} = MintWs.handle_in(not_upgraded_mint_ws, upgrade_message)

      assert_receive {:tcp, _port, _} = fedecks_token

      assert {:error, :unexpected_on_non_upgraded_connection} =
               MintWs.handle_in(not_upgraded_mint_ws, fedecks_token)
    end

    test "with invalid credentials" do
      assert {:ok, mint_ws} =
               @test_url
               |> new()
               |> MintWs.connect(%{"username" => "bob", "password" => "bad password"})

      # From Mint websocket upgrade
      assert_receive {:tcp, _port, mint_data} = mint_message

      assert mint_data =~ "Forbidden"
      assert {:upgrade_error, 403} = MintWs.handle_in(mint_ws, mint_message)
    end

    test "to invalid server" do
      assert {:error, %{reason: :nxdomain}} = MintWs.connect(new("ws://notlocal"), %{})
      assert {:error, %{reason: :econnrefused}} = MintWs.connect(new("ws://localhost:12834"), %{})
    end
  end

  describe "receive messages" do
    setup do
      {:ok, mint_ws} =
        @test_url
        |> new()
        |> MintWs.connect(%{"username" => "bob", "password" => "bob's password"})

      assert_receive {:tcp, _port, _} = upgrade_message

      {:upgraded, mint_ws} = MintWs.handle_in(mint_ws, upgrade_message)
      on_exit(fn -> MintWs.close(mint_ws) end)

      {:ok, mint_ws: mint_ws}
    end

    test "receiving fedecks token", %{mint_ws: mint_ws} do
      assert_receive {:tcp, _port, _} = token_message
      assert {:fedecks_token, %MintWs{}, token} = MintWs.handle_in(mint_ws, token_message)
      secrets = FedecksServer.Config.token_secrets({:fedecks_client, FedecksTestHandler})

      assert {:ok, @device_id} == FedecksServer.Token.from_token(token, secrets)
    end

    test "receiving other fedecks message", %{mint_ws: mint_ws} do
      assert_receive {:tcp, _port, _} = token_message
      {:fedecks_token, mint_ws, _} = MintWs.handle_in(mint_ws, token_message)

      SimplestPubSub.publish({:message_to, @device_id}, "hello matey")
      assert_receive {:tcp, _port, _} = other_message

      assert {:message, %MintWs{}, "hello matey"} = MintWs.handle_in(mint_ws, other_message)
    end

    test "decoding multiple messages", %{mint_ws: mint_ws} do
      SimplestPubSub.publish({:message_to, @device_id}, "message 1")
      SimplestPubSub.publish({:message_to, @device_id}, "message 2")

      assert_receive {:tcp, _port, _} = messages

      assert {:messages, %MintWs{}, [{:fedecks_token, _}, "message 1", "message 2"]} =
               MintWs.handle_in(mint_ws, messages)
    end
  end

  test "closing" do
    {:ok, mint_ws} =
      @test_url
      |> new()
      |> MintWs.connect(%{"username" => "bob", "password" => "bob's password"})

    assert {:ok, %MintWs{conn: %{state: :closed}}} = MintWs.close(mint_ws)
  end

  test "closing an unopened connection is a no-op" do
    mint_ws = new(@test_url)
    assert {:ok, mint_ws} == MintWs.close(mint_ws)
  end

  defp new(url) do
    {:ok, res} = MintWs.new(url, @device_id)
    res
  end
end
