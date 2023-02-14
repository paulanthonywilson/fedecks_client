defmodule FedecksClient.WebsocketClient do
  @moduledoc """
  Testing seam for the Jermy Ong (forked) `:websocket_client`

  """

  defmacro __using__(_) do
    implementation =
      case apply(Mix, :env, []) do
        :test -> MockWebsocketClient
        _ -> FedecksClient.RealWebsocketClient
      end

    quote do
      alias unquote(implementation), as: WebsocketClient
    end
  end

  @callback start_link(
              url :: String.t(),
              handler_module :: atom(),
              handler_args :: Keyword.t(),
              opts :: Keyword.t()
            ) ::
              {:ok, pid()} | {:error, term()}
end
