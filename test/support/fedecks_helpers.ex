defmodule FedecksHelpers do
  @moduledoc false
  import ExUnit.Assertions

  @doc """
  Clear out all the messages on this process.
  """
  @spec clear_process_inbox :: :ok
  def clear_process_inbox(count \\ 1_000)

  def clear_process_inbox(0) do
    flunk("Found an unreasonable amount of messages in the process inbox. Giving up.")
  end

  def clear_process_inbox(count) do
    receive do
      _ ->
        clear_process_inbox(count - 1)
    after
      1 -> :ok
    end
  end

  def generate_unique_name do
    String.to_atom("#{:rand.uniform(999)}-#{inspect(self())}")
  end

  @doc """
  Avoid timing issues with casts and messages in a GenServer by waiting for the queue to empty.
  """
  @spec process_all_gen_server_messages(GenServer.server()) :: :ok
  def process_all_gen_server_messages(pid) do
    # Performed through a message to the GenServer so all previous messages must process before
    # this can return
    :sys.get_state(pid)
    :ok
  end
end
