defmodule SoundForge.LLM.Provider do
  @moduledoc """
  Schema for LLM provider configurations.

  Each user can configure multiple LLM providers (Anthropic, OpenAI, Ollama, etc.)
  with API keys, base URLs, and provider-specific settings. The `api_key` field
  is stored as `:binary` and will be encrypted at rest in US-102.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @cloud_providers [:anthropic, :openai, :azure_openai, :google_gemini]
  @local_providers [:ollama, :lm_studio, :litellm, :custom_openai]
  @all_providers @cloud_providers ++ @local_providers

  @health_statuses [:unknown, :healthy, :degraded, :unreachable]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "llm_providers" do
    field :provider_type, Ecto.Enum, values: @all_providers
    field :name, :string
    field :api_key, :binary
    field :base_url, :string
    field :default_model, :string
    field :enabled, :boolean, default: true
    field :priority, :integer
    field :last_health_check_at, :utc_datetime
    field :health_status, Ecto.Enum, values: @health_statuses, default: :unknown
    field :config_json, :map, default: %{}

    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an LLM provider configuration.

  Validates:
  - `provider_type`, `name` are always required
  - `api_key` is required for cloud providers (#{inspect(@cloud_providers)})
  - `base_url` is required for local/proxy providers (#{inspect(@local_providers)})
  - `provider_type` must be one of the allowed enum values
  - Unique constraint on `(user_id, provider_type, name)`
  """
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :user_id,
      :provider_type,
      :name,
      :api_key,
      :base_url,
      :default_model,
      :enabled,
      :priority,
      :last_health_check_at,
      :health_status,
      :config_json
    ])
    |> validate_required([:user_id, :provider_type, :name])
    |> validate_inclusion(:provider_type, @all_providers)
    |> validate_inclusion(:health_status, @health_statuses)
    |> validate_conditional_fields()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :provider_type, :name],
      name: :llm_providers_user_id_provider_type_name_index
    )
  end

  @doc """
  Returns the list of cloud provider types that require an API key.
  """
  def cloud_providers, do: @cloud_providers

  @doc """
  Returns the list of local/proxy provider types that require a base URL.
  """
  def local_providers, do: @local_providers

  @doc """
  Returns all supported provider types.
  """
  def all_providers, do: @all_providers

  # Conditional validation: cloud providers require api_key,
  # local/proxy providers require base_url.
  defp validate_conditional_fields(changeset) do
    case get_field(changeset, :provider_type) do
      provider_type when provider_type in @cloud_providers ->
        validate_required(changeset, [:api_key], message: "is required for cloud providers")

      provider_type when provider_type in @local_providers ->
        validate_required(changeset, [:base_url], message: "is required for local/proxy providers")

      _ ->
        changeset
    end
  end
end
