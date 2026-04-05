defmodule SoundForge.LLM.ProviderTest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Provider

  describe "changeset/2 - cloud providers" do
    test "valid cloud provider with api_key" do
      changeset =
        Provider.changeset(%Provider{}, %{
          user_id: 1,
          provider_type: :anthropic,
          name: "My Anthropic",
          api_key: "sk-ant-test123"
        })

      assert changeset.valid?
    end

    test "cloud provider requires api_key" do
      changeset =
        Provider.changeset(%Provider{}, %{
          user_id: 1,
          provider_type: :openai,
          name: "My OpenAI"
        })

      refute changeset.valid?
      assert %{api_key: [_]} = errors_on(changeset)
    end

    test "validates all cloud provider types" do
      for type <- [:anthropic, :openai, :azure_openai, :google_gemini] do
        changeset =
          Provider.changeset(%Provider{}, %{
            user_id: 1,
            provider_type: type,
            name: "Test",
            api_key: "test-key"
          })

        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end
  end

  describe "changeset/2 - local providers" do
    test "valid local provider with base_url" do
      changeset =
        Provider.changeset(%Provider{}, %{
          user_id: 1,
          provider_type: :ollama,
          name: "Local Ollama",
          base_url: "http://localhost:11434"
        })

      assert changeset.valid?
    end

    test "local provider requires base_url" do
      changeset =
        Provider.changeset(%Provider{}, %{
          user_id: 1,
          provider_type: :ollama,
          name: "Local Ollama"
        })

      refute changeset.valid?
      assert %{base_url: [_]} = errors_on(changeset)
    end

    test "validates all local provider types" do
      for type <- [:ollama, :lm_studio, :litellm, :custom_openai] do
        changeset =
          Provider.changeset(%Provider{}, %{
            user_id: 1,
            provider_type: type,
            name: "Test",
            base_url: "http://localhost:8000"
          })

        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end
  end

  describe "changeset/2 - general validation" do
    test "requires user_id" do
      changeset = Provider.changeset(%Provider{}, %{provider_type: :anthropic, name: "Test", api_key: "k"})
      refute changeset.valid?
    end

    test "requires provider_type" do
      changeset = Provider.changeset(%Provider{}, %{user_id: 1, name: "Test"})
      refute changeset.valid?
    end

    test "requires name" do
      changeset = Provider.changeset(%Provider{}, %{user_id: 1, provider_type: :anthropic, api_key: "k"})
      refute changeset.valid?
    end

    test "validates health_status inclusion" do
      for status <- [:unknown, :healthy, :degraded, :unreachable] do
        changeset =
          Provider.changeset(%Provider{}, %{
            user_id: 1,
            provider_type: :ollama,
            name: "Test",
            base_url: "http://localhost:11434",
            health_status: status
          })

        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "defaults enabled to true" do
      provider = %Provider{}
      assert provider.enabled == true
    end

    test "defaults health_status to unknown" do
      provider = %Provider{}
      assert provider.health_status == :unknown
    end
  end

  describe "provider type helpers" do
    test "cloud_providers returns cloud types" do
      assert Provider.cloud_providers() == [:anthropic, :openai, :azure_openai, :google_gemini]
    end

    test "local_providers returns local types" do
      assert Provider.local_providers() == [:ollama, :lm_studio, :litellm, :custom_openai]
    end

    test "all_providers returns complete list" do
      assert length(Provider.all_providers()) == 8
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
