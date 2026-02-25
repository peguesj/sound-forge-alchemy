defmodule SoundForge.LLM.Router do
  @moduledoc """
  Intelligent task-to-model router with fallback chains.

  Selects the best available model for a given task based on requirements,
  user preferences, and provider health. Supports fallback chains: if the
  primary provider fails, automatically retries with the next best option.

  LiteLLM is prioritized when configured, as it can proxy to many providers.
  """

  alias SoundForge.LLM.{Client, ModelRegistry, Providers, Response}
  require Logger

  @max_fallback_attempts 4

  @type task_spec :: %{
          optional(:task_type) => atom(),
          optional(:prefer) => :speed | :quality | :cost,
          optional(:features) => [atom()],
          optional(:model) => String.t(),
          optional(:provider_type) => atom(),
          optional(:system) => String.t(),
          optional(:max_tokens) => integer(),
          optional(:temperature) => float()
        }

  @doc """
  Routes a chat request to the best available provider for the user.

  Builds a fallback chain of providers, tries each in order until one succeeds.

  ## Parameters
  - `user_id` - The user making the request
  - `messages` - List of message maps with :role and :content
  - `task_spec` - Map with routing preferences (see @type task_spec)

  ## Returns
  - `{:ok, %Response{}}` on success
  - `{:error, :no_providers_available}` if no providers configured
  - `{:error, {:all_providers_failed, errors}}` if all fallbacks exhausted
  """
  @spec route(term(), list(), task_spec()) :: {:ok, Response.t()} | {:error, term()}
  def route(user_id, messages, task_spec \\ %{}) do
    providers = build_provider_chain(user_id, task_spec)

    if providers == [] do
      {:error, :no_providers_available}
    else
      try_providers(providers, messages, task_spec, [])
    end
  end

  @doc """
  Routes to a specific provider type, falling back to alternatives if it fails.
  """
  @spec route_to(term(), atom(), list(), task_spec()) :: {:ok, Response.t()} | {:error, term()}
  def route_to(user_id, provider_type, messages, task_spec \\ %{}) do
    route(user_id, messages, Map.put(task_spec, :provider_type, provider_type))
  end

  # ---------------------------------------------------------------------------
  # Provider chain building
  # ---------------------------------------------------------------------------

  defp build_provider_chain(user_id, task_spec) do
    all_providers = Providers.all_available_providers(user_id)

    # If specific provider requested, put it first
    {primary, rest} =
      case Map.get(task_spec, :provider_type) do
        nil ->
          {[], all_providers}

        type ->
          {primary, rest} = Enum.split_with(all_providers, &(&1.provider_type == type))
          {primary, rest}
      end

    # Prioritize LiteLLM in the fallback chain
    {litellm, others} = Enum.split_with(rest, &(&1.provider_type == :litellm))

    # Sort remaining by priority and health
    sorted_others =
      others
      |> Enum.sort_by(fn p ->
        health_penalty = if p.health_status == :unreachable, do: 1000, else: 0
        (p.priority || 999) + health_penalty
      end)

    chain = primary ++ litellm ++ sorted_others

    # Filter by capability if task features specified
    features = Map.get(task_spec, :features, [])

    if features != [] do
      Enum.filter(chain, fn provider ->
        model_name = Map.get(task_spec, :model) || provider.default_model
        model_info = model_name && ModelRegistry.get_model(provider.provider_type, model_name)

        if model_info do
          required = MapSet.new(features)
          MapSet.subset?(required, MapSet.new(model_info.features))
        else
          # Unknown model, allow it through (might work)
          true
        end
      end)
    else
      chain
    end
    |> Enum.take(@max_fallback_attempts)
  end

  # ---------------------------------------------------------------------------
  # Fallback execution
  # ---------------------------------------------------------------------------

  defp try_providers([], _messages, _task_spec, errors) do
    {:error, {:all_providers_failed, Enum.reverse(errors)}}
  end

  defp try_providers([provider | rest], messages, task_spec, errors) do
    opts = build_opts(provider, task_spec)

    Logger.debug(
      "LLM Router: trying #{provider.provider_type} (#{provider.name}) model=#{opts[:model]}"
    )

    case Client.chat(provider, messages, opts) do
      {:ok, %Response{}} = success ->
        # Update health on success
        if provider.id, do: Providers.update_health(provider, :healthy)
        success

      {:error, reason} = _error ->
        Logger.warning(
          "LLM Router: #{provider.provider_type} failed: #{inspect(reason)}, trying next..."
        )

        if provider.id, do: Providers.update_health(provider, :unreachable)
        try_providers(rest, messages, task_spec, [{provider.provider_type, reason} | errors])
    end
  end

  defp build_opts(provider, task_spec) do
    opts = []
    opts = if task_spec[:model], do: [{:model, task_spec.model} | opts], else: opts
    opts = if task_spec[:system], do: [{:system, task_spec.system} | opts], else: opts
    opts = if task_spec[:max_tokens], do: [{:max_tokens, task_spec.max_tokens} | opts], else: opts

    opts =
      if task_spec[:temperature],
        do: [{:temperature, task_spec.temperature} | opts],
        else: opts

    # Use provider's default model if no override
    unless Keyword.has_key?(opts, :model) do
      [{:model, provider.default_model} | opts]
    else
      opts
    end
  end
end
