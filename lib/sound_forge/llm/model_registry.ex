defmodule SoundForge.LLM.ModelRegistry do
  @moduledoc """
  GenServer-backed model capability registry with ETS storage.

  Tracks known model capabilities (speed, quality, cost, context window,
  features) and performs periodic health checks on configured providers.
  """
  use GenServer

  alias SoundForge.LLM.Client
  require Logger

  @table :llm_model_registry
  @health_check_interval :timer.minutes(5)

  # -------------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all known model capability entries."
  @spec list_models() :: [map()]
  def list_models do
    :ets.tab2list(@table)
    |> Enum.map(fn {_key, model} -> model end)
  end

  @doc "Returns models that support the given features."
  @spec models_for_task(list(atom())) :: [map()]
  def models_for_task(required_features) when is_list(required_features) do
    required = MapSet.new(required_features)

    list_models()
    |> Enum.filter(fn model ->
      MapSet.subset?(required, MapSet.new(model.features))
    end)
  end

  @doc """
  Returns the best model for a task given preferences.

  ## Options
  - `:prefer` - `:speed`, `:quality`, or `:cost` (default: `:quality`)
  - `:features` - Required features list (default: `[:chat]`)
  - `:provider_types` - Limit to these provider types
  """
  @spec best_model_for(atom(), keyword()) :: map() | nil
  def best_model_for(task_type \\ :chat, opts \\ []) do
    prefer = Keyword.get(opts, :prefer, :quality)
    features = Keyword.get(opts, :features, features_for_task(task_type))
    provider_types = Keyword.get(opts, :provider_types)

    candidates =
      models_for_task(features)
      |> maybe_filter_providers(provider_types)

    case prefer do
      :speed -> Enum.min_by(candidates, &speed_score/1, fn -> nil end)
      :cost -> Enum.min_by(candidates, &cost_score/1, fn -> nil end)
      _ -> Enum.max_by(candidates, &quality_score/1, fn -> nil end)
    end
  end

  @doc "Gets a specific model's capabilities."
  @spec get_model(atom(), String.t()) :: map() | nil
  def get_model(provider_type, model_name) do
    case :ets.lookup(@table, {provider_type, model_name}) do
      [{_key, model}] -> model
      [] -> nil
    end
  end

  @doc "Triggers an immediate health check for all providers of a user."
  def check_health(user_id) do
    GenServer.cast(__MODULE__, {:check_health, user_id})
  end

  # -------------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    seed_known_models()
    schedule_health_check()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:health_check, state) do
    run_health_checks()
    schedule_health_check()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:check_health, user_id}, state) do
    run_health_checks_for_user(user_id)
    {:noreply, state}
  end

  # -------------------------------------------------------------------------
  # Seed data
  # -------------------------------------------------------------------------

  defp seed_known_models do
    models = [
      # Anthropic
      %{provider_type: :anthropic, model: "claude-opus-4-6", speed: :slow, quality: :high, cost: :high, context_window: 200_000, features: [:chat, :vision, :tool_use, :json_mode]},
      %{provider_type: :anthropic, model: "claude-sonnet-4-20250514", speed: :medium, quality: :high, cost: :medium, context_window: 200_000, features: [:chat, :vision, :tool_use, :json_mode]},
      %{provider_type: :anthropic, model: "claude-haiku-4-5-20251001", speed: :fast, quality: :medium, cost: :low, context_window: 200_000, features: [:chat, :vision, :tool_use, :json_mode]},
      # OpenAI
      %{provider_type: :openai, model: "gpt-4o", speed: :medium, quality: :high, cost: :medium, context_window: 128_000, features: [:chat, :vision, :tool_use, :json_mode, :audio]},
      %{provider_type: :openai, model: "gpt-4o-mini", speed: :fast, quality: :medium, cost: :low, context_window: 128_000, features: [:chat, :vision, :tool_use, :json_mode]},
      %{provider_type: :openai, model: "o3", speed: :slow, quality: :high, cost: :high, context_window: 128_000, features: [:chat, :tool_use, :json_mode]},
      # Google Gemini
      %{provider_type: :google_gemini, model: "gemini-2.0-flash", speed: :fast, quality: :medium, cost: :low, context_window: 1_000_000, features: [:chat, :vision, :tool_use, :json_mode, :audio]},
      %{provider_type: :google_gemini, model: "gemini-2.5-pro", speed: :medium, quality: :high, cost: :medium, context_window: 1_000_000, features: [:chat, :vision, :tool_use, :json_mode, :audio]},
      # Ollama (local, free)
      %{provider_type: :ollama, model: "llama3.2", speed: :medium, quality: :medium, cost: :free, context_window: 128_000, features: [:chat, :tool_use]},
      %{provider_type: :ollama, model: "mistral", speed: :fast, quality: :medium, cost: :free, context_window: 32_000, features: [:chat]},
      %{provider_type: :ollama, model: "codellama", speed: :medium, quality: :medium, cost: :free, context_window: 16_000, features: [:chat]},
      # Azure mirrors OpenAI
      %{provider_type: :azure_openai, model: "gpt-4o", speed: :medium, quality: :high, cost: :medium, context_window: 128_000, features: [:chat, :vision, :tool_use, :json_mode]}
    ]

    Enum.each(models, fn model ->
      :ets.insert(@table, {{model.provider_type, model.model}, model})
    end)
  end

  # -------------------------------------------------------------------------
  # Health checks
  # -------------------------------------------------------------------------

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp run_health_checks do
    # Check system providers only (user-specific checks triggered on demand)
    providers = SoundForge.LLM.Providers.SystemProviders.list_system_providers()

    Enum.each(providers, fn provider ->
      Task.start(fn ->
        result = Client.test_connection(provider)
        status = if result == :ok, do: :healthy, else: :unreachable

        # System providers aren't persisted, so just log
        Logger.debug("Health check #{provider.provider_type}: #{status}")
      end)
    end)
  rescue
    _ -> :ok
  end

  defp run_health_checks_for_user(user_id) do
    providers = SoundForge.LLM.Providers.get_enabled_providers(user_id)

    Enum.each(providers, fn provider ->
      Task.start(fn ->
        result = Client.test_connection(provider)
        status = if result == :ok, do: :healthy, else: :unreachable
        SoundForge.LLM.Providers.update_health(provider, status)
      end)
    end)
  rescue
    _ -> :ok
  end

  # -------------------------------------------------------------------------
  # Scoring helpers
  # -------------------------------------------------------------------------

  defp speed_score(%{speed: :fast}), do: 0
  defp speed_score(%{speed: :medium}), do: 1
  defp speed_score(%{speed: :slow}), do: 2
  defp speed_score(_), do: 3

  defp quality_score(%{quality: :high}), do: 3
  defp quality_score(%{quality: :medium}), do: 2
  defp quality_score(%{quality: :low}), do: 1
  defp quality_score(_), do: 0

  defp cost_score(%{cost: :free}), do: 0
  defp cost_score(%{cost: :low}), do: 1
  defp cost_score(%{cost: :medium}), do: 2
  defp cost_score(%{cost: :high}), do: 3
  defp cost_score(_), do: 4

  defp features_for_task(:chat), do: [:chat]
  defp features_for_task(:analysis), do: [:chat, :json_mode]
  defp features_for_task(:vision), do: [:chat, :vision]
  defp features_for_task(:tool_use), do: [:chat, :tool_use]
  defp features_for_task(_), do: [:chat]

  defp maybe_filter_providers(models, nil), do: models

  defp maybe_filter_providers(models, types) do
    type_set = MapSet.new(types)
    Enum.filter(models, &MapSet.member?(type_set, &1.provider_type))
  end
end
