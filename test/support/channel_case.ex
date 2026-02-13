defmodule SoundForgeWeb.ChannelCase do
  @moduledoc """
  Test case template for Phoenix channel tests with Ecto sandbox setup.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import SoundForgeWeb.ChannelCase

      @endpoint SoundForgeWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
