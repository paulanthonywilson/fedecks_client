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
    name = String.to_atom("#{:rand.uniform(999)}-#{inspect(self())}")
    token_store_name = :"#{name}.TokenStore"
    {:ok, pid} = TokenStore.start_link({System.tmp_dir!(), token_store_name})
    %{filename: file} = :sys.get_state(pid)

    on_exit(fn ->
      if file, do: File.rm(file)
    end)

    {:ok, name: name, token_store: token_store_name}
  end
end
