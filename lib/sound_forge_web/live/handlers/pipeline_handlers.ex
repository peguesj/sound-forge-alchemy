defmodule SoundForgeWeb.Live.Handlers.PipelineHandlers do
  @moduledoc """
  Download, processing, analysis, upload, and pipeline lifecycle
  handle_event/handle_info clauses for DashboardLive.

  Extracted via `use SoundForgeWeb.Live.Handlers.PipelineHandlers` in DashboardLive.
  All definitions are injected into the calling module's namespace.
  """

  defmacro __using__(_opts) do
    quote do
      # ── Module attributes ────────────────────────────────────────────────

      @valid_pipeline_stages ~w(download processing analysis)a
      @pipeline_stages [:download, :processing, :analysis]

      # ── Download Events ────────────────────────────────��──────────────────

      def handle_event("download_track", %{"id" => id}, socket) do
        user_id = socket.assigns[:current_user_id]

        with {:ok, track} <- fetch_owned_track(socket, id),
             true <- is_binary(track.spotify_url),
             false <- has_completed_download?(id) do
          {:ok, download_job} =
            SoundForge.Music.create_download_job(%{track_id: track.id, status: :queued})

          %{
            "track_id" => track.id,
            "spotify_url" => track.spotify_url,
            "quality" => SoundForge.Settings.get(user_id, :download_quality),
            "job_id" => download_job.id
          }
          |> SoundForge.Jobs.DownloadWorker.new()
          |> Oban.insert()

          maybe_subscribe(socket, track.id)

          pipelines = socket.assigns.pipelines
          pipeline = Map.get(pipelines, track.id, %{})
          updated_pipeline = Map.put(pipeline, :download, %{status: :queued, progress: 0})
          pipelines = Map.put(pipelines, track.id, updated_pipeline)

          {:noreply,
           socket
           |> push_notification(:info, "Download Started", "Downloading \"#{track.title}\"...", %{
             track_id: track.id
           })
           |> assign(:pipelines, pipelines)
           |> put_flash(:info, "Download started for #{track.title}")}
        else
          false ->
            {:noreply, put_flash(socket, :error, "Track has no Spotify URL")}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Track not found")}

          true ->
            {:noreply, put_flash(socket, :info, "Track has already been downloaded.")}
        end
      end

      def handle_event("toggle_auto_download", _params, socket) do
        {:noreply, update(socket, :auto_download, &(!&1))}
      end

      # ── Processing / Engine Events ────────────────────────────���───────────

      def handle_event("process_track", %{"id" => id}, socket) do
        user_id = socket.assigns[:current_user_id]
        engine = socket.assigns.selected_engine
        preview = socket.assigns.preview_mode

        lalalai_opts =
          if engine == "lalalai" do
            mode = socket.assigns.lalalai_mode
            base = [lalalai_mode: mode]

            case mode do
              "multistem" ->
                stems = socket.assigns.multistem_selection |> MapSet.to_list()
                base ++ [multistem_stems: stems]

              "voice_clean" ->
                base ++ [noise_level: socket.assigns.noise_level]

              "voice_change" ->
                base ++
                  [
                    voice_pack_id: socket.assigns.voice_pack_id,
                    accent: socket.assigns.accent
                  ]

              "demuser" ->
                base ++ [dereverb: socket.assigns.dereverb]

              _ ->
                base
            end
          else
            []
          end

        with {:ok, track} <- fetch_owned_track(socket, id),
             {:ok, job} <-
               start_processing(
                 track.id,
                 user_id,
                 [engine: engine, preview: preview] ++ lalalai_opts
               ) do
          maybe_subscribe(socket, track.id)

          pipelines = socket.assigns.pipelines
          pipeline = Map.get(pipelines, track.id, %{})

          updated_pipeline =
            Map.put(pipeline, :processing, %{
              status: :queued,
              progress: 0,
              job_id: job.id,
              engine: job.engine
            })

          pipelines = Map.put(pipelines, track.id, updated_pipeline)

          {:noreply,
           socket
           |> assign(:pipelines, pipelines)
           |> put_flash(:info, "Processing #{track.title}...")}
        else
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Track not found")}

          {:error, :no_completed_download} ->
            {:noreply, put_flash(socket, :error, "Download the track first before processing")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not start processing")}
        end
      end

      def handle_event("select_engine", %{"engine" => "lalalai"}, socket) do
        user_id = socket.assigns[:current_user_id]

        if SoundForge.Audio.LalalAI.configured_for_user?(user_id) do
          {:noreply, assign(socket, :selected_engine, "lalalai")}
        else
          {:noreply,
           socket
           |> assign(:show_lalalai_modal, true)
           |> assign(:lalalai_modal_expanded, false)
           |> assign(:lalalai_modal_key_input, "")
           |> assign(:lalalai_modal_testing, false)
           |> assign(:lalalai_modal_test_result, nil)}
        end
      end

      def handle_event("select_engine", %{"engine" => "demucs"}, socket) do
        {:noreply, assign(socket, :selected_engine, "demucs")}
      end

      def handle_event("select_lalalai_mode", %{"mode" => mode}, socket) do
        {:noreply, assign(socket, :lalalai_mode, mode)}
      end

      def handle_event("toggle_multistem", %{"stem" => stem}, socket) do
        selection = socket.assigns.multistem_selection

        updated =
          if MapSet.member?(selection, stem),
            do: MapSet.delete(selection, stem),
            else: MapSet.put(selection, stem)

        {:noreply, assign(socket, :multistem_selection, updated)}
      end

      def handle_event("set_noise_level", %{"level" => level}, socket) do
        {:noreply, assign(socket, :noise_level, String.to_integer(level))}
      end

      def handle_event("select_voice_pack", %{"pack_id" => pack_id}, socket) do
        {:noreply, assign(socket, :voice_pack_id, pack_id)}
      end

      def handle_event("set_accent", %{"value" => value}, socket) do
        {:noreply, assign(socket, :accent, String.to_float(value))}
      end

      def handle_event("toggle_dereverb", _params, socket) do
        {:noreply, update(socket, :dereverb, &(!&1))}
      end

      def handle_event("toggle_preview", _params, socket) do
        {:noreply, assign(socket, :preview_mode, !socket.assigns.preview_mode)}
      end

      # ── lalal.ai Modal Events ─────────────────────────────���───────────────

      def handle_event("close_lalalai_modal", _params, socket) do
        {:noreply, assign(socket, :show_lalalai_modal, false)}
      end

      def handle_event("test_lalalai_connection", _params, socket) do
        user_id = socket.assigns[:current_user_id]
        key = SoundForge.Audio.LalalAI.api_key_for_user(user_id)

        if key do
          socket = assign(socket, :lalalai_connection_status, :testing)
          lv_pid = self()

          Task.Supervisor.start_child(SoundForge.TaskSupervisor, fn ->
            result = SoundForge.Audio.LalalAI.test_api_key(key)
            send(lv_pid, {:lalalai_connection_result, result})
          end)

          {:noreply, socket}
        else
          {:noreply,
           socket
           |> assign(:lalalai_connection_status, :error)
           |> assign(
             :lalalai_last_error,
             "No API key configured. Add one in Settings or set SYSTEM_LALALAI_ACTIVATION_KEY."
           )}
        end
      end

      def handle_event("expand_lalalai_key_form", _params, socket) do
        {:noreply, assign(socket, :lalalai_modal_expanded, true)}
      end

      def handle_event("lalalai_modal_key_input", %{"key" => key}, socket) do
        {:noreply, assign(socket, :lalalai_modal_key_input, key)}
      end

      def handle_event("test_save_lalalai_key", _params, socket) do
        key = socket.assigns.lalalai_modal_key_input

        if key == "" do
          {:noreply,
           assign(socket, :lalalai_modal_test_result, {:error, "Please enter an API key"})}
        else
          socket = assign(socket, :lalalai_modal_testing, true)
          lv_pid = self()

          Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
            result = SoundForge.Audio.LalalAI.test_api_key(key)
            send(lv_pid, {:lalalai_modal_test_result, result, key})
          end)

          {:noreply, socket}
        end
      end

      def handle_event("cancel_lalalai_task", %{"job-id" => job_id}, socket) do
        job = SoundForge.Music.get_processing_job!(job_id)
        task_id = get_in(job.options || %{}, ["lalalai_task_id"])

        if task_id do
          case SoundForge.Audio.LalalAI.cancel_task([task_id]) do
            {:ok, _} ->
              SoundForge.Music.update_processing_job(job, %{status: :cancelled})

              SoundForge.Jobs.PipelineBroadcaster.broadcast_stage_failed(
                job.track_id,
                job_id,
                :processing
              )

              socket =
                update_pipeline_stage(socket, job.track_id, :processing, fn stage_data ->
                  Map.merge(stage_data, %{
                    status: :cancelled,
                    progress: stage_data[:progress] || 0
                  })
                end)

              {:noreply, put_flash(socket, :info, "Task cancelled")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to cancel: #{inspect(reason)}")}
          end
        else
          {:noreply, put_flash(socket, :error, "No task ID found")}
        end
      end

      def handle_event("cancel_all_lalalai_tasks", _params, socket) do
        case SoundForge.Audio.LalalAI.cancel_all_tasks() do
          {:ok, _} ->
            socket =
              Enum.reduce(socket.assigns.pipelines, socket, fn {track_id, pipeline}, acc ->
                case Map.get(pipeline, :processing) do
                  %{status: s, engine: "lalalai"} when s in [:processing, :queued] ->
                    update_pipeline_stage(acc, track_id, :processing, fn stage_data ->
                      Map.merge(stage_data, %{
                        status: :cancelled,
                        progress: stage_data[:progress] || 0
                      })
                    end)

                  _ ->
                    acc
                end
              end)

            {:noreply, put_flash(socket, :info, "All lalal.ai tasks cancelled")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to cancel all: #{inspect(reason)}")}
        end
      end

      # ── Analysis Events ───────────────────────────────────────────────────

      def handle_event("analyze_track", %{"id" => id}, socket) do
        user_id = socket.assigns[:current_user_id]

        with {:ok, track} <- fetch_owned_track(socket, id),
             {:ok, _} <- retry_pipeline_stage(track.id, :analysis, user_id) do
          maybe_subscribe(socket, track.id)

          pipelines = socket.assigns.pipelines
          pipeline = Map.get(pipelines, track.id, %{})
          updated_pipeline = Map.put(pipeline, :analysis, %{status: :queued, progress: 0})
          pipelines = Map.put(pipelines, track.id, updated_pipeline)

          {:noreply,
           socket
           |> assign(:pipelines, pipelines)
           |> put_flash(:info, "Analyzing #{track.title}...")}
        else
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Track not found")}

          {:error, :no_completed_download} ->
            {:noreply, put_flash(socket, :error, "Download the track first before analyzing")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not start analysis")}
        end
      end

      def handle_event("convert_to_midi", %{"id" => id}, socket) do
        with {:ok, track} <- fetch_owned_track(socket, id),
             {:ok, file_path} <- SoundForge.Music.get_download_path_validated(track.id) do
          %{track_id: track.id, file_path: file_path}
          |> SoundForge.Jobs.AudioToMidiWorker.new()
          |> Oban.insert()

          {:noreply, put_flash(socket, :info, "Converting #{track.title} to MIDI...")}
        else
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Track not found")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Download the track first")}
        end
      end

      def handle_event("detect_chords", %{"id" => id}, socket) do
        with {:ok, track} <- fetch_owned_track(socket, id),
             {:ok, file_path} <- SoundForge.Music.get_download_path_validated(track.id) do
          %{track_id: track.id, file_path: file_path}
          |> SoundForge.Jobs.ChordDetectionWorker.new()
          |> Oban.insert()

          {:noreply, put_flash(socket, :info, "Detecting chords in #{track.title}...")}
        else
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Track not found")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Download the track first")}
        end
      end

      # ── Delete / Pipeline Lifecycle Events ───────────────────────────────

      def handle_event("delete_track", %{"id" => id}, socket) do
        with {:ok, track} <- fetch_owned_track(socket, id),
             {:ok, _} <- SoundForge.Music.delete_track_with_files(track) do
          pipelines = Map.delete(socket.assigns.pipelines, id)

          socket =
            socket
            |> stream_delete_by_dom_id(:tracks, "tracks-#{id}")
            |> assign(:pipelines, pipelines)
            |> update(:track_count, fn c -> max(c - 1, 0) end)
            |> put_flash(:info, "Track deleted")

          socket =
            if socket.assigns.live_action == :show,
              do: push_navigate(socket, to: ~p"/"),
              else: socket

          {:noreply, socket}
        else
          {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Track not found")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete track")}
        end
      end

      def handle_event("dismiss_pipeline", %{"track-id" => track_id}, socket) do
        pipelines = Map.delete(socket.assigns.pipelines, track_id)
        {:noreply, assign(socket, :pipelines, pipelines)}
      end

      def handle_event("retry_pipeline", %{"track-id" => track_id, "stage" => stage}, socket) do
        stage_atom =
          try do
            atom = String.to_existing_atom(stage)
            if atom in @valid_pipeline_stages, do: atom, else: nil
          rescue
            ArgumentError -> nil
          end

        if is_nil(stage_atom) do
          {:noreply, put_flash(socket, :error, "Invalid pipeline stage")}
        else
          user_id = socket.assigns[:current_user_id]

          with {:ok, track} <- fetch_owned_track(socket, track_id),
               {:ok, result} <- retry_pipeline_stage(track.id, stage_atom, user_id) do
            pipelines = socket.assigns.pipelines
            pipeline = Map.get(pipelines, track_id, %{})

            stage_data =
              if stage_atom == :processing and
                   is_struct(result, SoundForge.Music.ProcessingJob) do
                %{status: :queued, progress: 0, job_id: result.id, engine: result.engine}
              else
                %{status: :queued, progress: 0}
              end

            updated_pipeline = Map.put(pipeline, stage_atom, stage_data)
            pipelines = Map.put(pipelines, track_id, updated_pipeline)

            {:noreply,
             socket
             |> assign(:pipelines, pipelines)
             |> put_flash(:info, "Retrying #{stage}...")}
          else
            {:error, :not_found} ->
              {:noreply, put_flash(socket, :error, "Track not found")}

            {:error, :no_completed_download} ->
              {:noreply, put_flash(socket, :error, "Download the track first")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Retry failed: #{reason}")}
          end
        end
      end

      def handle_event("force_reset_pipeline", %{"track-id" => track_id}, socket) do
        cancelled_count = SoundForge.Music.cancel_stuck_oban_jobs(track_id)
        SoundForge.Music.fail_stuck_processing_jobs(track_id)
        pipelines = Map.delete(socket.assigns.pipelines, track_id)

        {:noreply,
         socket
         |> assign(:pipelines, pipelines)
         |> put_flash(
           :info,
           "Pipeline reset (#{cancelled_count} job(s) cancelled). Use Retry to restart stages."
         )}
      end

      # ── Upload Events ─────────────────────────────────────────────────────

      def handle_event("upload_audio", _params, socket) do
        uid = user_id(socket)

        uploaded_tracks =
          consume_uploaded_entries(socket, :audio, fn %{path: tmp_path}, entry ->
            process_uploaded_entry(tmp_path, entry, uid)
          end)

        successful =
          uploaded_tracks
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, track} -> track end)

        socket = Enum.reduce(successful, socket, &add_upload_pipeline(&2, &1))
        socket = upload_flash(socket, successful)
        {:noreply, socket}
      end

      def handle_event("validate_upload", _params, socket) do
        {:noreply, socket}
      end

      def handle_event("cancel_upload", %{"ref" => ref}, socket) do
        {:noreply, cancel_upload(socket, :audio, ref)}
      end

      # ── Piano Roll Events ───────────────��───────────────────────────��─────

      def handle_event(
            "add_user_note",
            %{
              "note" => note,
              "onset_sec" => onset_sec,
              "duration_sec" => duration_sec,
              "velocity" => velocity
            },
            socket
          ) do
        track = socket.assigns.track
        user_id = socket.assigns.current_user_id

        if track && user_id do
          case SoundForge.MIDI.NoteEdits.create_note_edit(%{
                 note: note,
                 onset_sec: onset_sec,
                 duration_sec: duration_sec,
                 velocity: velocity,
                 track_id: track.id,
                 user_id: user_id
               }) do
            {:ok, _edit} ->
              user_notes =
                serialize_user_notes(SoundForge.MIDI.NoteEdits.list_note_edits(track.id, user_id))

              {:noreply,
               socket
               |> assign(:user_notes, user_notes)
               |> push_event("set_user_notes", %{notes: user_notes})}

            {:error, _changeset} ->
              {:noreply, socket}
          end
        else
          {:noreply, socket}
        end
      end

      def handle_event("delete_user_note", %{"note_id" => note_id}, socket) do
        track = socket.assigns.track
        user_id = socket.assigns.current_user_id

        if track && user_id do
          case SoundForge.MIDI.NoteEdits.get_note_edit(note_id) do
            nil ->
              {:noreply, socket}

            edit ->
              SoundForge.MIDI.NoteEdits.delete_note_edit(edit)

              user_notes =
                serialize_user_notes(SoundForge.MIDI.NoteEdits.list_note_edits(track.id, user_id))

              {:noreply,
               socket
               |> assign(:user_notes, user_notes)
               |> push_event("set_user_notes", %{notes: user_notes})}
          end
        else
          {:noreply, socket}
        end
      end

      # ── Pipeline handle_info ──────────────────────────────────────────────

      def handle_info({:lalalai_modal_test_result, result, key}, socket) do
        case result do
          {:ok, :valid} ->
            user_id = socket.assigns[:current_user_id]

            if user_id do
              SoundForge.Settings.save_lalalai_api_key(user_id, key)
            end

            {:noreply,
             socket
             |> assign(:lalalai_modal_testing, false)
             |> assign(:lalalai_modal_test_result, {:ok, "API key verified and saved."})
             |> assign(:selected_engine, "lalalai")
             |> assign(:show_lalalai_modal, false)
             |> put_flash(:info, "lalal.ai API key saved. Cloud separation is now available.")}

          {:error, :invalid_api_key} ->
            {:noreply,
             socket
             |> assign(:lalalai_modal_testing, false)
             |> assign(
               :lalalai_modal_test_result,
               {:error, "Invalid API key. Please check and try again."}
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:lalalai_modal_testing, false)
             |> assign(
               :lalalai_modal_test_result,
               {:error, "Test failed: #{inspect(reason)}"}
             )}
        end
      end

      def handle_info({:lalalai_connection_result, result}, socket) do
        case result do
          {:ok, :valid} ->
            {:noreply,
             socket
             |> assign(:lalalai_connection_status, :ok)
             |> assign(:lalalai_last_error, nil)
             |> put_flash(:info, "lalal.ai connection verified.")}

          {:error, :invalid_api_key} ->
            {:noreply,
             socket
             |> assign(:lalalai_connection_status, :error)
             |> assign(
               :lalalai_last_error,
               "API key is invalid or expired. Update in Settings > Cloud Separation."
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:lalalai_connection_status, :error)
             |> assign(:lalalai_last_error, "Connection failed: #{inspect(reason)}")}
        end
      end

      def handle_info({ref, _result}, socket) when is_reference(ref) do
        Process.demonitor(ref, [:flush])
        {:noreply, socket}
      end

      def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
        {:noreply, assign(socket, :fetching_spotify, false)}
      end

      def handle_info(
            {:pipeline_progress, %{track_id: track_id, stage: stage} = payload},
            socket
          ) do
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})
        existing_stage = Map.get(pipeline, stage, %{})

        stage_data =
          %{status: payload.status, progress: payload.progress}
          |> maybe_put(:job_id, Map.get(existing_stage, :job_id))
          |> maybe_put(:engine, Map.get(existing_stage, :engine))

        updated_pipeline = Map.put(pipeline, stage, stage_data)
        pipelines = Map.put(pipelines, track_id, updated_pipeline)

        socket =
          if payload.status == :failed do
            stage_name = stage |> to_string() |> String.capitalize()

            socket
            |> push_notification(
              :error,
              "#{stage_name} Failed",
              "#{stage_name} failed for track. Check server logs.",
              %{track_id: track_id}
            )
            |> put_flash(:error, "#{stage_name} failed. Check server logs for details.")
          else
            socket
          end

        socket =
          if payload.status == :completed && stage in [:download, :processing] do
            case SoundForge.Music.get_track(track_id) do
              {:ok, track} when not is_nil(track) -> stream_insert(socket, :tracks, track)
              _ -> socket
            end
          else
            socket
          end

        socket =
          if payload.status == :completed &&
               socket.assigns.live_action == :show &&
               socket.assigns.track && socket.assigns.track.id == track_id do
            track = SoundForge.Music.get_track_with_details!(track_id)

            socket
            |> assign(:track, track)
            |> assign(:stems, track.stems)
            |> assign(:analysis, List.first(track.analysis_results))
            |> assign(:midi_result, SoundForge.Music.get_midi_result_for_track(track_id))
            |> assign(:chord_result, SoundForge.Music.get_chord_result_for_track(track_id))
          else
            socket
          end

        {:noreply, assign(socket, :pipelines, pipelines)}
      end

      def handle_info({:midi_conversion_complete, track_id}, socket) do
        socket =
          if socket.assigns.live_action == :show &&
               socket.assigns.track && socket.assigns.track.id == track_id do
            assign(socket, :midi_result, SoundForge.Music.get_midi_result_for_track(track_id))
          else
            socket
          end

        {:noreply, socket}
      end

      def handle_info({:chord_detection_complete, track_id}, socket) do
        socket =
          if socket.assigns.live_action == :show &&
               socket.assigns.track && socket.assigns.track.id == track_id do
            assign(socket, :chord_result, SoundForge.Music.get_chord_result_for_track(track_id))
          else
            socket
          end

        {:noreply, socket}
      end

      def handle_info({:pipeline_complete, %{track_id: track_id}}, socket) do
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})

        updated_pipeline =
          Enum.reduce([:download, :processing, :analysis], pipeline, fn stage, acc ->
            if Map.has_key?(acc, stage) do
              Map.put(acc, stage, %{status: :completed, progress: 100})
            else
              acc
            end
          end)

        pipelines = Map.put(pipelines, track_id, updated_pipeline)

        socket =
          case SoundForge.Music.get_track(track_id) do
            {:ok, track} when not is_nil(track) -> stream_insert(socket, :tracks, track)
            _ -> socket
          end

        socket =
          if socket.assigns.live_action == :show &&
               socket.assigns.track && socket.assigns.track.id == track_id do
            track = SoundForge.Music.get_track_with_details!(track_id)

            socket
            |> assign(:track, track)
            |> assign(:stems, track.stems)
            |> assign(:analysis, List.first(track.analysis_results))
          else
            socket
          end

        track_title =
          case SoundForge.Music.get_track(track_id) do
            {:ok, t} when not is_nil(t) -> t.title
            _ -> "Track"
          end

        {:noreply,
         socket
         |> push_notification(:success, "Pipeline Complete", "\"#{track_title}\" is ready.", %{
           track_id: track_id
         })
         |> assign(:pipelines, pipelines)
         |> put_flash(:info, "Pipeline complete! Track is ready.")}
      end

      def handle_info(
            {:playlist_track_update,
             %{track_id: track_id, stage: stage, status: status, progress: progress}},
            socket
          ) do
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})
        updated_pipeline = Map.put(pipeline, stage, %{status: status, progress: progress})
        {:noreply, assign(socket, :pipelines, Map.put(pipelines, track_id, updated_pipeline))}
      end

      def handle_info({:job_progress, payload}, socket) do
        jobs = Map.put(socket.assigns.active_jobs, payload.job_id, payload)
        {:noreply, assign(socket, :active_jobs, jobs)}
      end

      def handle_info(
            {:batch_progress,
             %{
               batch_job_id: _id,
               status: status,
               completed_count: completed,
               total_count: total
             }},
            socket
          ) do
        batch_status = socket.assigns.batch_status

        updated_status =
          if batch_status do
            %{batch_status | status: status, completed_count: completed, total_count: total}
          else
            batch_status
          end

        {:noreply, assign(socket, :batch_status, updated_status)}
      end

      def handle_info(
            {:batch_complete,
             %{
               batch_job_id: _id,
               completed_count: completed,
               failed_count: failed,
               total_count: total
             }},
            socket
          ) do
        msg =
          if failed > 0 do
            "Batch complete: #{completed}/#{total} succeeded, #{failed} failed"
          else
            "Batch complete: #{completed} tracks processed successfully"
          end

        {:noreply,
         socket
         |> assign(:batch_processing, false)
         |> assign(:batch_mode, false)
         |> put_flash(:info, msg)}
      end

      # ── Public: Template helpers ──────────────────────────────────────────

      def pipeline_complete?(pipeline) do
        triggered = Enum.filter(@pipeline_stages, &Map.has_key?(pipeline, &1))

        triggered != [] and
          Enum.all?(triggered, fn stage ->
            match?(%{status: :completed}, Map.get(pipeline, stage))
          end)
      end

      # ── Private: Pipeline logic ───────────────────────────────────────────

      defp start_processing(track_id, user_id, opts) do
        engine = Keyword.get(opts, :engine, "demucs")
        preview = Keyword.get(opts, :preview, false)
        model = SoundForge.Settings.get(user_id, :demucs_model)
        lalalai_mode = Keyword.get(opts, :lalalai_mode, "stem_separator")
        multistem_stems = Keyword.get(opts, :multistem_stems, [])
        noise_level = Keyword.get(opts, :noise_level, 0)
        voice_pack_id = Keyword.get(opts, :voice_pack_id, nil)
        accent = Keyword.get(opts, :accent, 0.5)
        dereverb = Keyword.get(opts, :dereverb, false)

        with {:ok, file_path} <- SoundForge.Music.get_download_path(track_id),
             {:ok, job} <-
               SoundForge.Music.create_processing_job(%{
                 track_id: track_id,
                 model: model,
                 status: :queued,
                 engine: engine,
                 preview: preview
               }),
             {:ok, _oban_job} <-
               %{
                 "track_id" => track_id,
                 "job_id" => job.id,
                 "file_path" => file_path,
                 "model" => model,
                 "engine" => engine,
                 "preview" => preview,
                 "lalalai_mode" => lalalai_mode,
                 "multistem_stems" => multistem_stems,
                 "noise_level" => noise_level,
                 "voice_pack_id" => voice_pack_id,
                 "accent" => accent,
                 "dereverb" => dereverb
               }
               |> SoundForge.Jobs.ProcessingWorker.new()
               |> Oban.insert() do
          {:ok, job}
        else
          {:error, :no_completed_download} -> {:error, :no_completed_download}
          error -> error
        end
      end

      defp retry_pipeline_stage(track_id, :download, user_id) do
        track = SoundForge.Music.get_track!(track_id)

        with {:ok, job} <-
               SoundForge.Music.create_download_job(%{track_id: track_id, status: :queued}) do
          %{
            "track_id" => track_id,
            "spotify_url" => track.spotify_url,
            "quality" => SoundForge.Settings.get(user_id, :download_quality),
            "job_id" => job.id
          }
          |> SoundForge.Jobs.DownloadWorker.new()
          |> Oban.insert()
        end
      end

      defp retry_pipeline_stage(track_id, :processing, user_id) do
        start_processing(track_id, user_id, [])
      end

      defp retry_pipeline_stage(track_id, :analysis, user_id) do
        with {:ok, file_path} <- SoundForge.Music.get_download_path(track_id),
             {:ok, job} <-
               SoundForge.Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
          %{
            "track_id" => track_id,
            "job_id" => job.id,
            "file_path" => file_path,
            "features" => SoundForge.Settings.get(user_id, :analysis_features)
          }
          |> SoundForge.Jobs.AnalysisWorker.new()
          |> Oban.insert()
        else
          {:error, :no_completed_download} -> {:error, :no_completed_download}
          error -> error
        end
      end

      defp start_single_pipeline(track_meta, original_url, uid, auto_download) do
        spotify_id = track_meta["song_id"] || track_meta["id"]
        spotify_url = track_meta["url"] || original_url

        with :ok <- check_duplicate(spotify_id, nil),
             {:ok, track} <- create_track_from_metadata(track_meta, spotify_url, uid) do
          if auto_download do
            {:ok, download_job} =
              SoundForge.Music.create_download_job(%{track_id: track.id, status: :queued})

            %{
              "track_id" => track.id,
              "spotify_url" => spotify_url,
              "quality" => SoundForge.Settings.get(uid, :download_quality),
              "job_id" => download_job.id
            }
            |> SoundForge.Jobs.DownloadWorker.new()
            |> Oban.insert()

            pipeline = %{track_id: track.id, download: %{status: :queued, progress: 0}}
            {:ok, track, pipeline}
          else
            pipeline = %{track_id: track.id}
            {:ok, track, pipeline}
          end
        end
      end

      defp add_pipeline_track(
             socket,
             track_meta,
             url,
             uid,
             auto_download,
             playlist \\ nil,
             position \\ nil
           ) do
        case start_single_pipeline(track_meta, url, uid, auto_download) do
          {:ok, track, pipeline} ->
            if playlist do
              SoundForge.Music.add_track_to_playlist(playlist, track, position || 0)
            end

            maybe_subscribe(socket, track.id)
            pipelines = Map.put(socket.assigns.pipelines, track.id, pipeline)

            socket
            |> assign(:pipelines, pipelines)
            |> stream_insert(:tracks, track, at: 0)
            |> update(:track_count, &(&1 + 1))

          {:error, _} ->
            socket
        end
      end

      defp maybe_subscribe(socket, track_id) do
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track_id}")
        end
      end

      defp maybe_put(map, _key, nil), do: map
      defp maybe_put(map, key, value), do: Map.put(map, key, value)

      defp update_pipeline_stage(socket, track_id, stage, fun) do
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})
        stage_data = Map.get(pipeline, stage, %{})
        updated_pipeline = Map.put(pipeline, stage, fun.(stage_data))
        assign(socket, :pipelines, Map.put(pipelines, track_id, updated_pipeline))
      end

      defp fetch_success_message([_single | []] = [track_meta]) do
        "Started processing: #{track_meta["name"] || "track"}"
      end

      defp fetch_success_message(tracks_data) do
        "Started processing #{length(tracks_data)} tracks"
      end

      defp check_duplicate(nil, _scope), do: :ok

      defp check_duplicate(spotify_id, _scope) do
        case SoundForge.Music.get_track_by_spotify_id(spotify_id) do
          nil -> :ok
          _track -> {:error, :duplicate}
        end
      end

      defp process_uploaded_entry(tmp_path, entry, user_id) do
        filename = entry.client_name
        title = filename |> Path.rootname() |> String.replace(~r/[-_]+/, " ") |> String.trim()
        ext = Path.extname(filename)

        SoundForge.Storage.ensure_directories!()
        dest_filename = "#{Ecto.UUID.generate()}#{ext}"
        dest_path = Path.join(SoundForge.Storage.downloads_path(), dest_filename)
        File.cp!(tmp_path, dest_path)

        case SoundForge.Music.create_track(%{title: title, user_id: user_id}) do
          {:ok, track} ->
            enqueue_upload_processing(track, dest_path, entry.client_size)
            {:ok, track}

          error ->
            File.rm(dest_path)
            error
        end
      end

      defp enqueue_upload_processing(track, dest_path, file_size) do
        {:ok, _job} =
          SoundForge.Music.create_download_job(%{
            track_id: track.id,
            status: :completed,
            output_path: dest_path,
            file_size: file_size
          })

        model = SoundForge.Settings.get(nil, :demucs_model)

        {:ok, processing_job} =
          SoundForge.Music.create_processing_job(%{
            track_id: track.id,
            model: model,
            status: :queued
          })

        %{
          "track_id" => track.id,
          "job_id" => processing_job.id,
          "file_path" => dest_path,
          "model" => model
        }
        |> SoundForge.Jobs.ProcessingWorker.new()
        |> Oban.insert()
      end

      defp add_upload_pipeline(socket, track) do
        maybe_subscribe(socket, track.id)

        pipeline = %{
          track_id: track.id,
          download: %{status: :completed, progress: 100},
          processing: %{status: :queued, progress: 0}
        }

        pipelines = Map.put(socket.assigns.pipelines, track.id, pipeline)

        socket
        |> assign(:pipelines, pipelines)
        |> stream_insert(:tracks, track, at: 0)
        |> update(:track_count, &(&1 + 1))
      end

      defp upload_flash(socket, []), do: socket

      defp upload_flash(socket, [_]),
        do: put_flash(socket, :info, "Uploaded 1 file, processing started")

      defp upload_flash(socket, tracks),
        do: put_flash(socket, :info, "Uploaded #{length(tracks)} files, processing started")

      defp delete_single_track(socket, track_id) do
        with {:ok, track} <- fetch_owned_track(socket, track_id),
             {:ok, _} <- SoundForge.Music.delete_track_with_files(track) do
          pipelines = Map.delete(socket.assigns.pipelines, track_id)

          socket
          |> stream_delete_by_dom_id(:tracks, "tracks-#{track_id}")
          |> assign(:pipelines, pipelines)
          |> update(:track_count, fn c -> max(c - 1, 0) end)
        else
          _ -> socket
        end
      end

      defp has_completed_download?(track_id) do
        import Ecto.Query

        SoundForge.Repo.exists?(
          from(dj in SoundForge.Music.DownloadJob,
            where: dj.track_id == ^track_id and dj.status == :completed
          )
        )
      end

      defp build_initial_pipeline(track) do
        %{}
        |> add_pipeline_stage(:download, Map.get(track, :download_jobs, []))
        |> add_pipeline_stage(:processing, Map.get(track, :processing_jobs, []))
        |> add_pipeline_stage(:analysis, Map.get(track, :analysis_jobs, []))
      end

      defp add_pipeline_stage(pipeline, _stage, jobs) when not is_list(jobs), do: pipeline
      defp add_pipeline_stage(pipeline, _stage, []), do: pipeline

      defp add_pipeline_stage(pipeline, stage, jobs) do
        latest = Enum.max_by(jobs, & &1.inserted_at, DateTime, fn -> nil end)

        if latest do
          progress = if latest.status == :completed, do: 100, else: latest.progress || 0
          Map.put(pipeline, stage, %{status: latest.status, progress: progress})
        else
          pipeline
        end
      end

      defp maybe_resume_incomplete_pipelines(tracks, user_id) do
        model = Application.get_env(:sound_forge, :default_demucs_model, "htdemucs")

        Enum.each(tracks, fn track ->
          djs = Map.get(track, :download_jobs, [])
          ajs = Map.get(track, :analysis_jobs, [])
          pjs = Map.get(track, :processing_jobs, [])

          has_complete_download = Enum.any?(djs, &(&1.status == :completed))
          has_complete_analysis = Enum.any?(ajs, &(&1.status == :completed))
          has_active_processing = Enum.any?(pjs, &(&1.status in [:queued, :processing]))
          completed_download = has_complete_download && Enum.find(djs, &(&1.status == :completed))

          if has_complete_download and not has_complete_analysis and not has_active_processing and
               completed_download do
            file_path = completed_download.output_path

            if file_path && File.exists?(file_path) do
              require Logger
              Logger.info("[DashboardLive] Auto-resuming pipeline for track #{track.id}")

              case SoundForge.Music.create_processing_job(%{
                     track_id: track.id,
                     model: model,
                     status: :queued
                   }) do
                {:ok, processing_job} ->
                  %{
                    "track_id" => track.id,
                    "job_id" => processing_job.id,
                    "file_path" => file_path,
                    "model" => model,
                    "user_id" => user_id
                  }
                  |> SoundForge.Jobs.ProcessingWorker.new()
                  |> Oban.insert()

                {:error, reason} ->
                  require Logger

                  Logger.warning(
                    "[DashboardLive] Could not resume pipeline for #{track.id}: #{inspect(reason)}"
                  )
              end
            end
          end
        end)
      end

      defp serialize_user_notes(note_edits) do
        Enum.map(note_edits, fn n ->
          %{
            id: n.id,
            note: n.note,
            onset: n.onset_sec,
            duration: n.duration_sec,
            velocity: n.velocity
          }
        end)
      end
    end
  end
end
