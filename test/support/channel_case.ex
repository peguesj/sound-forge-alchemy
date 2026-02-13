defmodule SoundForgeWeb.ChannelCase do
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
