defmodule FedecksCase do
  @moduledoc """
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
    {:ok, pid} = TokenStore.start_link(directory: System.tmp_dir!(), name: name)
    %{filename: file} = :sys.get_state(pid)

    on_exit(fn ->
      if file, do: File.rm(file)
    end)

    {:ok, name: name, token_store: TokenStore.server_name(name)}
  end
end
