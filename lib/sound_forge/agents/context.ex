defmodule SoundForge.Agents.Context do
  @moduledoc """
  Execution context passed to agent `run/2` callbacks.

  Bundles the instruction, relevant data, available tools, and prior conversation
  history so agents have everything they need to complete a task.

  ## Fields

  - `:user_id` - ID of the user who triggered the agent run (used for LLM routing)
  - `:track_id` - optional single track relevant to the task
  - `:track_ids` - optional list of track IDs
  - `:instruction` - natural-language instruction from the user or orchestrator
  - `:data` - arbitrary map of additional domain data (analysis results, metadata, etc.)
  - `:tools` - list of `%SoundForge.Agents.Tool{}` available during execution
  - `:conversation_history` - prior messages for multi-turn interactions
  - `:messages` - accumulator for current-turn messages (default `[]`)
  """

  alias SoundForge.Agents.Tool

  @enforce_keys [:instruction]
  defstruct [
    :user_id,
    :track_id,
    :track_ids,
    :instruction,
    :data,
    :tools,
    :conversation_history,
    messages: []
  ]

  @type t :: %__MODULE__{
          user_id: term() | nil,
          track_id: String.t() | nil,
          track_ids: [String.t()] | nil,
          instruction: String.t(),
          data: map() | nil,
          tools: [Tool.t()] | nil,
          conversation_history: [map()] | nil,
          messages: [map()]
        }

  @doc "Builds a new context with the given instruction and optional overrides."
  @spec new(String.t(), keyword()) :: t()
  def new(instruction, opts \\ []) when is_binary(instruction) do
    struct!(__MODULE__, Keyword.merge([instruction: instruction, messages: []], opts))
  end

  @doc "Appends a message map to the context's `:messages` list."
  @spec append_message(t(), map()) :: t()
  def append_message(%__MODULE__{messages: msgs} = ctx, message) when is_map(message) do
    %{ctx | messages: msgs ++ [message]}
  end

  @doc """
  Returns tools formatted as LLM API tool-call specs, or `nil` when no tools present.
  """
  @spec llm_tool_specs(t()) :: [map()] | nil
  def llm_tool_specs(%__MODULE__{tools: nil}), do: nil
  def llm_tool_specs(%__MODULE__{tools: []}), do: nil

  def llm_tool_specs(%__MODULE__{tools: tools}) do
    Enum.map(tools, &Tool.to_llm_spec/1)
  end
end
