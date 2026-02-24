defmodule SoundForge.Audio.AnalysisHelpers do
  @moduledoc """
  Helper functions for extracting structural analysis data from analysis results.
  """

  @doc "Extract structure segments from analysis result."
  def structure_segments(nil), do: []
  def structure_segments(%{features: nil}), do: []
  def structure_segments(%{features: features}) do
    get_in(features, ["structure", "segments"]) || []
  end

  @doc "Extract recommended loop points from analysis result."
  def recommended_loop_points(nil), do: []
  def recommended_loop_points(%{features: nil}), do: []
  def recommended_loop_points(%{features: features}) do
    get_in(features, ["loop_points", "recommended"]) || []
  end

  @doc "Extract all loop points from analysis result."
  def all_loop_points(nil), do: []
  def all_loop_points(%{features: nil}), do: []
  def all_loop_points(%{features: features}) do
    get_in(features, ["loop_points", "all"]) || []
  end

  @doc "Extract arrangement markers from analysis result."
  def arrangement_markers(nil), do: []
  def arrangement_markers(%{features: nil}), do: []
  def arrangement_markers(%{features: features}) do
    features["arrangement_markers"] || []
  end

  @doc "Extract energy curve from analysis result."
  def energy_curve(nil), do: %{}
  def energy_curve(%{features: nil}), do: %{}
  def energy_curve(%{features: features}) do
    features["energy_curve"] || %{}
  end

  @doc "Extract bar times from analysis result."
  def bar_times(nil), do: []
  def bar_times(%{features: nil}), do: []
  def bar_times(%{features: features}) do
    get_in(features, ["structure", "bar_times"]) || []
  end

  @doc "Extract time signature from analysis result."
  def time_signature(nil), do: %{"beats_per_bar" => 4, "confidence" => 0.0}
  def time_signature(%{features: nil}), do: %{"beats_per_bar" => 4, "confidence" => 0.0}
  def time_signature(%{features: features}) do
    get_in(features, ["structure", "time_signature"]) || %{"beats_per_bar" => 4, "confidence" => 0.0}
  end
end
