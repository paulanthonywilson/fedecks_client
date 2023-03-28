defmodule FedecksClient.CompileEnvTest do
  use ExUnit.Case
  alias FedecksClient.CompileEnv

  test "Not test?() in dev or prod Mix.env()" do
    for env <- [:dev, :prod], target <- [nil, :rpi0, :host, :elixir_ls] do
      refute CompileEnv.test?(env, target)
      refute CompileEnv.test?(env, target)
      refute CompileEnv.test?(env, target)
      refute CompileEnv.test?(env, target)
    end
  end

  test "test?() if in test Mix.env() when target is other than `:elxir_ls`" do
    for target <- [nil, :rpi0, :host] do
      assert CompileEnv.test?(:test, target)
    end
  end

  test "Not test?() when `Mix.target()` is `:elixir_ls`" do
    refute CompileEnv.test?(:test, :elixir_ls)
  end
end
