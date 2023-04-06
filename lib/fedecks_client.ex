defmodule FedecksClient do
  @moduledoc """

  """

  defmacro __using__(_) do
    quote do
      def start_link(_) do
        maybe_val = fn fun, default ->
          if function_exported?(__MODULE__, fun, 0) do
            apply(__MODULE__, fun, [])
          else
            default
          end
        end

        FedecksClient.FedecksSupervisor.start_link(
          name: __MODULE__,
          token_dir: maybe_val.(:token_dir, unquote(__MODULE__).default_token_dir()),
          connection_url: connection_url(),
          device_id: device_id(),
          connect_delay: maybe_val.(:connect_delay, unquote(__MODULE__).default_connect_delay()),
          ping_frequency:
            maybe_val.(:ping_frequency, unquote(__MODULE__).default_ping_frequency())
        )
      end
    end
  end

  @default_connect_delay 10_000
  @default_ping_frequency 19_000

  @mix_env Mix.env()
  @mix_target Mix.target()

  @dev_token_dir "#{System.tmp_dir!()}/#{__MODULE__}"
  def default_token_dir(mix_env \\ @mix_env, mix_target \\ @mix_target)
  def default_token_dir(:test, _), do: @dev_token_dir
  def default_token_dir(_, :host), do: @dev_token_dir
  def default_token_dir(_, _), do: "/root/fedecks"

  def default_connect_delay, do: @default_connect_delay
  def default_ping_frequency, do: @default_ping_frequency
end
