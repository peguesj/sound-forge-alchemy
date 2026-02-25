defmodule SoundForge.LLM.Response do
  @moduledoc """
  Normalized response struct for all LLM provider interactions.
  """

  @type t :: %__MODULE__{
          content: String.t() | nil,
          model: String.t() | nil,
          usage: map(),
          finish_reason: String.t() | nil,
          raw_response: map()
        }

  defstruct [:content, :model, :finish_reason, usage: %{}, raw_response: %{}]
end
