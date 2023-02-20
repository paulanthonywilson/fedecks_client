defmodule StubMintWs do
  @moduledoc false
  alias FedecksClient.Websockets.RealMintWs

  alias FedecksClient.Websockets.MintWsConnection
  @behaviour MintWs

  @impl MintWs
  def close(mintws), do: {:ok, mintws}

  @impl MintWs
  def connect(mintws, _), do: {:ok, mintws}

  @impl MintWs
  def handle_in(mintws, _), do: {:ok, mintws}

  @impl MintWs
  def request_token(mint_ws), do: {:ok, mint_ws}

  @impl MintWs
  def send(mintws, _), do: {:ok, mintws}

  @impl MintWs
  def send_raw(mintws, _), do: {:ok, mintws}
end
