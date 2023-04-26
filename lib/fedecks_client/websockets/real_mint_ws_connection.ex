defmodule FedecksClient.Websockets.RealMintWsConnection do
  @moduledoc false
  _doc = """
  Handles Fedecks websockets via `Mint` and `Mint.WebSocket`
  """

  alias FedecksClient.Websockets.{MintWs, MintWsConnection}

  @behaviour MintWsConnection

  @impl MintWsConnection
  def connect(
        %MintWs{
          ws_url: %{http_scheme: http_scheme, host: host, port: port, scheme: scheme, path: path}
        } = mint_ws,
        credentials
      ) do
    auth = auth(mint_ws, credentials)

    # If we don't specify `:http1` then `http2` gets used which works fine when connecting directly
    # to Cowboy but not so much when proxied behind `nginx` which happens with a Fly.io CNAMEd custom domain.
    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port, protocols: [:http1]),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(scheme, conn, path, [{"x-fedecks-auth", auth}]) do
      {:ok, %{mint_ws | conn: conn, ref: ref}}
    else
      {:error, _} = err -> err
      {:error, _, reason} -> {:error, reason}
    end
  end

  @impl MintWsConnection
  def send(mint_ws, message) do
    do_send(mint_ws, :erlang.term_to_binary(message))
  end

  @impl MintWsConnection
  def request_token(mint_ws) do
    do_send(mint_ws, :erlang.term_to_binary('token_please'))
  end

  @impl MintWsConnection
  def ping(%{conn: conn, websocket: websocket, ref: ref, device_id: device_id} = mint_ws) do
    with {:ok, websocket, data} <-
           Mint.WebSocket.encode(websocket, {:ping, device_id}),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      {:ok, %{mint_ws | conn: conn, websocket: websocket}}
    else
      {:error, _, reason} -> {:error, reason}
    end
  end

  @impl MintWsConnection
  def send_raw(mint_ws, message) do
    do_send(mint_ws, message)
  end

  defp do_send(%{conn: conn, websocket: websocket, ref: ref} = mint_ws, message) do
    with {:ok, websocket, data} <-
           Mint.WebSocket.encode(websocket, {:binary, message}),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      {:ok, %{mint_ws | conn: conn, websocket: websocket}}
    else
      {:error, _, reason} -> {:error, reason}
    end
  end

  @impl MintWsConnection
  def handle_in(%{conn: conn, ref: ref, websocket: nil} = mint_ws, message) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn,
       [{:status, ^ref, 101 = status_code}, {:headers, ^ref, resp_headers}, {:done, ^ref}]} ->
        {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status_code, resp_headers)

        {:upgraded, %{mint_ws | conn: conn, websocket: websocket}}

      {:ok, _conn, [{:status, ^ref, status_code}, {:headers, ^ref, _}, {:done, ^ref}]} ->
        {:upgrade_error, status_code}

      {:ok, _conn, _} ->
        {:error, :unexpected_on_non_upgraded_connection}

      {:error, _, err, _} ->
        {:error, err}

      :unknown ->
        {:error, :unkown}
    end
  end

  def handle_in(%{conn: conn, ref: ref} = mint_ws, message) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, [{:data, ^ref, data}]} ->
        decode(%{mint_ws | conn: conn}, data)

      err ->
        {:error, err}
    end
  end

  defp decode(%{websocket: websocket} = mint_ws, data) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, messages} ->
        decoded =
          messages
          |> Enum.map(&decode_fedecks_message/1)
          |> Enum.filter(fn
            :error -> false
            _ -> true
          end)

        {:messages, %{mint_ws | websocket: websocket}, decoded}
    end
  end

  defp decode_fedecks_message(message) do
    with {:ok, decoded} <- safe_decode(message) do
      case decoded do
        {'token', token} -> {:fedecks_token, token}
        msg -> msg
      end
    end
  end

  defp safe_decode({:binary, <<131>> <> _ = binary}) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> :error
  end

  defp safe_decode(_), do: :error

  @impl MintWsConnection
  def close(%MintWs{conn: nil} = mint_ws), do: {:ok, mint_ws}

  def close(%MintWs{conn: conn} = mint_ws) do
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
