defmodule SoundForge.LLM.Adapters.GoogleGeminiTest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.GoogleGemini

  describe "chat/3" do
    test "returns missing_api_key when api_key is nil" do
      provider = %{api_key: nil, base_url: nil, default_model: nil}
      assert {:error, :missing_api_key} = GoogleGemini.chat(provider, [])
    end

    test "returns missing_api_key when api_key is false" do
      provider = %{api_key: false, base_url: nil, default_model: nil}
      assert {:error, :missing_api_key} = GoogleGemini.chat(provider, [])
    end
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(GoogleGemini)
    end

    test "implements Client behaviour" do
      behaviours =
        GoogleGemini.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert SoundForge.LLM.Client in behaviours
    end

    test "chat/3 function is exported" do
      assert {:chat, 3} in GoogleGemini.__info__(:functions)
    end

    test "chat/2 function is exported (default opts)" do
      assert {:chat, 2} in GoogleGemini.__info__(:functions)
    end
  end
end
