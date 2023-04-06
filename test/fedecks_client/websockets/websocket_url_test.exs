defmodule FedecksClient.Websockets.WebsocketUrlTest do
  use ExUnit.Case, async: true
  alias FedecksClient.Websockets.WebsocketUrl

  test "valid ws urls" do
    assert {:ok, %WebsocketUrl{}} = WebsocketUrl.new("ws://blah.com")
    assert {:ok, %WebsocketUrl{}} = WebsocketUrl.new("ws://localhost/mavis")
    assert {:ok, %WebsocketUrl{}} = WebsocketUrl.new("ws://localhost:4133/mavis")
    assert {:ok, %WebsocketUrl{}} = WebsocketUrl.new("wss://blah.com")
    assert {:ok, %WebsocketUrl{}} = WebsocketUrl.new("wss://localhost/mavis")
    assert {:ok, %WebsocketUrl{}} = WebsocketUrl.new("wss://localhost:4133/mavis")
  end

  test "invalid ws urls" do
    assert {:error, "Invalid url at or after ':'"} == WebsocketUrl.new("ws://blah.com/miss>h")
    assert {:error, "Not a websocket scheme 'http'"} == WebsocketUrl.new("http://blah.com")
    assert {:error, "Websocket scheme not in url"} == WebsocketUrl.new("blah.com")

    assert {:error, "Hostname not in url"} == WebsocketUrl.new("ws://")
    assert {:error, "Hostname not in url"} == WebsocketUrl.new("ws:///")
    assert {:error, "Hostname not in url"} == WebsocketUrl.new("ws:///justapath")
  end

  test "scheme converted to atom" do
    assert {:ok, %{scheme: :ws}} = WebsocketUrl.new("ws://blah.com")
    assert {:ok, %{scheme: :wss}} = WebsocketUrl.new("wss://blah.com")
  end

  test "http_scheme" do
    assert {:ok, %{http_scheme: :http}} = WebsocketUrl.new("ws://blah.com")
    assert {:ok, %{http_scheme: :https}} = WebsocketUrl.new("wss://blah.com")
  end

  test "host" do
    assert {:ok, %{host: "wibble.com"}} = WebsocketUrl.new("ws://wibble.com")
    assert {:ok, %{host: "wibble.com"}} = WebsocketUrl.new("ws://wibble.com/blah")
    assert {:ok, %{host: "wibble.com"}} = WebsocketUrl.new("wss://wibble.com/blah")
    assert {:ok, %{host: "wibble.com"}} = WebsocketUrl.new("wss://wibble.com:81/blah")
    assert {:ok, %{host: "wobble"}} = WebsocketUrl.new("ws://wobble")
  end

  test "port" do
    assert {:ok, %{port: 80}} = WebsocketUrl.new("ws://blah.co.uk")
    assert {:ok, %{port: 81}} = WebsocketUrl.new("ws://blah.co.uk:81")
    assert {:ok, %{port: 443}} = WebsocketUrl.new("wss://blah.co.uk")
    assert {:ok, %{port: 843}} = WebsocketUrl.new("wss://blah.co.uk:843")
  end

  test "path" do
    assert {:ok, %{path: "/fks/websocket"}} = WebsocketUrl.new("ws://merecomps.com/fks/websocket")
    assert {:ok, %{path: "/"}} = WebsocketUrl.new("wss://merecomps.com/")
    assert {:ok, %{path: "/"}} = WebsocketUrl.new("wss://merecomps.com")
  end
end
