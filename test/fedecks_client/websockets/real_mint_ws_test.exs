defmodule FedecksClient.Websockets.RealMintWsTest do
  use ExUnit.Case, async: false
  alias FedecksClient.Websockets.{MintWs, RealMintWs, WebsocketUrl}

  import ExUnit.CaptureLog

  @test_url "ws://localhost:12833/fedecks/websocket"
  @device_id "id345"

  setup do
    capture_log(fn ->
      :ok = start_server()
    end)

    :ok
  end

  defp start_server(count \\ 100)
  defp start_server(0), do: flunk("could not start the server")

  defp start_server(count) do
    case start_supervised(FedecksServerEndpoint) do
      {:ok, _} ->
        :ok

      _ ->
        Process.sleep(10)
        start_server(count - 1)
    end
  end

  describe "new" do
    test "with valid url" do
      assert {:ok, %MintWs{ws_url: %WebsocketUrl{host: "localhost"}, device_id: "id123"}} =
               RealMintWs.new(@test_url, "id123")
    end

    test "with invalid url" do
      assert {:error, "Not a websocket" <> _} = RealMintWs.new("http://localhost", "123")
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
              } = mint_ws} = RealMintWs.connect(mint_ws, %{})

      RealMintWs.close(mint_ws)
    end

    test "and upgrade valid server with valid credentials" do
      assert {:ok, %{ref: ref} = mint_ws} =
               @test_url
               |> new()
               |> RealMintWs.connect(%{"username" => "bob", "password" => "bob's password"})

      # From Mint websocket upgrade
      assert_receive {:tcp, _socket, mint_data} = mint_message

      assert mint_data =~ "Switching Protocols"

      assert {:upgraded, mint_ws} = RealMintWs.handle_in(mint_ws, mint_message)

      assert %MintWs{ref: ^ref, websocket: %Mint.WebSocket{}} = mint_ws
      RealMintWs.close(mint_ws)
    end

    test "can not  process ugrade message when already upgraded" do
      {:ok, not_upgraded_mint_ws} =
        @test_url
        |> new()
        |> RealMintWs.connect(%{"username" => "bob", "password" => "bob's password"})

      # From Mint websocket upgrade
      assert_receive {:tcp, _socket, _} = upgrade_message

      {:upgraded, mint_ws} = RealMintWs.handle_in(not_upgraded_mint_ws, upgrade_message)

      {:ok, _mint_ws} = RealMintWs.request_token(mint_ws)

      assert_receive {:tcp, _socket, _} = fedecks_token

      capture_log(fn ->
        assert {:error, :unexpected_on_non_upgraded_connection} =
                 RealMintWs.handle_in(not_upgraded_mint_ws, fedecks_token)
      end)
    end

    test "with invalid credentials" do
      assert {:ok, mint_ws} =
               @test_url
               |> new()
               |> RealMintWs.connect(%{"username" => "bob", "password" => "bad password"})

      # From Mint websocket upgrade
      assert_receive {:tcp, _socket, mint_data} = mint_message

      assert mint_data =~ "Forbidden"
      assert {:upgrade_error, 403} = RealMintWs.handle_in(mint_ws, mint_message)
    end

    test "to invalid server" do
      assert {:error, %{reason: :nxdomain}} = RealMintWs.connect(new("ws://notlocal"), %{})

      assert {:error, %{reason: :econnrefused}} =
               RealMintWs.connect(new("ws://localhost:12834"), %{})
    end
  end

  describe "sending" do
    setup do
      SimplestPubSub.subscribe(FedecksTestHandler)
      {:ok, mint_ws: connect_and_upgrade()}
    end

    test "a message", %{mint_ws: mint_ws} do
      {:ok, %MintWs{}} = RealMintWs.send(mint_ws, "hello matey")
      assert_receive {FedecksTestHandler, {:server_received, "hello matey"}}
    end

    test "a raw binary", %{mint_ws: mint_ws} do
      {:ok, %MintWs{}} = RealMintWs.send_raw(mint_ws, "hello matey")
      assert_receive {FedecksTestHandler, {:server_received_raw, "hello matey"}}
    end

    test "requesting a token", %{mint_ws: mint_ws} do
      {:ok, %MintWs{}} = RealMintWs.request_token(mint_ws)
      assert_receive {:tcp, _socket, _} = token_message

      assert {:messages, %MintWs{}, [{:fedecks_token, token}]} =
               RealMintWs.handle_in(mint_ws, token_message)

      secrets = FedecksServer.Config.token_secrets({:fedecks_client, FedecksTestHandler})

      assert {:ok, @device_id} == FedecksServer.Token.from_token(token, secrets)
    end
  end

  describe "receive messages" do
    setup ctx do
      mint_ws = connect_and_upgrade(ctx)

      {:ok, mint_ws: mint_ws}
    end

    test "receiving other fedecks message", %{mint_ws: mint_ws} do
      SimplestPubSub.publish({:message_to, @device_id}, "hello matey")
      assert_receive {:tcp, _socket, _} = other_message

      assert {:messages, %MintWs{}, ["hello matey"]} =
               RealMintWs.handle_in(mint_ws, other_message)
    end

    test "decoding multiple messages", %{mint_ws: mint_ws} do
      %{conn: %{socket: socket}} = mint_ws

      # Can not reliably predict the number of frames received so here  a message is captured
      assert {:messages, %MintWs{}, [{:fedecks_token, _}, "message 1", "message 2"]} =
               RealMintWs.handle_in(
                 %{mint_ws | websocket: %Mint.WebSocket{}},
                 {:tcp, socket,
                  <<130, 126, 0, 163, 131, 104, 2, 107, 0, 5, 116, 111, 107, 101, 110, 109, 0, 0,
                    0, 147, 81, 84, 69, 121, 79, 69, 100, 68, 84, 81, 46, 50, 82, 120, 68, 97,
                    100, 99, 73, 90, 83, 86, 105, 72, 72, 112, 68, 56, 115, 100, 76, 113, 122,
                    122, 69, 79, 51, 57, 54, 118, 117, 70, 122, 82, 52, 110, 108, 81, 113, 113,
                    100, 95, 103, 51, 104, 120, 49, 70, 106, 86, 113, 84, 115, 75, 107, 48, 57,
                    103, 75, 77, 46, 121, 109, 87, 57, 72, 52, 81, 116, 113, 113, 116, 118, 83,
                    111, 114, 65, 46, 122, 86, 80, 53, 53, 54, 55, 57, 67, 85, 102, 77, 49, 108,
                    95, 54, 114, 53, 78, 113, 53, 122, 55, 76, 72, 99, 73, 90, 73, 80, 73, 77, 82,
                    82, 72, 78, 46, 82, 84, 107, 54, 108, 103, 113, 115, 79, 99, 65, 100, 114,
                    116, 73, 67, 87, 79, 88, 110, 69, 103, 130, 15, 131, 109, 0, 0, 0, 9, 109,
                    101, 115, 115, 97, 103, 101, 32, 49, 130, 15, 131, 109, 0, 0, 0, 9, 109, 101,
                    115, 115, 97, 103, 101, 32, 50>>}
               )
    end

    test "bad messages ignored", %{mint_ws: mint_ws} do
      %{conn: %{socket: socket}} = mint_ws

      assert {:messages, %MintWs{}, []} =
               RealMintWs.handle_in(
                 %{mint_ws | websocket: %Mint.WebSocket{}},
                 {:tcp, socket, "lolnope"}
               )
    end

    test "errors handled", %{mint_ws: mint_ws} do
      assert {:error, :unknown} =
               RealMintWs.handle_in(
                 %{mint_ws | websocket: %Mint.WebSocket{}},
                 {:tcp, :erlang.list_to_port('#Port<0.9999>'), "lolnope"}
               )
    end
  end

  test "closing" do
    {:ok, mint_ws} =
      @test_url
      |> new()
      |> RealMintWs.connect(%{"username" => "bob", "password" => "bob's password"})

    assert {:ok, %MintWs{conn: %{state: :closed}}} = RealMintWs.close(mint_ws)
  end

  test "closing an unopened connection is a no-op" do
    mint_ws = new(@test_url)
    assert {:ok, mint_ws} == RealMintWs.close(mint_ws)
  end

  defp new(url) do
    {:ok, res} = RealMintWs.new(url, @device_id)
    res
  end

  defp connect_and_upgrade(ctx \\ %{}) do
    {:ok, mint_ws} =
      ctx
      |> Map.get(:url, @test_url)
      |> new()
      |> RealMintWs.connect(%{"username" => "bob", "password" => "bob's password"})

    assert_receive {:tcp, _socket, _} = upgrade_message

    {:upgraded, mint_ws} = RealMintWs.handle_in(mint_ws, upgrade_message)

    on_exit(fn -> RealMintWs.close(mint_ws) end)
    mint_ws
  end
end
