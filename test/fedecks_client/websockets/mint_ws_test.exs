defmodule FedecksClient.Websockets.MintWsTest do
  use ExUnit.Case, async: true
  alias FedecksClient.Websockets.{MintWs, WebsocketUrl}

  test "with valid url" do
    assert {:ok, %MintWs{ws_url: %WebsocketUrl{host: "localhost"}, device_id: "id123"}} =
             MintWs.new("ws://localhost:3993/feddy/weddy", "id123")
  end

  test "with invalid url" do
    assert {:error, "Not a websocket" <> _} = MintWs.new("http://localhost", "123")
  end
end
