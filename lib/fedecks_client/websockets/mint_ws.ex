defmodule FedecksClient.Websockets.MintWs do
  @moduledoc """
  Handles Fedecks websockets via `Mint` and `Mint.WebSocket`
  """
  alias FedecksClient.Websockets.WebsocketUrl

  required_keys = [:ws_url, :device_id]
  @enforce_keys required_keys
  defstruct [:websocket, :conn, :ref | required_keys]

  def new(url, device_id) do
    with {:ok, ws_url} <- WebsocketUrl.new(url) do
      {:ok, %__MODULE__{ws_url: ws_url, device_id: device_id}}
    end
  end

  def connect(
        %__MODULE__{
          ws_url: %{http_scheme: http_scheme, host: host, port: port, scheme: scheme, path: path}
        } = mint_ws,
        credentials
      ) do
    auth = auth(mint_ws, credentials)

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(scheme, conn, path, [{"x-fedecks-auth", auth}]) do
      {:ok, %{mint_ws | conn: conn, ref: ref}}
    end
  end

  def send(mint_ws, message) do
    do_send(mint_ws, :erlang.term_to_binary(message))
  end

  def request_token(mint_ws) do
    do_send(mint_ws, :erlang.term_to_binary('token_please'))
  end

  def send_raw(mint_ws, message) do
    do_send(mint_ws, message)
  end

  defp do_send(%{conn: conn, websocket: websocket, ref: ref} = mint_ws, message) do
    with {:ok, websocket, data} <-
           Mint.WebSocket.encode(websocket, {:binary, message}),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      {:ok, %{mint_ws | conn: conn, websocket: websocket}}
    else
      err ->
        raise inspect(err)
    end
  end

  def handle_in(%{conn: conn, ref: ref, websocket: nil} = mint_ws, message) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn,
       [{:status, ^ref, 101 = status_code}, {:headers, ^ref, resp_headers}, {:done, ^ref}]} ->
        {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status_code, resp_headers)

        {:upgraded, %{mint_ws | conn: conn, websocket: websocket}}

      {:ok, conn, [{:status, ^ref, status_code}, {:headers, ^ref, _}, {:done, ^ref}]} ->
        close(mint_ws, conn)
        {:upgrade_error, status_code}

      {:ok, conn, s} ->
        close(mint_ws, conn)
        {:error, :unexpected_on_non_upgraded_connection}
    end
  end

  def handle_in(%{conn: conn, ref: ref} = mint_ws, message) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, [{:data, ^ref, data}]} ->
        decode(%{mint_ws | conn: conn}, data)

      err ->
        {:ok, mint_ws} = close(mint_ws)
        {:error, mint_ws, err}
    end
  end

  defp decode(%{websocket: websocket} = mint_ws, data) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, messages} ->
        decoded = for {:binary, <<131>> <> _ = m} <- messages, do: decode_fedecks_message(m)
        {:messages, %{mint_ws | websocket: websocket}, decoded}
    end
  end

  defp decode_fedecks_message(message) do
    message
    # todo safe
    |> :erlang.binary_to_term()
    |> case do
      {'token', token} -> {:fedecks_token, token}
      msg -> msg
    end
  end

  defp close(mint_ws, conn) do
    close(%{mint_ws | conn: conn})
  end

  def close(%__MODULE__{conn: nil} = mint_ws), do: {:ok, mint_ws}

  def close(%__MODULE__{conn: conn} = mint_ws) do
    {:ok, conn} = Mint.HTTP.close(conn)
    {:ok, %{mint_ws | conn: conn}}
  end

  defp auth(%{device_id: device_id}, credentials) do
    credentials
    |> Map.merge(%{"fedecks-device-id" => device_id})
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end
end
