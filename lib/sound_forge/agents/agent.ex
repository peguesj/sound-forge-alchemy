defmodule SoundForge.Agents.Agent do
  @moduledoc """
  Behaviour and `use` macro for SoundForge specialist agents.

  Each agent is a functional module (not a process) that:
  - Declares its capability profile
  - Receives a `%Context{}` and returns `{:ok, %Result{}}` or `{:error, reason}`
  - Routes LLM calls through `SoundForge.LLM.Router` using its `preferred_traits/0`

  ## Implementing an agent

      defmodule SoundForge.Agents.TrackAnalysisAgent do
        use SoundForge.Agents.Agent

        @impl true
        def name, do: "track_analysis_agent"

        @impl true
        def description, do: "Analyses harmonic and rhythmic content"

        @impl true
        def capabilities, do: [:track_analysis, :key_detection]

        @impl true
        def preferred_traits, do: [task: :analysis, speed: :balanced]

        @impl true
        def system_prompt, do: "You are an expert music analyst..."

        @impl true
        def run(%Context{} = ctx, opts) do
          messages = format_messages(nil, [%{"role" => "user", "content" => ctx.instruction}])

          case call_llm(ctx.user_id, messages, opts) do
            {:ok, %SoundForge.LLM.Response{} = response} ->
              {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end

  ## Injected helpers (from `use SoundForge.Agents.Agent`)

  - `call_llm/3` — `call_llm(user_id, messages, opts)` — routes through the
    LLM Router using this agent's `preferred_traits/0` converted to a task_spec.
  - `call_llm_with_provider/4` — forces a specific `provider_type`.
  - `format_messages/2` — builds a message list, prepending the system prompt.
  """

  alias SoundForge.Agents.{Context, Result}
  alias SoundForge.LLM.{Response, Router}

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback capabilities() :: [atom()]
  @callback preferred_traits() :: keyword()
  @callback system_prompt() :: String.t()
  @callback run(Context.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour SoundForge.Agents.Agent

      alias SoundForge.Agents.{Context, Result}
      alias SoundForge.LLM.{Response, Router}

      @doc """
      Routes an LLM call using this agent's `preferred_traits/0`.

      `user_id` is passed to the Router so it can select from the user's
      configured providers (with system-env fallbacks when user_id is nil).
      """
      @spec call_llm(term(), [map()], keyword()) ::
              {:ok, Response.t()} | {:error, term()}
      def call_llm(user_id, messages, opts \\ []) do
        task_spec = build_task_spec(preferred_traits(), opts)
        Router.route(user_id, messages, task_spec)
      end

      @doc """
      Routes an LLM call forcing a specific `provider_type` atom.
      """
      @spec call_llm_with_provider(term(), atom(), [map()], keyword()) ::
              {:ok, Response.t()} | {:error, term()}
      def call_llm_with_provider(user_id, provider_type, messages, opts \\ []) do
        task_spec =
          preferred_traits()
          |> build_task_spec(opts)
          |> Map.put(:provider_type, provider_type)

        Router.route(user_id, messages, task_spec)
      end

      @doc """
      Builds the message list for an LLM call, prepending the system prompt.

      - `nil` → uses `system_prompt/0`
      - `:none` → omits the system message entirely
      - binary → uses the supplied string as the system message
      """
      @spec format_messages(String.t() | nil | :none, [map()]) :: [map()]
      def format_messages(system_content, user_messages) when is_list(user_messages) do
        sys =
          case system_content do
            :none -> []
            nil -> [%{"role" => "system", "content" => system_prompt()}]
            custom when is_binary(custom) -> [%{"role" => "system", "content" => custom}]
          end

        sys ++ user_messages
      end

      # Converts keyword traits + opts into a task_spec map for the Router.
      defp build_task_spec(traits, opts) do
        base = %{}

        base
        |> put_if(traits[:task], :task_type)
        |> put_if(speed_to_prefer(traits[:speed]), :prefer)
        |> put_if(opts[:model], :model)
        |> put_if(opts[:max_tokens], :max_tokens)
        |> put_if(opts[:temperature], :temperature)
        |> put_if(opts[:features], :features)
      end

      defp put_if(map, nil, _key), do: map
      defp put_if(map, value, key), do: Map.put(map, key, value)

      defp speed_to_prefer(:fast), do: :speed
      defp speed_to_prefer(:slow), do: :quality
      defp speed_to_prefer(_), do: nil
    end
  end
end
