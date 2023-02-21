defmodule FedecksClient.Websockets.WebsocketUrl do
  @moduledoc """
  Holds and validates  websocket url in a way that is useful for using with Mint Websockets
  """

  required_keys = [:scheme, :http_scheme, :host, :port, :path]
  @enforce_keys required_keys
  defstruct required_keys

  def new(string_url) do
    string_url
    |> URI.new()
    |> validate()
    |> uri_to_websocket_url()
  end

  defp validate({:error, part}) do
    {:error, "Invalid url at or after '#{part}'"}
  end

  defp validate({:ok, %{scheme: nil}}) do
    {:error, "Websocket scheme not in url"}
  end

  defp validate({:ok, %{scheme: scheme}}) when scheme not in ["ws", "wss"] do
    {:error, "Not a websocket scheme '#{scheme}'"}
  end

  defp validate({:ok, %{host: ""}}) do
    {:error, "Hostname not in url"}
  end

  defp validate({:ok, uri}) do
    {:ok, uri}
  end

  defp uri_to_websocket_url({:error, _} = err), do: err

  defp uri_to_websocket_url({:ok, uri}) do
    {:ok,
     %__MODULE__{
       scheme: atomise_scheme(uri),
       http_scheme: http_scheme(uri),
       host: host(uri),
       port: port(uri),
       path: path(uri)
     }}
  end

  defp atomise_scheme(%{scheme: "ws"}), do: :ws
  defp atomise_scheme(%{scheme: "wss"}), do: :wss

  defp http_scheme(%{scheme: "ws"}), do: :http
  defp http_scheme(%{scheme: "wss"}), do: :https

  defp host(%{host: host}), do: host

  defp port(%{port: port}), do: port

  defp path(%{path: nil}), do: "/"
  defp path(%{path: path}), do: path
end
