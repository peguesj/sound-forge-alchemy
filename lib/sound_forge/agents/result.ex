defmodule SoundForge.Agents.Result do
  @moduledoc """
  Represents the outcome of an agent execution.

  ## Fields

  - `:agent` - module that produced this result
  - `:content` - primary text output from the LLM
  - `:data` - optional map of structured data
  - `:usage` - optional map with token-usage info from the LLM
  - `:error` - `nil` on success; a string or term on failure
  - `:success?` - `true` when the agent completed without error
  """

  @enforce_keys [:agent]
  defstruct [
    :agent,
    :content,
    :data,
    :usage,
    :error,
    success?: true
  ]

  @type t :: %__MODULE__{
          agent: module() | atom(),
          content: String.t() | nil,
          data: map() | nil,
          usage: map() | nil,
          error: term() | nil,
          success?: boolean()
        }

  @doc "Builds a successful result. Accepts `:data` and `:usage` in opts."
  @spec ok(module() | atom(), String.t() | nil, keyword()) :: t()
  def ok(agent, content, opts \\ []) do
    struct!(__MODULE__, Keyword.merge([agent: agent, content: content, success?: true], opts))
  end

  @doc "Builds a failure result."
  @spec error(module() | atom(), term()) :: t()
  def error(agent, reason) do
    %__MODULE__{agent: agent, error: reason, success?: false}
  end

  @doc "Returns `true` when the result indicates success."
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{success?: s}), do: s

  @doc "Returns `true` when the result indicates failure."
  @spec failure?(t()) :: boolean()
  def failure?(%__MODULE__{success?: s}), do: not s
end
