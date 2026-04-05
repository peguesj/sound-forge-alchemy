defmodule SoundForgeWeb.PipelineTrackerRenderingTest do
  @moduledoc "Tests for PipelineTracker rendering with various pipeline states."
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.PipelineTracker

  describe "render with empty pipelines" do
    test "renders empty tracker" do
      html = render_component(PipelineTracker, %{
        id: "pt-empty",
        pipelines: %{}
      })

      assert is_binary(html)
    end
  end

  describe "render with active pipeline" do
    test "renders downloading pipeline" do
      pipelines = %{
        "track-1" => %{
          track_id: "track-1",
          stages: %{
            download: %{status: :downloading, progress: 50},
            processing: %{status: :queued, progress: 0},
            analysis: %{status: :queued, progress: 0}
          },
          triggered_stages: [:download, :processing, :analysis]
        }
      }

      html = render_component(PipelineTracker, %{
        id: "pt-downloading",
        pipelines: pipelines
      })

      assert is_binary(html)
    end

    test "renders processing pipeline" do
      pipelines = %{
        "track-2" => %{
          track_id: "track-2",
          stages: %{
            download: %{status: :completed, progress: 100},
            processing: %{status: :processing, progress: 75},
            analysis: %{status: :queued, progress: 0}
          },
          triggered_stages: [:download, :processing, :analysis]
        }
      }

      html = render_component(PipelineTracker, %{
        id: "pt-processing",
        pipelines: pipelines
      })

      assert is_binary(html)
    end

    test "renders completed pipeline" do
      pipelines = %{
        "track-3" => %{
          track_id: "track-3",
          stages: %{
            download: %{status: :completed, progress: 100},
            processing: %{status: :completed, progress: 100},
            analysis: %{status: :completed, progress: 100}
          },
          triggered_stages: [:download, :processing, :analysis]
        }
      }

      html = render_component(PipelineTracker, %{
        id: "pt-complete",
        pipelines: pipelines
      })

      assert is_binary(html)
    end

    test "renders failed pipeline" do
      pipelines = %{
        "track-4" => %{
          track_id: "track-4",
          stages: %{
            download: %{status: :completed, progress: 100},
            processing: %{status: :failed, progress: 30},
            analysis: %{status: :queued, progress: 0}
          },
          triggered_stages: [:download, :processing]
        }
      }

      html = render_component(PipelineTracker, %{
        id: "pt-failed",
        pipelines: pipelines
      })

      assert is_binary(html)
    end
  end

  describe "render with multiple pipelines" do
    test "renders two active pipelines" do
      pipelines = %{
        "t1" => %{
          track_id: "t1",
          stages: %{download: %{status: :downloading, progress: 30}},
          triggered_stages: [:download]
        },
        "t2" => %{
          track_id: "t2",
          stages: %{download: %{status: :completed, progress: 100}, processing: %{status: :processing, progress: 60}},
          triggered_stages: [:download, :processing]
        }
      }

      html = render_component(PipelineTracker, %{
        id: "pt-multi",
        pipelines: pipelines
      })

      assert is_binary(html)
    end
  end

  describe "render with open state" do
    test "renders tracker in open state" do
      html = render_component(PipelineTracker, %{
        id: "pt-open",
        pipelines: %{},
        open: true
      })

      assert is_binary(html)
    end
  end

  describe "render with partial pipeline" do
    test "renders download-only pipeline" do
      pipelines = %{
        "track-dl" => %{
          track_id: "track-dl",
          stages: %{download: %{status: :completed, progress: 100}},
          triggered_stages: [:download]
        }
      }

      html = render_component(PipelineTracker, %{
        id: "pt-dl-only",
        pipelines: pipelines
      })

      assert is_binary(html)
    end
  end
end
