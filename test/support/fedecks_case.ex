defmodule FedecksCase do
  @moduledoc false
  _doc = """
  Sets up a name / topic and a token store.
  """

  use ExUnit.CaseTemplate

  alias FedecksClient.TokenStore

  using do
    quote do
      import FedecksHelpers
    end
  end

  setup do
    name = FedecksHelpers.generate_unique_name()
    directory = "#{System.tmp_dir()}/#{name}"

    {:ok, _pid} = start_supervised({TokenStore, directory: directory, name: name})

    on_exit(fn ->
      File.rm_rf(directory)
    end)

    {:ok, name: name, token_store: TokenStore.server_name(name)}
  end
end
