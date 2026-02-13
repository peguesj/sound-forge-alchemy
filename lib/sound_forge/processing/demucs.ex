defmodule SoundForge.Processing.Demucs do
  @moduledoc """
  Configuration module for available Demucs stem separation models.
  """

  @models [
    %{
      name: "htdemucs",
      description:
        "Hybrid Transformer Demucs - default 4-stem model (vocals, drums, bass, other)",
      stems: 4
    },
    %{
      name: "htdemucs_ft",
      description: "Fine-tuned Hybrid Transformer Demucs - higher quality, slower",
      stems: 4
    },
    %{
      name: "htdemucs_6s",
      description: "6-stem model (vocals, drums, bass, guitar, piano, other)",
      stems: 6
    },
    %{
      name: "mdx_extra",
      description: "MDX-Net Extra - alternative architecture, good for vocals",
      stems: 4
    }
  ]

  @doc """
  Returns the list of available Demucs models.

  Each model is a map with `:name`, `:description`, and `:stems` keys.
  """
  @spec list_models() :: [map()]
  def list_models, do: @models
end
