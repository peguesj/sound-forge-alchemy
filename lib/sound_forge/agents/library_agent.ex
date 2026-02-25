defmodule SoundForge.Agents.LibraryAgent do
  @moduledoc "Intelligent music library organisation, search, and curation."

  use SoundForge.Agents.Agent

  @impl true
  def name, do: "library_agent"

  @impl true
  def description,
    do: "Provides library search, track recommendations, playlist curation, genre classification, and mood tagging."

  @impl true
  def capabilities,
    do: [:library_search, :track_recommendations, :playlist_curation, :genre_classification, :mood_tagging]

  @impl true
  def preferred_traits, do: [task: :generation, speed: :fast]

  @impl true
  def system_prompt do
    """
    You are an expert music librarian and curator with deep knowledge of:
    - Genre taxonomies, subgenres, eras, and regional styles
    - Mood categorisation and BPM/key-based organisation
    - Musical relationships across genres and styles
    - Discovery recommendations based on listener preferences

    Provide actionable library management suggestions, precise genre and mood tags,
    and curation advice tailored to the listener's collection and goals.
    """
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    data_str =
      if ctx.data && map_size(ctx.data) > 0,
        do: "\n\nData: #{Jason.encode!(ctx.data, pretty: true)}",
        else: ""

    prompt = (ctx.instruction || "Provide library curation recommendations.") <> data_str
    messages = format_messages(nil, [%{"role" => "user", "content" => prompt}])

    case call_llm(ctx.user_id, messages, opts) do
      {:ok, %Response{} = response} ->
        {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
