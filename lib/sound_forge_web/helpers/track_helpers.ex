defmodule SoundForgeWeb.Helpers.TrackHelpers do
  @moduledoc """
  Shared track listing helpers for LiveView components.

  Centralises the duplicated `list_user_tracks/1` pattern that appeared
  in DashboardLive, DJTabComponent, and DAWTabComponent.
  """

  alias SoundForge.Music

  @doc """
  List tracks for a given scope (user map) or all tracks when no scope.

  Returns an empty list on error rather than raising.
  """
  def list_user_tracks(scope) when is_map(scope) and not is_nil(scope) do
    Music.list_tracks(scope, sort_by: :title)
    |> Enum.uniq_by(& &1.id)
  rescue
    _ -> []
  end

  def list_user_tracks(_) do
    Music.list_tracks(sort_by: :title)
    |> Enum.uniq_by(& &1.id)
  rescue
    _ -> []
  end
end
