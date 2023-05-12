defmodule FedecksClient.DeadMansHandleTest do
  use FedecksCase, async: true
  alias FedecksClient.DeadMansHandle

  setup %{name: name} do
    pid = start_supervised!({DeadMansHandle, name: name, pong_timeout: 10})
    ref = Process.monitor(pid)
    pong_topic = DeadMansHandle.server_name(name)
    {:ok, ref: ref, topic: pong_topic}
  end

  test "dies if no pongs received after ping", %{ref: ref, topic: topic} do
    SimplestPubSub.publish(topic, :ping)
    assert_receive {:DOWN, ^ref, _, _, _}
  end

  test "death is averted if a pong is received following a ping", %{ref: ref, topic: topic} do
    SimplestPubSub.publish(topic, :ping)
    SimplestPubSub.publish(topic, :pong)
    refute_receive {:DOWN, ^ref, _, _, _}
  end
end
