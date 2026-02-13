defmodule SoundForgeWeb.Components.JobProgressTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Components.JobProgress

  describe "pipeline_progress/1" do
    test "renders empty pipeline" do
      html =
        render_component(&JobProgress.pipeline_progress/1, pipeline: %{}, track_title: "Test")

      assert html =~ "Test"
      assert html =~ "Download"
      assert html =~ "Separate"
      assert html =~ "Analyze"
      assert html =~ "Queued"
    end

    test "renders downloading stage" do
      pipeline = %{download: %{status: :downloading, progress: 45}}

      html =
        render_component(&JobProgress.pipeline_progress/1,
          pipeline: pipeline,
          track_title: "Song"
        )

      assert html =~ "Song"
      assert html =~ "45%"
      assert html =~ "Processing"
    end

    test "renders completed pipeline" do
      pipeline = %{
        download: %{status: :completed, progress: 100},
        processing: %{status: :completed, progress: 100},
        analysis: %{status: :completed, progress: 100}
      }

      html =
        render_component(&JobProgress.pipeline_progress/1,
          pipeline: pipeline,
          track_title: "Done"
        )

      assert html =~ "Complete"
      assert html =~ "100%"
    end

    test "renders failed stage" do
      pipeline = %{
        download: %{status: :completed, progress: 100},
        processing: %{status: :failed, progress: 0}
      }

      html =
        render_component(&JobProgress.pipeline_progress/1,
          pipeline: pipeline,
          track_title: "Failed"
        )

      assert html =~ "Failed"
    end

    test "renders processing stage progress" do
      pipeline = %{
        download: %{status: :completed, progress: 100},
        processing: %{status: :processing, progress: 67}
      }

      html =
        render_component(&JobProgress.pipeline_progress/1,
          pipeline: pipeline,
          track_title: "Separating"
        )

      assert html =~ "67%"
      assert html =~ "Processing"
    end
  end

  describe "job_progress/1" do
    test "renders single job progress" do
      html =
        render_component(&JobProgress.job_progress/1, job: %{status: :downloading, progress: 50})

      assert html =~ "downloading"
      assert html =~ "50%"
    end
  end
end
