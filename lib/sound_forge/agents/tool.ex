defmodule SoundForge.Agents.Tool do
  @moduledoc """
  Represents a callable tool available to agents during execution.

  Tools are Elixir functions that agents can invoke for structured side-effects
  (database lookups, file reads, API calls) without leaving the agent execution
  pipeline.

  ## Example

      %Tool{
        name: "get_track_metadata",
        description: "Retrieves metadata for a given track ID",
        params_schema: %{
          "type" => "object",
          "properties" => %{
            "track_id" => %{"type" => "string"}
          },
          "required" => ["track_id"]
        },
        handler: fn %{"track_id" => id} ->
          case SoundForge.Music.get_track(id) do
            nil -> {:error, :not_found}
            track -> {:ok, track}
          end
        end
      }
  """

  @enforce_keys [:name, :description, :params_schema, :handler]
  defstruct [:name, :description, :params_schema, :handler]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          params_schema: map(),
          handler: (map() -> {:ok, term()} | {:error, term()})
        }

  @doc """
  Calls the tool handler with the given params map.

  Wraps bare exceptions in `{:error, _}` so callers always get a consistent
  return shape.
  """
  @spec call(t(), map()) :: {:ok, term()} | {:error, term()}
  def call(%__MODULE__{handler: handler}, params) when is_map(params) do
    handler.(params)
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc """
  Serialises the tool to the OpenAI-compatible function-calling format.
  """
  @spec to_llm_spec(t()) :: map()
  def to_llm_spec(%__MODULE__{name: name, description: desc, params_schema: schema}) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => desc,
        "parameters" => schema
      }
    }
  end
end
