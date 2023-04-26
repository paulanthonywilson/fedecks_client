defmodule FedecksClient.CompileEnv do
  @moduledoc false
  _doc = """
  Convenience module for determining the compilation environment, specifically
  using the values of `Mix.env/0` and `Mix.target/0` to figure out if we are running tests
  so will want to substitute in some choice Mox "mocks" in appropriate places.

  See https://furlough.merecomplexities.com/elixir/tdd/mocks/2023/03/24/elixir-mock-stub-fake-testing-seams-a-modest-proposal.html for
  the point of all this.

  """

  @mix_env Mix.env()
  @mix_target Mix.target()

  @doc """
  Are we actually developing this library and running tests? `true` if and only if
  `Mix.env/0` is `:test` and `Mix.target/0` is _not_ `:elixir_ls`.

  Note that `Mix.target/0` will only return `elixir_ls` if it is configured to do so. This
  can be done VSCode in the extension settings and is not crucial.

  Optionally passing in the values is for the purposes of testing this function.
  """
  def test?(mix_env \\ @mix_env, mix_target \\ @mix_target)
  def test?(:test, :elixir_ls), do: false
  def test?(:test, _), do: true
  def test?(_, _), do: false
end
