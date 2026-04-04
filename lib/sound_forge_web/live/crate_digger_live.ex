defmodule SoundForgeWeb.Live.CrateDiggerLive do
  @moduledoc """
  CrateDigger — learning-focused Spotify playlist player for producers.

  Left panel: crate list + import form.
  Center panel: track list with stem config toggles.
  Right panel: slide-out inspector with WhoSampled, Track Details, Lyrics, Analysis,
               and per-track stem override.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Accounts
  alias SoundForge.CrateDigger
  alias SoundForge.CrateDigger.WhoSampledScraper
  alias SoundForge.Jobs.AnalysisWorker
  alias SoundForge.Jobs.DownloadWorker
  alias SoundForge.Music
  alias SoundForge.Repo

  require Logger

  @impl true
  def mount(_params, session, socket) do
    user = resolve_user(socket.assigns[:current_user], session)

    crates = if user, do: CrateDigger.list_crates(user.id), else: []

    socket =
      socket
      |> assign(:page_title, "Crate Digger — SFA")
      |> assign(:current_user, user)
      |> assign(:current_scope, socket.assigns[:current_scope])
      |> assign(:current_user_id, if(user, do: user.id, else: nil))
      |> assign(:nav_tab, :crate)
      |> assign(:nav_context, :all_tracks)
      |> assign(:midi_devices, [])
      |> assign(:midi_bpm, nil)
      |> assign(:midi_transport, :stopped)
      |> assign(:pipelines, %{})
      |> assign(:refreshing_midi, false)
      |> assign(:crates, crates)
      |> assign(:active_crate, List.first(crates))
      |> assign(:playlist_url, "")
      |> assign(:playlist_loading, false)
      |> assign(:playlist_error, nil)
      |> assign(:inspector_track, nil)
      |> assign(:inspector_open, false)
      # WhoSampled state per inspector_track
      |> assign(:whosampled_loading, false)
      |> assign(:whosampled_samples, nil)
      |> assign(:whosampled_error, nil)
      # Accordion section open/closed
      |> assign(:section_open, %{whosampled: false, details: false, lyrics: false, analysis: false, stems: false})
      # Analysis for active inspector track
      |> assign(:inspector_analysis, nil)
      # Crate management UI state
      |> assign(:confirm_delete_crate_id, nil)
      |> assign(:crate_refreshing_id, nil)
      |> assign(:rename_crate_id, nil)
      |> assign(:rename_crate_name, "")
      # Track context menu
      |> assign(:context_menu_track_idx, nil)
      # Track filter
      |> assign(:track_filter, "")
      # Playback state
      |> assign(:now_playing_id, nil)
      |> assign(:playback_state, :idle)
      # v2: Guided profile wizard
      |> assign(:profile_wizard_open, false)
      |> assign(:profile_wizard_step, 1)
      |> assign(:profile_wizard_draft, %{})
      # v2: Spotify folder browser
      |> assign(:playlist_browser_open, false)
      |> assign(:playlist_browser_loading, false)
      |> assign(:user_playlists, [])
      |> assign(:selected_playlist_urls, MapSet.new())
      |> assign(:mega_crate_name, "")
      # v2: Stem interchange lab
      |> assign(:stem_lab_assignments, %{})
      # v2: Sequencer
      |> assign(:crate_sequence, nil)
      |> assign(:sequence_arc, :rise)
      # v2: Pagination
      |> assign(:track_page, 1)

    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "midi:actions")
      SoundForge.MIDI.GlobalBroadcaster.subscribe()
    end

    {:ok,
     socket
     |> assign(:midi_bar_position, "bottom")
     |> assign(:midi_learn_active, false)
     |> assign(:midi_monitor_open, false)}
  end

  # ---------------------------------------------------------------------------
  # Events — playlist import
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("update_playlist_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :playlist_url, url)}
  end

  def handle_event("import_playlist", _params, socket) do
    url = String.trim(socket.assigns.playlist_url)
    user = socket.assigns.current_user

    if url == "" or is_nil(user) do
      {:noreply, assign(socket, :playlist_error, "Enter a Spotify playlist URL")}
    else
      socket = socket |> assign(:playlist_loading, true) |> assign(:playlist_error, nil)
      send(self(), {:load_playlist, url, user.id})
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — crate selection
  # ---------------------------------------------------------------------------

  def handle_event("select_crate", %{"id" => id}, socket) do
    crate = CrateDigger.get_crate(id)
    socket = socket |> assign(:active_crate, crate) |> assign(:inspector_track, nil) |> assign(:inspector_open, false)
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — inspector
  # ---------------------------------------------------------------------------

  def handle_event("open_inspector", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    tracks = active_tracks(socket)
    track = Enum.at(tracks, idx)

    analysis = if track, do: load_analysis(track["spotify_id"]), else: nil

    socket =
      socket
      |> assign(:inspector_track, track)
      |> assign(:inspector_open, true)
      |> assign(:inspector_analysis, analysis)
      |> assign(:whosampled_samples, nil)
      |> assign(:whosampled_loading, false)
      |> assign(:whosampled_error, nil)
      |> assign(:section_open, %{whosampled: false, details: false, lyrics: false, analysis: false, stems: false})

    {:noreply, socket}
  end

  def handle_event("close_inspector", _params, socket) do
    {:noreply, socket |> assign(:inspector_open, false) |> assign(:inspector_track, nil)}
  end

  # ---------------------------------------------------------------------------
  # Events — accordion sections
  # ---------------------------------------------------------------------------

  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    section = String.to_existing_atom(section_str)
    current = socket.assigns.section_open
    updated = Map.update!(current, section, &(!&1))

    socket = assign(socket, :section_open, updated)

    # Lazy-load WhoSampled on first open
    socket =
      if section == :whosampled and updated.whosampled and
           is_nil(socket.assigns.whosampled_samples) and
           not socket.assigns.whosampled_loading do
        track = socket.assigns.inspector_track

        if track do
          send(self(), {:fetch_whosampled, track["spotify_id"], track["artist"], track["title"]})
          assign(socket, :whosampled_loading, true)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — stem config (playlist-level)
  # ---------------------------------------------------------------------------

  def handle_event("toggle_stem", %{"stem" => stem}, socket) do
    crate = socket.assigns.active_crate

    if crate do
      current_stems = crate.stem_config["enabled_stems"] || ["vocals", "drums", "bass", "other"]

      new_stems =
        if stem in current_stems do
          List.delete(current_stems, stem)
        else
          [stem | current_stems]
        end

      # Ensure at least one stem active
      new_stems = if Enum.empty?(new_stems), do: current_stems, else: new_stems

      case CrateDigger.update_crate_stem_config(crate, new_stems) do
        {:ok, updated_crate} ->
          crates = reload_crates(socket)
          {:noreply, socket |> assign(:active_crate, updated_crate) |> assign(:crates, crates)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — per-track stem override
  # ---------------------------------------------------------------------------

  def handle_event("toggle_track_stem", %{"stem" => stem}, socket) do
    crate = socket.assigns.active_crate
    track = socket.assigns.inspector_track

    if crate && track do
      current_override = get_track_override(crate, track["spotify_id"])

      effective =
        current_override ||
          crate.stem_config["enabled_stems"] ||
          ["vocals", "drums", "bass", "other"]

      new_stems =
        if stem in effective do
          List.delete(effective, stem)
        else
          [stem | effective]
        end

      new_stems = if Enum.empty?(new_stems), do: effective, else: new_stems

      CrateDigger.set_track_stem_override(crate.id, track["spotify_id"], new_stems)
      updated_crate = CrateDigger.get_crate(crate.id)
      {:noreply, assign(socket, :active_crate, updated_crate)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_track_override", _params, socket) do
    crate = socket.assigns.active_crate
    track = socket.assigns.inspector_track

    if crate && track do
      CrateDigger.set_track_stem_override(crate.id, track["spotify_id"], nil)
      updated_crate = CrateDigger.get_crate(crate.id)
      {:noreply, assign(socket, :active_crate, updated_crate)}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — Load into SFA (enqueue download)
  # ---------------------------------------------------------------------------

  def handle_event("load_into_sfa", %{"spotify_url" => spotify_url}, socket) do
    user = socket.assigns.current_user
    inspector_track = socket.assigns.inspector_track

    if is_nil(user) or not is_binary(spotify_url) or spotify_url == "" do
      {:noreply, socket}
    else
      spotify_id = extract_spotify_id_from_url(spotify_url)
      existing = Music.get_track_by_spotify_id_with_status(spotify_id)

      cond do
        not is_nil(existing) and Music.track_pipeline_complete?(existing) ->
          {:noreply, put_flash(socket, :info, "\"#{existing.title}\" is already in your library.")}

        not is_nil(existing) ->
          {:noreply, put_flash(socket, :info, "\"#{existing.title}\" is already being processed.")}

        true ->
          attrs = build_track_attrs(inspector_track, spotify_url, spotify_id, user.id)

          with {:ok, track} <- Music.create_track(attrs),
               {:ok, download_job} <- Music.create_download_job(%{track_id: track.id, status: :queued}) do
            %{
              "track_id" => track.id,
              "spotify_url" => spotify_url,
              "quality" => "320k",
              "job_id" => download_job.id
            }
            |> DownloadWorker.new()
            |> Oban.insert()

            {:noreply, put_flash(socket, :info, "\"#{track.title}\" queued for download.")}
          else
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to queue track for download.")}
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Events — trigger analysis
  # ---------------------------------------------------------------------------

  def handle_event("nav_tab", %{"tab" => tab}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/?tab=#{tab}")}
  end

  def handle_event("trigger_analysis", %{"track_id" => track_id}, socket) do
    %{"track_id" => track_id}
    |> AnalysisWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Analysis queued.")}
  end

  # ---------------------------------------------------------------------------
  # Events — crate management (delete, rename, refresh)
  # ---------------------------------------------------------------------------

  def handle_event("delete_crate", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_crate_id, id)}
  end

  def handle_event("cancel_delete_crate", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_crate_id, nil)}
  end

  def handle_event("confirm_delete_crate", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case CrateDigger.get_crate(id) do
      nil ->
        {:noreply, assign(socket, :confirm_delete_crate_id, nil)}

      crate ->
        {:ok, _} = CrateDigger.delete_crate(crate)
        crates = if user, do: CrateDigger.list_crates(user.id), else: []

        socket =
          socket
          |> assign(:crates, crates)
          |> assign(:active_crate, List.first(crates))
          |> assign(:confirm_delete_crate_id, nil)
          |> assign(:inspector_track, nil)
          |> assign(:inspector_open, false)
          |> put_flash(:info, "Crate deleted.")

        {:noreply, socket}
    end
  end

  def handle_event("start_rename_crate", %{"id" => id, "name" => name}, socket) do
    {:noreply, socket |> assign(:rename_crate_id, id) |> assign(:rename_crate_name, name)}
  end

  def handle_event("update_rename_crate", %{"name" => name}, socket) do
    {:noreply, assign(socket, :rename_crate_name, name)}
  end

  def handle_event("save_rename_crate", _params, socket) do
    user = socket.assigns.current_user
    crate_id = socket.assigns.rename_crate_id
    new_name = socket.assigns.rename_crate_name

    socket =
      with id when not is_nil(id) <- crate_id,
           crate when not is_nil(crate) <- CrateDigger.get_crate(id),
           {:ok, updated} <- CrateDigger.rename_crate(crate, new_name) do
        crates = if user, do: CrateDigger.list_crates(user.id), else: []

        active =
          if socket.assigns.active_crate && socket.assigns.active_crate.id == updated.id,
            do: updated,
            else: socket.assigns.active_crate

        socket
        |> assign(:crates, crates)
        |> assign(:active_crate, active)
        |> assign(:rename_crate_id, nil)
        |> assign(:rename_crate_name, "")
      else
        _ -> socket |> assign(:rename_crate_id, nil) |> assign(:rename_crate_name, "")
      end

    {:noreply, socket}
  end

  def handle_event("cancel_rename_crate", _params, socket) do
    {:noreply, socket |> assign(:rename_crate_id, nil) |> assign(:rename_crate_name, "")}
  end

  def handle_event("refresh_crate", %{"id" => id}, socket) do
    socket = assign(socket, :crate_refreshing_id, id)

    crate = CrateDigger.get_crate(id)

    socket =
      if crate do
        case CrateDigger.refresh_crate(crate) do
          {:ok, updated} ->
            user = socket.assigns.current_user
            crates = if user, do: CrateDigger.list_crates(user.id), else: []

            active =
              if socket.assigns.active_crate && socket.assigns.active_crate.id == updated.id,
                do: CrateDigger.get_crate(updated.id),
                else: socket.assigns.active_crate

            socket
            |> assign(:crates, crates)
            |> assign(:active_crate, active)
            |> assign(:crate_refreshing_id, nil)
            |> put_flash(:info, "Playlist refreshed.")

          {:error, _} ->
            socket
            |> assign(:crate_refreshing_id, nil)
            |> put_flash(:error, "Failed to refresh playlist. Check Spotify connection.")
        end
      else
        assign(socket, :crate_refreshing_id, nil)
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — track context menu
  # ---------------------------------------------------------------------------

  def handle_event("open_context_menu", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    {:noreply, assign(socket, :context_menu_track_idx, idx)}
  end

  def handle_event("close_context_menu", _params, socket) do
    {:noreply, assign(socket, :context_menu_track_idx, nil)}
  end

  def handle_event("reorder_track", %{"spotify_id" => spotify_id, "direction" => direction}, socket) do
    crate = socket.assigns.active_crate

    case crate do
      nil ->
        {:noreply, socket}

      %{playlist_data: tracks} when is_list(tracks) ->
        idx = Enum.find_index(tracks, &(&1["spotify_id"] == spotify_id))

        new_tracks =
          case {idx, direction} do
            {nil, _} -> tracks
            {0, "up"} -> tracks
            {i, "up"} when i > 0 ->
              {a, b} = {Enum.at(tracks, i - 1), Enum.at(tracks, i)}
              tracks |> List.replace_at(i - 1, b) |> List.replace_at(i, a)
            {i, "down"} when i < length(tracks) - 1 ->
              {a, b} = {Enum.at(tracks, i), Enum.at(tracks, i + 1)}
              tracks |> List.replace_at(i, b) |> List.replace_at(i + 1, a)
            _ -> tracks
          end

        case CrateDigger.update_crate(crate, %{playlist_data: new_tracks}) do
          {:ok, updated} ->
            crates = Enum.map(socket.assigns.crates, fn c ->
              if c.id == updated.id, do: updated, else: c
            end)
            {:noreply, socket |> assign(:active_crate, updated) |> assign(:crates, crates)}
          {:error, _} ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("redownload_track", %{"spotify_url" => spotify_url}, socket) do
    user = socket.assigns.current_user

    socket =
      if user && socket.assigns.active_crate && is_binary(spotify_url) && spotify_url != "" do
        spotify_id = extract_spotify_id_from_url(spotify_url)
        existing = Music.get_track_by_spotify_id_with_status(spotify_id)

        track =
          existing ||
            with attrs = build_track_attrs(socket.assigns.inspector_track, spotify_url, spotify_id, user.id),
                 {:ok, t} <- Music.create_track(attrs) do
              t
            else
              _ -> nil
            end

        case track && Music.create_download_job(%{track_id: track.id, status: :queued}) do
          {:ok, download_job} ->
            %{
              "track_id" => track.id,
              "spotify_url" => spotify_url,
              "quality" => "320k",
              "job_id" => download_job.id
            }
            |> DownloadWorker.new()
            |> Oban.insert()

            socket
            |> assign(:context_menu_track_idx, nil)
            |> put_flash(:info, "Re-download queued.")

          _ ->
            socket
            |> assign(:context_menu_track_idx, nil)
            |> put_flash(:error, "Failed to queue re-download.")
        end
      else
        assign(socket, :context_menu_track_idx, nil)
      end

    {:noreply, socket}
  end

  def handle_event("load_in_tab", %{"tab" => tab, "spotify_id" => spotify_id}, socket) do
    # Navigate to dashboard tab — the active track hint is passed as query param
    # DashboardLive reads ?preload_track= on mount to highlight/load the track
    {:noreply,
     socket
     |> assign(:context_menu_track_idx, nil)
     |> push_navigate(to: ~p"/?tab=#{tab}&preload_track=#{spotify_id}")}
  end

  def handle_event("filter_tracks", %{"query" => query}, socket) do
    {:noreply, assign(socket, :track_filter, query)}
  end

  # ---------------------------------------------------------------------------
  # Events — playback (preview)
  # ---------------------------------------------------------------------------

  def handle_event("play_track_preview", %{"index" => idx_str}, socket) do
    tracks = active_tracks(socket)
    idx = String.to_integer(idx_str)
    track = Enum.at(tracks, idx)

    case track do
      nil ->
        {:noreply, socket}

      t ->
        preview_url = t["preview_url"]

        socket =
          socket
          |> assign(:now_playing_id, t["spotify_id"])
          |> assign(:playback_state, :playing)
          |> push_event("crate_play_track", %{spotify_id: t["spotify_id"], preview_url: preview_url})

        {:noreply, socket}
    end
  end

  def handle_event("stop_preview", _params, socket) do
    socket =
      socket
      |> assign(:now_playing_id, nil)
      |> assign(:playback_state, :idle)
      |> push_event("crate_stop_playback", %{})

    {:noreply, socket}
  end

  # JS → server playback lifecycle events
  def handle_event("crate_playback_started", %{"spotify_id" => spotify_id}, socket) do
    {:noreply, socket |> assign(:now_playing_id, spotify_id) |> assign(:playback_state, :playing)}
  end

  def handle_event("crate_playback_ended", _params, socket) do
    {:noreply, socket |> assign(:now_playing_id, nil) |> assign(:playback_state, :idle)}
  end

  def handle_event("crate_playback_error", _params, socket) do
    {:noreply, socket |> assign(:now_playing_id, nil) |> assign(:playback_state, :idle)}
  end

  # Catch-all: ignore unhandled events (e.g. pwa_midi_available from root layout hook)
  # ---------------------------------------------------------------------------
  # Events — guided profile wizard (v2)
  # ---------------------------------------------------------------------------

  def handle_event("open_profile_wizard", _params, socket) do
    crate = socket.assigns.active_crate
    draft = if crate, do: crate.crate_profile || %{}, else: %{}

    draft =
      draft
      |> Map.put_new("bpm_min", 120)
      |> Map.put_new("bpm_max", 140)
      |> Map.put_new("energy_level", 70)
      |> Map.put_new("key_preferences", [])
      |> Map.put_new("mood_tags", [])

    {:noreply,
     socket
     |> assign(:profile_wizard_open, true)
     |> assign(:profile_wizard_step, 1)
     |> assign(:profile_wizard_draft, draft)}
  end

  def handle_event("close_profile_wizard", _params, socket) do
    {:noreply, assign(socket, :profile_wizard_open, false)}
  end

  def handle_event("set_profile_field", %{"field" => field, "value" => value}, socket) do
    draft =
      case field do
        "bpm_min" -> Map.put(socket.assigns.profile_wizard_draft, "bpm_min", parse_int(value, 120))
        "bpm_max" -> Map.put(socket.assigns.profile_wizard_draft, "bpm_max", parse_int(value, 140))
        "energy_level" -> Map.put(socket.assigns.profile_wizard_draft, "energy_level", parse_int(value, 70))
        "mood_tags" -> Map.put(socket.assigns.profile_wizard_draft, "mood_tags", String.split(value, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")))
        "toggle_key" ->
          keys = socket.assigns.profile_wizard_draft["key_preferences"] || []
          updated = if value in keys, do: List.delete(keys, value), else: [value | keys]
          Map.put(socket.assigns.profile_wizard_draft, "key_preferences", updated)
        _ -> socket.assigns.profile_wizard_draft
      end

    {:noreply, assign(socket, :profile_wizard_draft, draft)}
  end

  def handle_event("next_wizard_step", _params, socket) do
    step = min(socket.assigns.profile_wizard_step + 1, 4)
    {:noreply, assign(socket, :profile_wizard_step, step)}
  end

  def handle_event("prev_wizard_step", _params, socket) do
    step = max(socket.assigns.profile_wizard_step - 1, 1)
    {:noreply, assign(socket, :profile_wizard_step, step)}
  end

  def handle_event("save_profile", _params, socket) do
    crate = socket.assigns.active_crate

    if crate do
      profile = Map.put(socket.assigns.profile_wizard_draft, "mode", "guided")

      case CrateDigger.update_crate(crate, %{crate_profile: profile}) do
        {:ok, updated_crate} ->
          crates = Enum.map(socket.assigns.crates, fn c ->
            if c.id == updated_crate.id, do: updated_crate, else: c
          end)
          {:noreply,
           socket
           |> assign(:active_crate, updated_crate)
           |> assign(:crates, crates)
           |> assign(:profile_wizard_open, false)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :profile_wizard_open, false)}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — Spotify playlist browser (v2)
  # ---------------------------------------------------------------------------

  def handle_event("open_playlist_browser", _params, socket) do
    user_id = socket.assigns.current_user_id
    socket = assign(socket, :playlist_browser_open, true)
    socket = assign(socket, :playlist_browser_loading, true)

    send(self(), {:fetch_user_playlists, user_id})
    {:noreply, socket}
  end

  def handle_event("close_playlist_browser", _params, socket) do
    {:noreply, assign(socket, :playlist_browser_open, false)}
  end

  def handle_event("toggle_playlist_selection", %{"url" => url}, socket) do
    selected = socket.assigns.selected_playlist_urls

    updated =
      if MapSet.member?(selected, url),
        do: MapSet.delete(selected, url),
        else: MapSet.put(selected, url)

    {:noreply, assign(socket, :selected_playlist_urls, updated)}
  end

  def handle_event("set_mega_crate_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :mega_crate_name, name)}
  end

  def handle_event("import_selected_playlists", _params, socket) do
    urls = MapSet.to_list(socket.assigns.selected_playlist_urls)
    name = socket.assigns.mega_crate_name
    user_id = socket.assigns.current_user_id

    if Enum.empty?(urls) or name == "" do
      {:noreply, socket}
    else
      socket = assign(socket, :playlist_browser_loading, true)
      send(self(), {:import_multi_playlists, urls, name, user_id})
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — Stem Interchange Lab (v2)
  # ---------------------------------------------------------------------------

  def handle_event("set_stem_donor", %{"stem" => stem, "donor" => donor_id}, socket) do
    crate = socket.assigns.active_crate
    track = socket.assigns.inspector_track

    if crate && track do
      assignments = Map.put(socket.assigns.stem_lab_assignments, stem, donor_id)
      spotify_track_id = track["spotify_id"]

      # Build extended stem_override
      enabled_stems = Map.keys(assignments) |> Enum.reject(fn s -> assignments[s] == "own" end)
      blend = assignments |> Enum.reject(fn {_s, v} -> v == "own" end) |> Map.new()

      stem_override = %{
        "enabled_stems" => if(Enum.empty?(enabled_stems), do: ["vocals", "drums", "bass", "other"], else: ["vocals", "drums", "bass", "other"]),
        "blend_assignments" => blend
      }

      CrateDigger.set_track_stem_override(crate.id, spotify_track_id, stem_override["enabled_stems"])
      {:noreply, assign(socket, :stem_lab_assignments, assignments)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset_stem_lab", _params, socket) do
    crate = socket.assigns.active_crate
    track = socket.assigns.inspector_track

    if crate && track do
      CrateDigger.set_track_stem_override(crate.id, track["spotify_id"], nil)
    end

    {:noreply, assign(socket, :stem_lab_assignments, %{})}
  end

  # ---------------------------------------------------------------------------
  # Events — Sequencer (v2)
  # ---------------------------------------------------------------------------

  def handle_event("set_sequence_arc", %{"arc" => arc}, socket) do
    {:noreply, assign(socket, :sequence_arc, String.to_existing_atom(arc))}
  end

  def handle_event("generate_sequence", _params, socket) do
    crate = socket.assigns.active_crate
    arc = socket.assigns.sequence_arc

    if crate do
      case SoundForge.CrateDigger.Sequencer.sequence(crate, arc) do
        {:ok, ordered_tracks} ->
          {:noreply, assign(socket, :crate_sequence, ordered_tracks)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("send_sequence_to_deck", _params, socket) do
    if socket.assigns.crate_sequence do
      Phoenix.PubSub.broadcast(
        SoundForge.PubSub,
        "dj:commands",
        {:crate_sequence, socket.assigns.crate_sequence}
      )
    end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — Pagination (v2)
  # ---------------------------------------------------------------------------

  def handle_event("set_track_page", %{"page" => page_str}, socket) do
    page = parse_int(page_str, 1)
    {:noreply, assign(socket, :track_page, page)}
  end

  # ---------------------------------------------------------------------------
  # Events — Export (v2)
  # ---------------------------------------------------------------------------

  def handle_event("export_crate_json", _params, socket) do
    crate = socket.assigns.active_crate

    if crate do
      data = %{
        name: crate.name,
        source_type: crate.source_type,
        profile: crate.crate_profile,
        tracks: crate.playlist_data
      }

      json = Jason.encode!(data, pretty: true)
      filename = "#{crate.name |> String.replace(~r/[^a-zA-Z0-9]/, "_")}_crate.json"

      {:noreply,
       socket
       |> push_event("download_file", %{filename: filename, content: json, mime: "application/json"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("export_crate_csv", _params, socket) do
    crate = socket.assigns.active_crate

    if crate do
      header = "title,artist,spotify_id,duration_ms\n"

      rows =
        Enum.map_join(crate.playlist_data, "\n", fn t ->
          [t["title"] || "", t["artist"] || "", t["spotify_id"] || "", to_string(t["duration_ms"] || "")]
          |> Enum.map(&("\"" <> String.replace(&1, "\"", "\"\"") <> "\""))
          |> Enum.join(",")
        end)

      csv = header <> rows
      filename = "#{crate.name |> String.replace(~r/[^a-zA-Z0-9]/, "_")}_tracks.csv"

      {:noreply,
       socket
       |> push_event("download_file", %{filename: filename, content: csv, mime: "text/csv"})}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — Batch analysis (v2)
  # ---------------------------------------------------------------------------

  def handle_event("analyze_all_tracks", _params, socket) do
    crate = socket.assigns.active_crate
    user_id = socket.assigns.current_user_id

    if crate && user_id do
      send(self(), {:enqueue_crate_analysis, crate, user_id})
    end

    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Info handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:load_playlist, url, user_id}, socket) do
    case CrateDigger.load_spotify_playlist(user_id, url) do
      {:ok, crate} ->
        crates = CrateDigger.list_crates(user_id)

        socket =
          socket
          |> assign(:crates, crates)
          |> assign(:active_crate, CrateDigger.get_crate(crate.id))
          |> assign(:playlist_loading, false)
          |> assign(:playlist_url, "")

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:playlist_loading, false)
          |> assign(:playlist_error, "Failed to load playlist: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  def handle_info({:fetch_whosampled, spotify_id, artist, title}, socket) do
    case WhoSampledScraper.fetch_samples(spotify_id, artist, title) do
      {:ok, samples} ->
        socket =
          socket
          |> assign(:whosampled_loading, false)
          |> assign(:whosampled_samples, samples)
          |> assign(:whosampled_error, nil)

        {:noreply, socket}

      {:error, :rate_limited} ->
        socket =
          socket
          |> assign(:whosampled_loading, false)
          |> assign(:whosampled_error, :rate_limited)

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("WhoSampled fetch failed: #{inspect(reason)}")

        socket =
          socket
          |> assign(:whosampled_loading, false)
          |> assign(:whosampled_error, :fetch_error)

        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # MIDI action handlers — universal transport controls
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:midi_action, :play, _params}, socket) do
    # Play the currently inspected track, or select+push-play the first track
    case socket.assigns.inspector_track do
      nil ->
        tracks = active_tracks(socket)

        case tracks do
          [first | _] ->
            {:noreply,
             socket
             |> assign(:inspector_track, first)
             |> assign(:inspector_open, true)
             |> assign(:now_playing_id, first["spotify_id"])
             |> assign(:playback_state, :playing)
             |> push_event("crate_play_track", %{
               spotify_id: first["spotify_id"],
               preview_url: first["preview_url"]
             })}

          [] ->
            {:noreply, socket}
        end

      track ->
        {:noreply,
         socket
         |> assign(:now_playing_id, track["spotify_id"])
         |> assign(:playback_state, :playing)
         |> push_event("crate_play_track", %{
           spotify_id: track["spotify_id"],
           preview_url: track["preview_url"]
         })}
    end
  end

  def handle_info({:midi_action, :stop, _params}, socket) do
    {:noreply, push_event(socket, "crate_stop_playback", %{})}
  end

  def handle_info({:midi_action, :next_track, _params}, socket) do
    tracks = active_tracks(socket)
    current = socket.assigns.inspector_track

    next =
      case current do
        nil ->
          List.first(tracks)

        track ->
          idx = Enum.find_index(tracks, fn t -> t["spotify_id"] == track["spotify_id"] end)

          if idx && idx + 1 < length(tracks) do
            Enum.at(tracks, idx + 1)
          else
            List.first(tracks)
          end
      end

    case next do
      nil ->
        {:noreply, socket}

      track ->
        {:noreply,
         socket
         |> assign(:inspector_track, track)
         |> assign(:now_playing_id, track["spotify_id"])
         |> assign(:playback_state, :playing)
         |> push_event("crate_play_track", %{
           spotify_id: track["spotify_id"],
           preview_url: track["preview_url"]
         })}
    end
  end

  def handle_info({:midi_action, :prev_track, _params}, socket) do
    tracks = active_tracks(socket)
    current = socket.assigns.inspector_track

    prev =
      case current do
        nil ->
          List.last(tracks)

        track ->
          idx = Enum.find_index(tracks, fn t -> t["spotify_id"] == track["spotify_id"] end)

          if idx && idx > 0 do
            Enum.at(tracks, idx - 1)
          else
            List.last(tracks)
          end
      end

    case prev do
      nil ->
        {:noreply, socket}

      track ->
        {:noreply,
         socket
         |> assign(:inspector_track, track)
         |> assign(:now_playing_id, track["spotify_id"])
         |> assign(:playback_state, :playing)
         |> push_event("crate_play_track", %{
           spotify_id: track["spotify_id"],
           preview_url: track["preview_url"]
         })}
    end
  end

  def handle_info({:midi_action, :bpm_tap, _params}, socket) do
    # BPM tap is not applicable to CrateDigger — no-op
    {:noreply, socket}
  end

  def handle_info({:midi_action, _action, _params}, socket) do
    # All other MIDI actions not handled by CrateDigger
    {:noreply, socket}
  end

  # Global MIDI bar events
  def handle_info({:midi_global_event, port_id, msg}, socket) do
    send_update(SoundForgeWeb.Live.Components.GlobalMidiBarComponent,
      id: "global-midi-bar",
      midi_event: {port_id, msg}
    )
    {:noreply, socket}
  end

  def handle_info({:global_midi_bar, :toggle_monitor, open}, socket) do
    {:noreply, assign(socket, :midi_monitor_open, open)}
  end

  def handle_info({:global_midi_bar, :toggle_learn, active}, socket) do
    {:noreply, assign(socket, :midi_learn_active, active)}
  end

  def handle_info({:global_midi_bar, :set_position, pos}, socket) do
    {:noreply, assign(socket, :midi_bar_position, pos)}
  end

  # v2: Fetch user playlists from Spotify
  def handle_info({:fetch_user_playlists, _user_id}, socket) do
    alias SoundForge.Spotify

    playlists =
      case Spotify.list_user_playlists(socket.assigns.current_user) do
        {:ok, list} -> list
        _ -> []
      end

    {:noreply,
     socket
     |> assign(:user_playlists, playlists)
     |> assign(:playlist_browser_loading, false)}
  end

  # v2: Import multiple playlists into a mega-crate
  def handle_info({:import_multi_playlists, urls, name, user_id}, socket) do
    case CrateDigger.load_multiple_playlists(user_id, urls, name) do
      {:ok, crate} ->
        crates = [crate | Enum.reject(socket.assigns.crates, &(&1.id == crate.id))]

        {:noreply,
         socket
         |> assign(:crates, crates)
         |> assign(:active_crate, crate)
         |> assign(:playlist_browser_open, false)
         |> assign(:playlist_browser_loading, false)
         |> assign(:selected_playlist_urls, MapSet.new())
         |> assign(:mega_crate_name, "")}

      {:error, _reason} ->
        {:noreply, assign(socket, :playlist_browser_loading, false)}
    end
  end

  # v2: Enqueue analysis for all unanalyzed tracks in a crate
  def handle_info({:enqueue_crate_analysis, crate, user_id}, socket) do
    spotify_ids =
      crate.playlist_data
      |> Enum.map(& &1["spotify_id"])
      |> Enum.reject(&is_nil/1)

    Enum.each(spotify_ids, fn spotify_id ->
      track = SoundForge.Music.get_track_by_spotify_id(spotify_id)

      if track && is_nil(track.analysis_status) do
        %{"track_id" => track.id, "user_id" => user_id}
        |> SoundForge.Jobs.AnalysisWorker.new()
        |> Oban.insert()
      end
    end)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-950 text-gray-100 overflow-hidden">
      <!-- CratePlayback hook sentinel — manages Spotify 30s preview Audio element -->
      <div id="crate-playback" phx-hook="CratePlayback" class="hidden"></div>
      <SoundForgeWeb.Live.Components.AppHeader.app_header
        nav_tab={:crate}
        nav_context={@nav_context}
        current_scope={@current_scope}
        current_user_id={@current_user_id}
        midi_devices={@midi_devices}
        midi_bpm={@midi_bpm}
        midi_transport={@midi_transport}
        pipelines={@pipelines}
        refreshing_midi={@refreshing_midi}
      />

      <!-- Main layout -->
      <div class="flex flex-1 overflow-hidden relative">
        <!-- Left panel: crate list + import -->
        <aside class="w-64 shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col overflow-hidden">
          <div class="px-4 pt-4 pb-3 border-b border-gray-800 shrink-0">
            <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Import Playlist</h2>
            <form phx-submit="import_playlist" phx-change="update_playlist_url" class="space-y-2">
              <input
                type="text"
                name="url"
                value={@playlist_url}
                placeholder="Spotify playlist URL"
                class="w-full px-3 py-1.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-200 placeholder-gray-600 focus:outline-none focus:border-purple-500"
                disabled={@playlist_loading}
              />
              <button
                type="submit"
                class="w-full px-3 py-1.5 text-xs font-medium bg-purple-600 hover:bg-purple-500 rounded text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={@playlist_loading or @playlist_url == ""}
              >
                <%= if @playlist_loading, do: "Loading...", else: "Import" %>
              </button>
            </form>
            <p :if={@playlist_error} class="mt-2 text-xs text-red-400">{@playlist_error}</p>
            <div class="mt-2 pt-2 border-t border-gray-800/50">
              <button phx-click="open_playlist_browser"
                class="w-full text-[10px] py-1.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 transition-colors flex items-center justify-center gap-1">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h7"/></svg>
                Browse My Spotify Library
              </button>
            </div>
          </div>

          <!-- Crate list -->
          <div class="flex-1 overflow-y-auto py-2">
            <!-- Empty state -->
            <div :if={@crates == []} class="px-4 py-8 text-center">
              <%= vinyl_icon_lg() %>
              <p class="mt-3 text-xs text-gray-500">Import a Spotify playlist to start digging</p>
            </div>

            <ul class="space-y-0.5 px-2">
              <li :for={crate <- @crates} class="group/crate">
                <!-- Rename mode -->
                <div :if={@rename_crate_id == crate.id} class="flex items-center gap-1 px-1 py-1">
                  <form phx-submit="save_rename_crate" phx-change="update_rename_crate" class="flex-1 flex gap-1">
                    <input
                      type="text"
                      name="name"
                      value={@rename_crate_name}
                      autofocus
                      class="flex-1 min-w-0 px-2 py-1 text-xs bg-gray-800 border border-purple-500 rounded text-gray-200 focus:outline-none"
                    />
                    <button type="submit" class="px-2 py-1 text-xs bg-purple-600 hover:bg-purple-500 rounded text-white shrink-0">✓</button>
                  </form>
                  <button phx-click="cancel_rename_crate" class="p-1 text-gray-500 hover:text-white transition-colors">
                    <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>
                  </button>
                </div>

                <!-- Normal row -->
                <div :if={@rename_crate_id != crate.id} class="flex items-center rounded">
                  <button
                    phx-click="select_crate"
                    phx-value-id={crate.id}
                    class={[
                      "flex-1 flex items-start gap-2 px-2 py-2 rounded-l text-left transition-colors text-xs min-w-0",
                      if(@active_crate && @active_crate.id == crate.id,
                        do: "bg-purple-600/20 text-purple-300",
                        else: "text-gray-400 hover:bg-gray-800 hover:text-white"
                      )
                    ]}
                  >
                    <%= vinyl_icon_sm() %>
                    <div class="flex-1 min-w-0">
                      <p class="font-medium truncate">{crate.name}</p>
                      <p class="text-gray-600 truncate">{length(crate.playlist_data || [])} tracks</p>
                    </div>
                  </button>

                  <!-- Action buttons (visible on hover) -->
                  <div class="flex items-center gap-0 shrink-0 opacity-0 group-hover/crate:opacity-100 transition-opacity">
                    <button
                      phx-click="refresh_crate"
                      phx-value-id={crate.id}
                      title="Refresh from Spotify"
                      disabled={@crate_refreshing_id == crate.id}
                      class="p-1.5 text-gray-500 hover:text-blue-400 hover:bg-gray-800 transition-colors disabled:opacity-40"
                    >
                      <svg class={["w-3 h-3", if(@crate_refreshing_id == crate.id, do: "animate-spin", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                      </svg>
                    </button>
                    <button
                      phx-click="start_rename_crate"
                      phx-value-id={crate.id}
                      phx-value-name={crate.name}
                      title="Rename"
                      class="p-1.5 text-gray-500 hover:text-purple-400 hover:bg-gray-800 transition-colors"
                    >
                      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
                      </svg>
                    </button>
                    <button
                      phx-click="delete_crate"
                      phx-value-id={crate.id}
                      title="Delete crate"
                      class="p-1.5 text-gray-500 hover:text-red-400 hover:bg-gray-800 rounded-r transition-colors"
                    >
                      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                      </svg>
                    </button>
                  </div>
                </div>
              </li>
            </ul>
          </div>
        </aside>

        <!-- Center panel: track list -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Stem config bar -->
          <div :if={@active_crate} class="flex items-center gap-3 px-4 py-2.5 bg-gray-900/50 border-b border-gray-800 shrink-0">
            <span class="text-xs text-gray-500">Stems:</span>
            <%= for stem <- ["vocals", "drums", "bass", "other"] do %>
              <button
                phx-click="toggle_stem"
                phx-value-stem={stem}
                class={[
                  "px-2.5 py-1 rounded text-xs font-medium transition-colors",
                  if(stem in (@active_crate.stem_config["enabled_stems"] || []),
                    do: "bg-purple-600 text-white",
                    else: "bg-gray-800 text-gray-500 hover:bg-gray-700"
                  )
                ]}
              >
                {stem}
              </button>
            <% end %>
            <span class="ml-2 text-xs text-gray-600">
              Playing: {Enum.join(@active_crate.stem_config["enabled_stems"] || [], " + ")}
            </span>
          </div>

          <!-- v2: Crate profile badge + wizard trigger + sequence controls -->
          <div :if={@active_crate} class="flex items-center gap-2 px-4 py-1.5 bg-gray-900/30 border-b border-gray-800/60 shrink-0">
            <%!-- Profile badge --%>
            <% profile = @active_crate.crate_profile || %{} %>
            <span class={[
              "text-[9px] px-2 py-0.5 rounded-full font-medium",
              cond do
                profile["mode"] == "guided" -> "bg-green-900/60 text-green-400"
                profile["mode"] == "auto" -> "bg-blue-900/60 text-blue-400"
                true -> "bg-gray-800 text-gray-600"
              end
            ]}>
              {cond do
                profile["mode"] == "guided" -> "Profile: Guided"
                profile["mode"] == "auto" -> "Profile: Auto (#{profile["bpm_center"]} BPM)"
                true -> "No Profile"
              end}
            </span>
            <button
              phx-click="open_profile_wizard"
              class="text-[9px] px-2 py-0.5 rounded bg-gray-800 text-gray-400 hover:bg-gray-700 transition-colors"
            >
              {if map_size(profile) > 0, do: "Edit Profile", else: "Define Profile"}
            </button>
            <%!-- Sequencer arc buttons --%>
            <div class="ml-auto flex items-center gap-1">
              <%= for {label, arc} <- [{"Rise", :rise}, {"Fall", :fall}, {"Peak", :peak}, {"Flat", :flat}] do %>
                <button
                  phx-click="set_sequence_arc"
                  phx-value-arc={arc}
                  class={[
                    "text-[9px] px-1.5 py-0.5 rounded transition-colors",
                    if(@sequence_arc == arc, do: "bg-purple-700 text-purple-200", else: "bg-gray-800 text-gray-500 hover:bg-gray-700")
                  ]}
                >
                  {label}
                </button>
              <% end %>
              <button
                phx-click="generate_sequence"
                class="text-[9px] px-2 py-0.5 rounded bg-purple-900/50 text-purple-300 hover:bg-purple-800 transition-colors ml-1"
              >
                Sequence
              </button>
              <button
                :if={@crate_sequence}
                phx-click="send_sequence_to_deck"
                class="text-[9px] px-2 py-0.5 rounded bg-green-900/50 text-green-300 hover:bg-green-800 transition-colors"
                title="Send sequence to DJ deck"
              >
                → Deck
              </button>
            </div>
          </div>

          <!-- Track filter bar -->
          <div :if={@active_crate && length(@active_crate.playlist_data || []) > 5} class="px-4 py-2 border-b border-gray-800 shrink-0">
            <form phx-change="filter_tracks">
              <input
                type="text"
                name="query"
                value={@track_filter}
                placeholder="Filter tracks…"
                phx-debounce="150"
                class="w-full px-3 py-1.5 text-xs bg-gray-800/80 border border-gray-700 rounded text-gray-200 placeholder-gray-600 focus:outline-none focus:border-purple-500 transition-colors"
              />
            </form>
          </div>

          <!-- Track list -->
          <div class="flex-1 overflow-y-auto" id="crate-track-list" phx-click="close_context_menu">
            <!-- No active crate -->
            <div :if={is_nil(@active_crate)} class="flex flex-col items-center justify-center h-full text-center px-8">
              <%= vinyl_icon_lg() %>
              <p class="mt-4 text-gray-500 text-sm">Select a crate to view tracks</p>
            </div>

            <!-- Skeleton loading -->
            <div :if={@active_crate && @playlist_loading} class="divide-y divide-gray-800">
              <%= for _i <- 1..6 do %>
                <div class="flex items-center gap-3 px-4 py-3 animate-pulse">
                  <div class="w-10 h-10 rounded bg-gray-800 shrink-0"></div>
                  <div class="flex-1 space-y-2">
                    <div class="h-3 bg-gray-800 rounded w-2/3"></div>
                    <div class="h-2.5 bg-gray-800 rounded w-1/3"></div>
                  </div>
                  <div class="h-2.5 bg-gray-800 rounded w-10"></div>
                </div>
              <% end %>
            </div>

            <!-- Track rows -->
            <div :if={@active_crate && not @playlist_loading} class="divide-y divide-gray-800/50">
              <% filtered = filter_tracks(@active_crate.playlist_data || [], @track_filter) %>
              <div :if={filtered == []} class="flex flex-col items-center justify-center py-16 text-center px-8">
                <p class="text-gray-500 text-sm">
                  <%= if @track_filter != "", do: "No tracks match "#{@track_filter}"", else: "No tracks in this playlist" %>
                </p>
              </div>

              <%= for {track, idx} <- Enum.with_index(filtered) do %>
                <% original_idx = Enum.find_index(@active_crate.playlist_data || [], &(&1["spotify_id"] == track["spotify_id"])) || idx %>
                <div class="relative group/track">
                  <div
                    class={[
                      "flex items-center gap-3 px-4 py-2.5 cursor-pointer hover:bg-gray-800/40 transition-colors",
                      if(@inspector_track && @inspector_track["spotify_id"] == track["spotify_id"],
                        do: "bg-purple-900/20",
                        else: ""
                      )
                    ]}
                    phx-click="open_inspector"
                    phx-value-index={original_idx}
                  >
                  <!-- Artwork -->
                  <div class="w-10 h-10 rounded bg-gray-800 shrink-0 overflow-hidden">
                    <%= if track["artwork_url"] do %>
                      <img src={track["artwork_url"]} alt={track["title"]} class="w-full h-full object-cover" />
                    <% else %>
                      <div class="w-full h-full flex items-center justify-center text-gray-600">
                        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M12 2a10 10 0 100 20A10 10 0 0012 2zm0 3a7 7 0 110 14A7 7 0 0112 5zm0 2a5 5 0 100 10A5 5 0 0012 7zm0 2a3 3 0 110 6A3 3 0 0112 9z"/>
                        </svg>
                      </div>
                    <% end %>
                  </div>

                  <!-- Track info -->
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-gray-200 truncate">{track["title"]}</p>
                    <p class="text-xs text-gray-500 truncate">{track["artist"]}</p>
                  </div>

                  <!-- Play / stop inline button -->
                  <%= if @now_playing_id == track["spotify_id"] and @playback_state == :playing do %>
                    <button
                      phx-click="stop_preview"
                      class="p-1.5 rounded-full bg-purple-600 hover:bg-purple-500 text-white transition-colors shrink-0"
                      title="Stop preview"
                      onclick="event.stopPropagation()"
                    >
                      <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                        <rect x="6" y="6" width="4" height="12" rx="1"/>
                        <rect x="14" y="6" width="4" height="12" rx="1"/>
                      </svg>
                    </button>
                  <% else %>
                    <% play_idx = Enum.find_index(@active_crate.playlist_data || [], &(&1["spotify_id"] == track["spotify_id"])) || original_idx %>
                    <button
                      :if={track["preview_url"]}
                      phx-click="play_track_preview"
                      phx-value-index={play_idx}
                      class="p-1.5 rounded-full bg-gray-700/60 hover:bg-purple-600 text-gray-400 hover:text-white transition-colors shrink-0 opacity-0 group-hover/track:opacity-100"
                      title="Preview 30s"
                      onclick="event.stopPropagation()"
                    >
                      <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M8 5v14l11-7z"/>
                      </svg>
                    </button>
                    <div :if={!track["preview_url"]} class="w-7 shrink-0"></div>
                  <% end %>

                  <!-- Override badge + BPM + key + duration + context menu trigger -->
                  <% analysis = load_analysis(track["spotify_id"]) %>
                  <div class="flex items-center gap-2 shrink-0">
                    <span :if={has_override?(@active_crate, track["spotify_id"])} class="px-1.5 py-0.5 rounded text-xs bg-amber-500/20 text-amber-400 font-medium">
                      override
                    </span>
                    <%= if analysis && analysis.tempo do %>
                      <span class="text-[10px] text-cyan-500 font-mono tabular-nums w-10 text-right" title="BPM">
                        {Float.round(analysis.tempo * 1.0, 1)}
                      </span>
                    <% end %>
                    <%= if analysis && analysis.key do %>
                      <span class="text-[10px] text-purple-400 font-medium w-6 text-center" title="Key">
                        {analysis.key}
                      </span>
                    <% end %>
                    <span :if={analysis} class="w-1.5 h-1.5 rounded-full bg-green-500 shrink-0" title="Analysis available"></span>
                    <span class="text-xs text-gray-600 tabular-nums">{format_duration(track["duration_ms"])}</span>
                    <!-- Reorder buttons -->
                    <div class="flex flex-col gap-0" onclick="event.stopPropagation()">
                      <button
                        :if={original_idx > 0}
                        phx-click="reorder_track"
                        phx-value-spotify_id={track["spotify_id"]}
                        phx-value-direction="up"
                        class="p-0.5 rounded opacity-0 group-hover/track:opacity-100 transition-opacity text-gray-600 hover:text-gray-300 hover:bg-gray-700"
                        title="Move up"
                        onclick="event.stopPropagation()"
                      >
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24"><path d="M12 5l-7 7h14z"/></svg>
                      </button>
                      <button
                        :if={original_idx < length((@active_crate.playlist_data || [])) - 1}
                        phx-click="reorder_track"
                        phx-value-spotify_id={track["spotify_id"]}
                        phx-value-direction="down"
                        class="p-0.5 rounded opacity-0 group-hover/track:opacity-100 transition-opacity text-gray-600 hover:text-gray-300 hover:bg-gray-700"
                        title="Move down"
                        onclick="event.stopPropagation()"
                      >
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24"><path d="M12 19l7-7H5z"/></svg>
                      </button>
                    </div>
                  <!-- Three-dot context menu button -->
                    <button
                      phx-click="open_context_menu"
                      phx-value-index={original_idx}
                      class="p-1 rounded text-gray-500 hover:text-white hover:bg-gray-700 transition-colors"
                      title="Track options"
                      onclick="event.stopPropagation()"
                    >
                      <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>
                      </svg>
                    </button>
                  </div>
                  </div>

                  <!-- Context menu dropdown -->
                  <div
                    :if={@context_menu_track_idx == original_idx}
                    class="absolute right-2 top-full mt-0.5 z-50 w-52 bg-gray-800 rounded-lg shadow-2xl border border-gray-700 py-1"
                    onclick="event.stopPropagation()"
                  >
                    <button phx-click="load_in_tab" phx-value-tab="daw" phx-value-spotify_id={track["spotify_id"]}
                      class="w-full text-left px-3 py-2 text-xs hover:bg-gray-700 text-gray-200 flex items-center gap-2 transition-colors">
                      <svg class="w-3.5 h-3.5 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"/></svg>
                      Load in DAW
                    </button>
                    <button phx-click="load_in_tab" phx-value-tab="dj" phx-value-spotify_id={track["spotify_id"]}
                      class="w-full text-left px-3 py-2 text-xs hover:bg-gray-700 text-gray-200 flex items-center gap-2 transition-colors">
                      <svg class="w-3.5 h-3.5 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3"/></svg>
                      Load in DJ
                    </button>
                    <button phx-click="load_in_tab" phx-value-tab="pads" phx-value-spotify_id={track["spotify_id"]}
                      class="w-full text-left px-3 py-2 text-xs hover:bg-gray-700 text-gray-200 flex items-center gap-2 transition-colors">
                      <svg class="w-3.5 h-3.5 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
                      Load in Pads
                    </button>
                    <div class="border-t border-gray-700 my-1"></div>
                    <button phx-click="load_into_sfa" phx-value-spotify_url={"https://open.spotify.com/track/#{track["spotify_id"]}"}
                      class="w-full text-left px-3 py-2 text-xs hover:bg-gray-700 text-gray-200 flex items-center gap-2 transition-colors">
                      <svg class="w-3.5 h-3.5 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/></svg>
                      Download to Library
                    </button>
                    <button phx-click="redownload_track" phx-value-spotify_url={"https://open.spotify.com/track/#{track["spotify_id"]}"}
                      class="w-full text-left px-3 py-2 text-xs hover:bg-gray-700 text-gray-200 flex items-center gap-2 transition-colors">
                      <svg class="w-3.5 h-3.5 text-orange-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/></svg>
                      Re-download
                    </button>
                    <a
                      href={"https://open.spotify.com/track/#{track["spotify_id"]}"}
                      target="_blank" rel="noopener"
                      class="block px-3 py-2 text-xs hover:bg-gray-700 text-gray-200 flex items-center gap-2 transition-colors"
                      phx-click="close_context_menu"
                    >
                      <svg class="w-3.5 h-3.5 text-green-500" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg>
                      View on Spotify
                    </a>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- v2: Sequence view (shown when sequence generated) --%>
          <div :if={@crate_sequence} class="border-t border-purple-900/40 bg-gray-950 shrink-0">
            <div class="flex items-center justify-between px-4 py-2 border-b border-gray-800/50">
              <span class="text-[10px] font-semibold text-purple-400 uppercase tracking-wider">Sequence ({length(@crate_sequence)} tracks — {@sequence_arc})</span>
              <button phx-click="generate_sequence" class="text-[9px] text-gray-500 hover:text-gray-300">Regenerate</button>
            </div>
            <div class="overflow-x-auto">
              <div class="flex items-center gap-1 px-3 py-2 min-w-0">
                <%= for {track, i} <- Enum.with_index(@crate_sequence, 1) do %>
                  <div class="flex flex-col items-center shrink-0 w-14">
                    <% ring_class = cond do
                         track["_key_compat"] == "compatible" -> "ring-1 ring-green-500/50"
                         track["_key_compat"] == "close" -> "ring-1 ring-yellow-500/30"
                         true -> ""
                       end %>
                    <div class={["w-10 h-10 rounded bg-gray-800 overflow-hidden shrink-0", ring_class]}>
                      <img :if={track["artwork_url"]} src={track["artwork_url"]} class="w-full h-full object-cover" />
                      <div :if={!track["artwork_url"]} class="w-full h-full flex items-center justify-center text-gray-600 text-[8px]">{i}</div>
                    </div>
                    <span :if={track["_bpm_delta"]} class={[
                      "text-[8px] font-mono mt-0.5",
                      cond do
                        track["_bpm_delta"] > 0 -> "text-cyan-500"
                        track["_bpm_delta"] < 0 -> "text-orange-400"
                        true -> "text-gray-600"
                      end
                    ]}>
                      {if track["_bpm_delta"] > 0, do: "+#{track["_bpm_delta"]}", else: "#{track["_bpm_delta"]}"} BPM
                    </span>
                  </div>
                  <span :if={i < length(@crate_sequence)} class="text-gray-700 shrink-0">→</span>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- v2: Export + analyze toolbar --%>
          <div :if={@active_crate} class="flex items-center gap-2 px-4 py-2 border-t border-gray-800/60 bg-gray-950 shrink-0">
            <% health = CrateDigger.crate_health_score(@active_crate) %>
            <span class={[
              "text-[9px] px-2 py-0.5 rounded-full font-medium",
              cond do
                health > 0.7 -> "bg-green-900/50 text-green-400"
                health > 0.3 -> "bg-yellow-900/50 text-yellow-400"
                true -> "bg-red-900/50 text-red-400"
              end
            ]} title="Fraction of tracks with analysis data">
              {round(health * 100)}% analyzed
            </span>
            <button phx-click="analyze_all_tracks"
              class="text-[9px] px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 transition-colors">
              Analyze All
            </button>
            <div class="ml-auto flex items-center gap-1">
              <button phx-click="export_crate_json"
                class="text-[9px] px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 transition-colors">
                Export JSON
              </button>
              <button phx-click="export_crate_csv"
                class="text-[9px] px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 transition-colors">
                Export CSV
              </button>
            </div>
          </div>
        </div>

        <!-- Right panel: inspector (slide in/out) -->
        <div
          class={[
            "absolute top-0 right-0 h-full w-80 bg-gray-900 border-l border-gray-800 flex flex-col z-30 transition-transform duration-300 ease-in-out",
            "md:w-96",
            if(@inspector_open, do: "translate-x-0", else: "translate-x-full")
          ]}
          id="crate-inspector"
        >
          <%= if @inspector_track do %>
            <!-- Inspector header -->
            <div class="flex items-start gap-3 px-4 py-4 border-b border-gray-800 shrink-0">
              <div class="w-12 h-12 rounded bg-gray-800 shrink-0 overflow-hidden">
                <%= if @inspector_track["artwork_url"] do %>
                  <img src={@inspector_track["artwork_url"]} alt={@inspector_track["title"]} class="w-full h-full object-cover" />
                <% else %>
                  <div class="w-full h-full flex items-center justify-center text-gray-600">
                    <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2a10 10 0 100 20A10 10 0 0012 2zm0 3a7 7 0 110 14A7 7 0 0112 5zm0 2a5 5 0 100 10A5 5 0 0012 7zm0 2a3 3 0 110 6A3 3 0 0112 9z"/></svg>
                  </div>
                <% end %>
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-white truncate">{@inspector_track["title"]}</p>
                <p class="text-xs text-gray-400 truncate">{@inspector_track["artist"]}</p>
              </div>
              <!-- Preview play/stop button -->
              <%= if @inspector_track["preview_url"] do %>
                <%= if @now_playing_id == @inspector_track["spotify_id"] and @playback_state == :playing do %>
                  <button
                    phx-click="stop_preview"
                    class="p-1.5 rounded-full bg-purple-600 hover:bg-purple-500 text-white transition-colors shrink-0"
                    title="Stop preview"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                      <rect x="6" y="6" width="4" height="12" rx="1"/>
                      <rect x="14" y="6" width="4" height="12" rx="1"/>
                    </svg>
                  </button>
                <% else %>
                  <% playlist = if @active_crate, do: @active_crate.playlist_data || [], else: [] %>
                  <% idx = Enum.find_index(playlist, fn t -> t["spotify_id"] == @inspector_track["spotify_id"] end) || 0 %>
                  <button
                    phx-click="play_track_preview"
                    phx-value-index={idx}
                    class="p-1.5 rounded-full bg-gray-700 hover:bg-purple-600 text-white transition-colors shrink-0"
                    title="Preview 30s"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M8 5v14l11-7z"/>
                    </svg>
                  </button>
                <% end %>
              <% end %>
              <button phx-click="close_inspector" class="text-gray-500 hover:text-white transition-colors mt-0.5">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Accordion sections -->
            <div class="flex-1 overflow-y-auto divide-y divide-gray-800">

              <!-- WhoSampled -->
              <div>
                <button phx-click="toggle_section" phx-value-section="whosampled" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  WhoSampled
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.whosampled, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.whosampled} class="px-4 pb-3">
                  <div :if={@whosampled_loading} class="flex items-center gap-2 py-4 text-gray-500 text-sm">
                    <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"/></svg>
                    Fetching samples...
                  </div>
                  <div :if={not @whosampled_loading and @whosampled_error == :rate_limited} class="py-4">
                    <p class="text-xs text-amber-400">WhoSampled is rate-limiting requests.</p>
                    <button phx-click="toggle_section" phx-value-section="whosampled" class="mt-2 text-xs text-purple-400 hover:text-purple-300">Retry</button>
                  </div>
                  <div :if={not @whosampled_loading and @whosampled_error not in [nil, :rate_limited]} class="py-4">
                    <p class="text-xs text-red-400">Failed to load sample data.</p>
                    <button phx-click="toggle_section" phx-value-section="whosampled" class="mt-2 text-xs text-purple-400 hover:text-purple-300">Retry</button>
                  </div>
                  <p :if={not @whosampled_loading and is_nil(@whosampled_error) and @whosampled_samples == []} class="py-4 text-xs text-gray-500">No sample data found on WhoSampled.</p>
                  <p :if={not @whosampled_loading and is_nil(@whosampled_samples) and is_nil(@whosampled_error)} class="py-4 text-xs text-gray-500">Expand to load sample data.</p>
                  <div :if={not @whosampled_loading and is_list(@whosampled_samples) and @whosampled_samples != []} class="space-y-3 py-2">
                    <div :for={sample <- @whosampled_samples} class="rounded-md bg-gray-800/50 p-3 space-y-1.5">
                      <div class="flex items-start justify-between gap-2">
                        <div class="min-w-0">
                          <p class="text-sm font-medium text-gray-200 truncate">{sample["title"]}</p>
                          <p class="text-xs text-gray-400">{sample["artist"]}{if sample["year"], do: " · #{sample["year"]}", else: ""}</p>
                        </div>
                        <span class={["px-1.5 py-0.5 rounded text-xs font-medium shrink-0", sample_type_class(sample["sample_type"])]}>{sample["sample_type"]}</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <a :if={sample["spotify_url"]} href={sample["spotify_url"]} target="_blank" rel="noopener" class="text-xs text-green-400 hover:text-green-300">Spotify</a>
                        <a :if={sample["youtube_url"]} href={sample["youtube_url"]} target="_blank" rel="noopener" class="text-xs text-red-400 hover:text-red-300">YouTube</a>
                        <button :if={sample["spotify_url"]} phx-click="load_into_sfa" phx-value-spotify_url={sample["spotify_url"]} class="ml-auto text-xs text-purple-400 hover:text-purple-300">Load into SFA</button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Track Details -->
              <div>
                <button phx-click="toggle_section" phx-value-section="details" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Track Details
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.details, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.details} class="px-4 pb-3">
                  <dl class="space-y-2 py-2 text-xs">
                    <div :if={@inspector_track["album"]} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Album</dt>
                      <dd class="text-gray-300 text-right">{@inspector_track["album"]}</dd>
                    </div>
                    <div :if={format_artists(@inspector_track["artists"])} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Artists</dt>
                      <dd class="text-gray-300 text-right">{format_artists(@inspector_track["artists"])}</dd>
                    </div>
                    <div :if={format_release_date(@inspector_track["release_date"])} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Released</dt>
                      <dd class="text-gray-300 text-right">{format_release_date(@inspector_track["release_date"])}</dd>
                    </div>
                    <div class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Duration</dt>
                      <dd class="text-gray-300 text-right">{format_duration(@inspector_track["duration_ms"])}</dd>
                    </div>
                    <div class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Explicit</dt>
                      <dd class="text-gray-300 text-right">{if @inspector_track["explicit"], do: "Yes", else: "No"}</dd>
                    </div>
                    <div :if={@inspector_track["popularity"]} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Popularity</dt>
                      <dd class="text-gray-300 text-right">{@inspector_track["popularity"]}/100</dd>
                    </div>
                  </dl>
                </div>
              </div>

              <!-- Lyrics -->
              <div>
                <button phx-click="toggle_section" phx-value-section="lyrics" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Lyrics
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.lyrics, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.lyrics} class="px-4 pb-3 py-2">
                  <a
                    href={"https://genius.com/search?q=#{URI.encode("#{@inspector_track["artist"]} #{@inspector_track["title"]}")}"}
                    target="_blank"
                    rel="noopener"
                    class="flex items-center gap-2 text-sm text-yellow-400 hover:text-yellow-300 transition-colors"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"/></svg>
                    View on Genius
                    <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/></svg>
                  </a>
                </div>
              </div>

              <!-- Analysis -->
              <div>
                <button phx-click="toggle_section" phx-value-section="analysis" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Analysis
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.analysis, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.analysis} class="px-4 pb-3">
                  <%= if @inspector_analysis do %>
                    <dl class="space-y-3 py-2 text-xs">
                      <div :if={format_bpm(@inspector_analysis)} class="flex justify-between gap-2">
                        <dt class="text-gray-500">BPM</dt><dd class="text-gray-300">{format_bpm(@inspector_analysis)}</dd>
                      </div>
                      <div :if={format_key(@inspector_analysis)} class="flex justify-between gap-2">
                        <dt class="text-gray-500">Key</dt><dd class="text-gray-300">{format_key(@inspector_analysis)}</dd>
                      </div>
                      <div>
                        <dt class="text-gray-500 mb-1">Energy</dt>
                        <dd>
                          <div class="w-full bg-gray-800 rounded-full h-1.5">
                            <div class="bg-purple-500 h-1.5 rounded-full" style={"width: #{format_energy_pct(@inspector_analysis)}%"}></div>
                          </div>
                        </dd>
                      </div>
                      <div>
                        <dt class="text-gray-500 mb-1.5">Stems</dt>
                        <dd>
                          <div class="grid grid-cols-4 gap-1.5 text-center text-xs">
                            <div :for={stem <- ["vocals", "drums", "bass", "other"]} class={["rounded px-1 py-1.5", if(stem_available?(@inspector_analysis, stem), do: "bg-green-900/40 text-green-400", else: "bg-gray-800 text-gray-600")]}>
                              {stem}
                            </div>
                          </div>
                        </dd>
                      </div>
                    </dl>
                  <% else %>
                    <div class="py-3">
                      <p class="text-xs text-gray-500 mb-3">No analysis data available.</p>
                      <%= if find_sfa_track(@inspector_track["spotify_id"]) do %>
                        <% sfa_track = find_sfa_track(@inspector_track["spotify_id"]) %>
                        <button phx-click="trigger_analysis" phx-value-track_id={sfa_track.id} class="px-3 py-1.5 text-xs bg-purple-600 hover:bg-purple-500 rounded text-white transition-colors">
                          Trigger Analysis
                        </button>
                      <% else %>
                        <p class="text-xs text-gray-600">Track not in SFA library yet. Download it first.</p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Per-track stem override -->
              <div>
                <button phx-click="toggle_section" phx-value-section="stems" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Stem Override
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.stems, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.stems and @active_crate} class="px-4 pb-3 py-2 space-y-3">
                  <% override = get_track_override(@active_crate, @inspector_track["spotify_id"]) %>
                  <% effective = override || @active_crate.stem_config["enabled_stems"] || ["vocals", "drums", "bass", "other"] %>
                  <% is_overridden = not is_nil(override) %>
                  <p class="text-xs text-gray-500">
                    <span :if={is_overridden} class="text-amber-400 font-medium">Per-track override active.</span>
                    <span :if={not is_overridden}>Using playlist default. Toggle stems to override.</span>
                  </p>
                  <div class="flex flex-wrap gap-1.5">
                    <button :for={stem <- ["vocals", "drums", "bass", "other"]}
                      phx-click="toggle_track_stem"
                      phx-value-stem={stem}
                      class={["px-2.5 py-1 rounded text-xs font-medium transition-colors",
                        if(stem in effective,
                          do: if(is_overridden, do: "bg-amber-600 text-white", else: "bg-purple-600 text-white"),
                          else: "bg-gray-800 text-gray-500 hover:bg-gray-700"
                        )
                      ]}
                    >{stem}</button>
                  </div>
                  <button :if={is_overridden} phx-click="clear_track_override" class="text-xs text-gray-400 hover:text-white transition-colors">
                    Reset to playlist default
                  </button>
                </div>
              </div>

              <%!-- v2: Stem Interchange Lab --%>
              <div class="border-t border-gray-800/60">
                <div class="px-4 py-2.5 flex items-center justify-between">
                  <span class="text-xs font-medium text-gray-400">Stem Lab</span>
                  <button phx-click="reset_stem_lab" class="text-[10px] text-gray-600 hover:text-gray-400 transition-colors">Reset All</button>
                </div>
                <div :if={@active_crate && @inspector_track} class="px-4 pb-3 space-y-1.5">
                  <p class="text-[10px] text-gray-600 mb-2">Swap stems between tracks in this crate:</p>
                  <% crate_tracks = @active_crate.playlist_data || [] %>
                  <%= for stem <- ["vocals", "drums", "bass", "other"] do %>
                    <% current_donor = Map.get(@stem_lab_assignments, stem, "own") %>
                    <div class="flex items-center gap-2">
                      <span class={[
                        "w-14 shrink-0 text-[9px] font-mono px-1.5 py-0.5 rounded text-center",
                        if(current_donor != "own", do: "bg-purple-900/50 text-purple-300", else: "bg-gray-800 text-gray-500")
                      ]}>
                        {String.capitalize(stem)}
                        <span :if={current_donor != "own"} class="block w-2 h-2 rounded-full bg-purple-400 mx-auto mt-0.5"></span>
                      </span>
                      <form phx-change="set_stem_donor" class="flex-1">
                        <input type="hidden" name="stem" value={stem} />
                        <select name="donor"
                          class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-[9px] text-gray-300 focus:outline-none focus:border-purple-500">
                          <option value="own" selected={current_donor == "own"}>Own</option>
                          <%= for t <- crate_tracks, t["spotify_id"] != @inspector_track["spotify_id"] do %>
                            <% label = "#{t["title"] || "?"}" |> String.slice(0, 28) %>
                            <option value={t["spotify_id"]} selected={current_donor == t["spotify_id"]}>{label}</option>
                          <% end %>
                        </select>
                      </form>
                    </div>
                  <% end %>
                </div>
              </div>

            </div>
          <% end %>
        </div>

        <!-- Backdrop for mobile -->
        <div
          :if={@inspector_open}
          class="absolute inset-0 bg-black/50 z-20 md:hidden"
          phx-click="close_inspector"
        ></div>
      </div>
      <.live_component
        module={SoundForgeWeb.Live.Components.TransportBarComponent}
        id="transport-bar"
        nav_tab={:crate}
      />
    </div>

    <!-- Delete crate confirmation modal -->
    <div :if={@confirm_delete_crate_id} class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete_crate"></div>
      <div class="relative z-10 bg-gray-900 rounded-xl border border-gray-700 p-6 w-80 shadow-2xl">
        <div class="flex items-center gap-3 mb-3">
          <div class="w-8 h-8 rounded-full bg-red-500/20 flex items-center justify-center shrink-0">
            <svg class="w-4 h-4 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
          </div>
          <h3 class="text-sm font-semibold text-white">Delete Crate?</h3>
        </div>
        <p class="text-xs text-gray-400 mb-5">This permanently deletes the crate and all per-track stem overrides. This cannot be undone.</p>
        <div class="flex gap-2 justify-end">
          <button phx-click="cancel_delete_crate" class="px-4 py-2 text-xs bg-gray-800 hover:bg-gray-700 rounded text-gray-300 transition-colors">
            Cancel
          </button>
          <button phx-click="confirm_delete_crate" phx-value-id={@confirm_delete_crate_id} class="px-4 py-2 text-xs bg-red-600 hover:bg-red-500 rounded text-white font-medium transition-colors">
            Delete
          </button>
        </div>
      </div>
    </div>

    <%!-- v2: Guided Profile Wizard Modal --%>
    <div :if={@profile_wizard_open} class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm">
      <div class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-md mx-4">
        <div class="flex items-center justify-between px-5 py-3.5 border-b border-gray-800">
          <h3 class="text-sm font-semibold text-gray-200">Define Crate Profile</h3>
          <div class="flex items-center gap-3">
            <span class="text-xs text-gray-500">Step {@profile_wizard_step}/4</span>
            <button phx-click="close_profile_wizard" class="text-gray-500 hover:text-white">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>
        </div>
        <div class="px-5 py-4 min-h-[180px]">
          <%!-- Step 1: BPM Range --%>
          <div :if={@profile_wizard_step == 1}>
            <p class="text-xs text-gray-400 mb-3">What BPM range defines this crate?</p>
            <div class="flex items-center gap-4">
              <div class="flex-1">
                <label class="text-[10px] text-gray-500 block mb-1">Min BPM</label>
                <form phx-change="set_profile_field">
                  <input type="hidden" name="field" value="bpm_min" />
                  <input type="range" name="value" min="60" max="200" value={@profile_wizard_draft["bpm_min"] || 120}
                    class="w-full accent-purple-500" phx-debounce="100" />
                  <span class="text-purple-400 text-xs font-mono">{@profile_wizard_draft["bpm_min"] || 120} BPM</span>
                </form>
              </div>
              <div class="flex-1">
                <label class="text-[10px] text-gray-500 block mb-1">Max BPM</label>
                <form phx-change="set_profile_field">
                  <input type="hidden" name="field" value="bpm_max" />
                  <input type="range" name="value" min="60" max="200" value={@profile_wizard_draft["bpm_max"] || 140}
                    class="w-full accent-purple-500" phx-debounce="100" />
                  <span class="text-purple-400 text-xs font-mono">{@profile_wizard_draft["bpm_max"] || 140} BPM</span>
                </form>
              </div>
            </div>
          </div>
          <%!-- Step 2: Key preferences --%>
          <div :if={@profile_wizard_step == 2}>
            <p class="text-xs text-gray-400 mb-3">Select preferred keys (Camelot notation):</p>
            <div class="grid grid-cols-6 gap-1">
              <%= for key <- ~w(1A 2A 3A 4A 5A 6A 7A 8A 9A 10A 11A 12A 1B 2B 3B 4B 5B 6B 7B 8B 9B 10B 11B 12B) do %>
                <form phx-change="set_profile_field">
                  <input type="hidden" name="field" value="toggle_key" />
                  <button type="button" phx-click="set_profile_field" phx-value-field="toggle_key" phx-value-value={key}
                    class={[
                      "w-full text-[9px] py-1 rounded transition-colors",
                      if(key in (@profile_wizard_draft["key_preferences"] || []),
                        do: "bg-purple-600 text-white font-medium",
                        else: "bg-gray-800 text-gray-500 hover:bg-gray-700")
                    ]}>
                    {key}
                  </button>
                </form>
              <% end %>
            </div>
          </div>
          <%!-- Step 3: Energy level --%>
          <div :if={@profile_wizard_step == 3}>
            <p class="text-xs text-gray-400 mb-3">Target energy level for this crate:</p>
            <form phx-change="set_profile_field">
              <input type="hidden" name="field" value="energy_level" />
              <input type="range" name="value" min="0" max="100" value={@profile_wizard_draft["energy_level"] || 70}
                class="w-full accent-purple-500" phx-debounce="100" />
            </form>
            <div class="flex justify-between text-[9px] text-gray-600 mt-1">
              <span>Mellow</span>
              <span class="text-purple-400 font-mono">{@profile_wizard_draft["energy_level"] || 70}%</span>
              <span>Peak</span>
            </div>
          </div>
          <%!-- Step 4: Mood tags --%>
          <div :if={@profile_wizard_step == 4}>
            <p class="text-xs text-gray-400 mb-3">Add mood/genre tags (comma separated):</p>
            <form phx-change="set_profile_field">
              <input type="hidden" name="field" value="mood_tags" />
              <input type="text" name="value"
                value={@profile_wizard_draft["mood_tags"] |> List.wrap() |> Enum.join(", ")}
                placeholder="deep house, hypnotic, driving, 4am..."
                class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-xs text-gray-200 focus:outline-none focus:border-purple-500"
                phx-debounce="300" />
            </form>
            <div class="flex flex-wrap gap-1 mt-2">
              <%= for tag <- (@profile_wizard_draft["mood_tags"] || []) do %>
                <span class="px-2 py-0.5 rounded-full bg-purple-900/50 text-purple-300 text-[9px]">{tag}</span>
              <% end %>
            </div>
          </div>
        </div>
        <div class="flex justify-between px-5 py-3 border-t border-gray-800">
          <button :if={@profile_wizard_step > 1} phx-click="prev_wizard_step"
            class="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 rounded text-gray-300 transition-colors">
            Back
          </button>
          <div :if={@profile_wizard_step == 1} />
          <div class="flex gap-2">
            <button phx-click="close_profile_wizard"
              class="px-3 py-1.5 text-xs text-gray-500 hover:text-gray-300 transition-colors">
              Cancel
            </button>
            <button :if={@profile_wizard_step < 4} phx-click="next_wizard_step"
              class="px-4 py-1.5 text-xs bg-purple-600 hover:bg-purple-500 rounded text-white font-medium transition-colors">
              Next
            </button>
            <button :if={@profile_wizard_step == 4} phx-click="save_profile"
              class="px-4 py-1.5 text-xs bg-green-600 hover:bg-green-500 rounded text-white font-medium transition-colors">
              Save Profile
            </button>
          </div>
        </div>
      </div>
    </div>

    <%!-- v2: Playlist Browser Modal --%>
    <div :if={@playlist_browser_open} class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm">
      <div class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-lg mx-4 flex flex-col" style="max-height: 70vh;">
        <div class="flex items-center justify-between px-5 py-3.5 border-b border-gray-800 shrink-0">
          <h3 class="text-sm font-semibold text-gray-200">Browse Your Spotify Library</h3>
          <button phx-click="close_playlist_browser" class="text-gray-500 hover:text-white">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
          </button>
        </div>
        <div class="flex-1 overflow-y-auto">
          <div :if={@playlist_browser_loading} class="flex items-center justify-center py-12">
            <span class="text-gray-500 text-xs animate-pulse">Loading your playlists...</span>
          </div>
          <div :if={!@playlist_browser_loading && @user_playlists == []} class="px-5 py-8 text-center">
            <p class="text-gray-500 text-xs">No Spotify playlists found. Connect your Spotify account to browse.</p>
          </div>
          <%= for playlist <- @user_playlists do %>
            <div class="flex items-center gap-3 px-4 py-2.5 border-b border-gray-800/50 hover:bg-gray-800/30">
              <input type="checkbox"
                checked={MapSet.member?(@selected_playlist_urls, playlist["url"])}
                phx-click="toggle_playlist_selection"
                phx-value-url={playlist["url"]}
                class="accent-purple-500" />
              <div class="w-8 h-8 rounded bg-gray-800 shrink-0 overflow-hidden">
                <img :if={playlist["image_url"]} src={playlist["image_url"]} class="w-full h-full object-cover" />
              </div>
              <div class="min-w-0">
                <p class="text-xs text-gray-200 truncate">{playlist["name"]}</p>
                <p class="text-[9px] text-gray-600">{playlist["tracks_total"]} tracks</p>
              </div>
            </div>
          <% end %>
        </div>
        <div class="px-5 py-3 border-t border-gray-800 shrink-0">
          <div class="flex items-center gap-3">
            <form phx-change="set_mega_crate_name" class="flex-1">
              <input type="text" name="name" value={@mega_crate_name}
                placeholder="Name your mega-crate..."
                class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-xs text-gray-200 focus:outline-none focus:border-purple-500" />
            </form>
            <span class="text-[10px] text-gray-500">{MapSet.size(@selected_playlist_urls)} selected</span>
            <button
              phx-click="import_selected_playlists"
              disabled={MapSet.size(@selected_playlist_urls) == 0 or @mega_crate_name == ""}
              class="px-3 py-1.5 text-xs bg-purple-600 hover:bg-purple-500 disabled:opacity-40 disabled:cursor-not-allowed rounded text-white font-medium transition-colors shrink-0">
              Import Selected
            </button>
          </div>
        </div>
      </div>
    </div>

    <%!-- Global MIDI Bar — offset 72px to clear TransportBar --%>
    <.live_component
      module={SoundForgeWeb.Live.Components.GlobalMidiBarComponent}
      id="global-midi-bar"
      position={@midi_bar_position}
      visible={true}
      bottom_offset={72}
      midi_monitor_open={@midi_monitor_open}
      midi_learn_active={@midi_learn_active}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_spotify_id_from_url(url) when is_binary(url) do
    case Regex.run(~r{spotify\.com/track/([A-Za-z0-9]+)}, url) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp extract_spotify_id_from_url(_), do: nil

  defp build_track_attrs(inspector_track, spotify_url, spotify_id, user_id) do
    base = %{spotify_url: spotify_url, user_id: user_id, source: "manual"}

    if is_map(inspector_track) do
      Map.merge(base, %{
        spotify_id: spotify_id,
        title: inspector_track["title"] || "Unknown Track",
        artist: inspector_track["artist"],
        album: inspector_track["album"],
        album_art_url: inspector_track["album_art_url"],
        duration: inspector_track["duration"]
      })
    else
      Map.merge(base, %{spotify_id: spotify_id, title: "Unknown Track"})
    end
  end

  defp active_tracks(socket) do
    case socket.assigns.active_crate do
      nil -> []
      crate -> crate.playlist_data || []
    end
  end

  defp filter_tracks(tracks, ""), do: tracks

  defp filter_tracks(tracks, query) when is_binary(query) do
    q = String.downcase(String.trim(query))

    Enum.filter(tracks, fn track ->
      title = String.downcase(track["title"] || "")
      artist = String.downcase(track["artist"] || "")
      album = String.downcase(track["album"] || "")
      String.contains?(title, q) or String.contains?(artist, q) or String.contains?(album, q)
    end)
  end

  defp reload_crates(socket) do
    case socket.assigns.current_user do
      nil -> []
      user -> CrateDigger.list_crates(user.id)
    end
  end

  defp load_analysis(nil), do: nil

  defp load_analysis(spotify_id) do
    # Find by spotify_id on Track, then look up analysis
    import Ecto.Query

    track =
      Repo.one(
        from t in SoundForge.Music.Track,
          where: t.spotify_id == ^spotify_id,
          limit: 1
      )

    if track do
      Music.get_analysis_result_for_track(track.id)
    else
      nil
    end
  end

  defp find_sfa_track(nil), do: nil

  defp find_sfa_track(spotify_id) do
    import Ecto.Query

    Repo.one(
      from t in SoundForge.Music.Track,
        where: t.spotify_id == ^spotify_id,
        limit: 1
    )
  end

  defp has_override?(nil, _), do: false

  defp has_override?(crate, spotify_track_id) do
    Enum.any?(crate.track_configs || [], fn tc ->
      tc.spotify_track_id == spotify_track_id && not is_nil(tc.stem_override)
    end)
  end

  defp get_track_override(nil, _), do: nil

  defp get_track_override(crate, spotify_track_id) do
    case Enum.find(crate.track_configs || [], &(&1.spotify_track_id == spotify_track_id)) do
      %{stem_override: %{"enabled_stems" => stems}} when is_list(stems) -> stems
      _ -> nil
    end
  end

  defp resolve_user(%{id: _} = user, _session), do: user

  defp resolve_user(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _} <- Accounts.get_user_by_session_token(token) do
      user
    else
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  defp format_duration(nil), do: "--:--"

  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    m = div(seconds, 60)
    s = rem(seconds, 60)
    :io_lib.format("~B:~2..0B", [m, s]) |> to_string()
  end

  defp format_duration(_), do: "--:--"

  defp format_artists(nil), do: nil
  defp format_artists([]), do: nil
  defp format_artists(artists) when is_list(artists), do: Enum.join(artists, ", ")
  defp format_artists(artist) when is_binary(artist), do: artist

  defp format_release_date(nil), do: nil

  defp format_release_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        Calendar.strftime(date, "%B %d %Y")

      _ ->
        # year-only fallback
        case Regex.run(~r/^\d{4}/, date_str) do
          [year] -> year
          _ -> date_str
        end
    end
  end

  defp format_release_date(_), do: nil

  defp format_popularity(nil), do: nil
  defp format_popularity(n) when is_integer(n), do: "#{n}/100"
  defp format_popularity(_), do: nil

  defp format_bpm(%{features: %{"tempo" => bpm}}) when is_number(bpm), do: "#{round(bpm)} BPM"
  defp format_bpm(_), do: nil

  defp format_key(%{features: %{"key" => key, "mode" => mode}}) do
    keys = ~w(C C# D D# E F F# G G# A A# B)
    key_name = Enum.at(keys, key || 0, "?")
    mode_name = if mode == 1, do: "Major", else: "Minor"
    "#{key_name} #{mode_name}"
  end

  defp format_key(_), do: nil

  defp format_energy_pct(%{features: %{"energy" => e}}) when is_number(e), do: round(e * 100)
  defp format_energy_pct(_), do: 0

  defp stem_available?(%{features: features}, stem) when is_map(features) do
    Map.get(features, "stems_#{stem}") == true or Map.get(features, stem) == true
  end

  defp stem_available?(_, _), do: false

  defp sample_type_class("direct"), do: "bg-purple-500/20 text-purple-300"
  defp sample_type_class("interpolation"), do: "bg-blue-500/20 text-blue-300"
  defp sample_type_class("replayed"), do: "bg-green-500/20 text-green-300"
  defp sample_type_class(_), do: "bg-gray-700 text-gray-400"

  # ---------------------------------------------------------------------------
  # SVG icons
  # ---------------------------------------------------------------------------

  defp vinyl_icon_sm do
    Phoenix.HTML.raw("""
    <svg class="w-3.5 h-3.5 shrink-0 text-gray-500" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>
    </svg>
    """)
  end

  defp vinyl_icon_lg do
    Phoenix.HTML.raw("""
    <svg class="w-12 h-12 text-gray-700 mx-auto" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>
    </svg>
    """)
  end
end
