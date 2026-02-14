defmodule SoundForgeWeb.SettingsLive do
  @moduledoc """
  Settings LiveView for per-user preferences and Spotify OAuth management.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Settings
  alias SoundForge.Spotify.OAuth
  alias SoundForge.Accounts.UserSettings
  alias SoundForge.Audio.SpotDL

  @sections ~w(spotify downloads youtube demucs analysis storage general)a

  @impl true
  def mount(_params, session, socket) do
    user_id = resolve_user_id(socket, session)
    settings = Settings.get_user_settings(user_id) || %UserSettings{user_id: user_id}
    defaults = Settings.defaults()
    spotify_linked = if user_id, do: OAuth.linked?(user_id), else: false

    changeset = Settings.change_user_settings(settings)

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:current_user_id, user_id)
      |> assign(:section, :spotify)
      |> assign(:settings, settings)
      |> assign(:defaults, defaults)
      |> assign(:spotify_linked, spotify_linked)
      |> assign(:spotdl_available, SpotDL.available?())
      |> assign(:ffmpeg_available, ffmpeg_available?())
      |> assign(:form_dirty, false)
      |> assign_form(changeset)

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_section", %{"section" => section}, socket) do
    {:noreply,
     socket
     |> assign(:section, String.to_existing_atom(section))
     |> push_event("focus_section_heading", %{section: section})}
  end

  def handle_event("validate", %{"user_settings" => params}, socket) do
    changeset =
      (socket.assigns.settings || %UserSettings{})
      |> Settings.change_user_settings(params)
      |> Map.put(:action, :validate)

    dirty = params_differ_from_saved?(params, socket.assigns.settings)

    {:noreply,
     socket
     |> assign(:form_dirty, dirty)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"user_settings" => params}, socket) do
    user_id = socket.assigns.current_user_id

    case Settings.save_user_settings(user_id, params) do
      {:ok, updated} ->
        changeset = Settings.change_user_settings(updated)

        {:noreply,
         socket
         |> assign(:settings, updated)
         |> assign(:form_dirty, false)
         |> assign_form(changeset)
         |> put_flash(:info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("reset_section", %{"section" => section}, socket) do
    user_id = socket.assigns.current_user_id
    section_atom = String.to_existing_atom(section)

    case Settings.reset_section(user_id, section_atom) do
      {:ok, _} ->
        settings = Settings.get_user_settings(user_id) || %UserSettings{user_id: user_id}
        changeset = Settings.change_user_settings(settings)

        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign(:form_dirty, false)
         |> assign_form(changeset)
         |> put_flash(:info, "#{String.capitalize(section)} settings reset to defaults.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reset settings.")}
    end
  end

  def handle_event("link_spotify", _params, socket) do
    # LiveView can't write to session directly, so redirect to a controller
    # that sets session state and redirects to Spotify
    {:noreply, redirect(socket, to: ~p"/auth/spotify")}
  end

  def handle_event("unlink_spotify", _params, socket) do
    user_id = socket.assigns.current_user_id

    case OAuth.unlink(user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:spotify_linked, false)
         |> put_flash(:info, "Spotify account unlinked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unlink Spotify.")}
    end
  end

  # -- Private --

  defp resolve_user_id(socket, session) do
    case socket.assigns[:current_scope] do
      %{user: %{id: id}} ->
        id

      _ ->
        with token when is_binary(token) <- session["user_token"],
             {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
          user.id
        else
          _ -> nil
        end
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user_settings"))
  end

  defp ffmpeg_available? do
    is_binary(System.find_executable("ffmpeg"))
  end

  defp params_differ_from_saved?(params, nil), do: params != %{}

  defp params_differ_from_saved?(params, %UserSettings{} = settings) do
    settings_map =
      settings
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id, :user_id, :inserted_at, :updated_at, :user])
      |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), normalize_value(v)} end)

    normalized_params =
      params
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Enum.into(%{}, fn {k, v} -> {k, normalize_value(v)} end)

    Enum.any?(normalized_params, fn {key, val} ->
      saved = Map.get(settings_map, key)
      saved != val
    end)
  end

  defp normalize_value(v) when is_integer(v), do: Integer.to_string(v)

  defp normalize_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v),
    do: Atom.to_string(v)

  defp normalize_value(v) when is_list(v),
    do: Enum.map(v, &normalize_value/1) |> Enum.sort()

  defp normalize_value(v), do: v

  def sections, do: @sections

  defp section_label(:spotify), do: "Spotify"
  defp section_label(:downloads), do: "Downloads"
  defp section_label(:youtube), do: "YouTube / yt-dlp"
  defp section_label(:demucs), do: "Demucs"
  defp section_label(:analysis), do: "Analysis"
  defp section_label(:storage), do: "Storage"
  defp section_label(:general), do: "General"
end
