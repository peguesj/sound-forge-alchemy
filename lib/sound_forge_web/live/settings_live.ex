defmodule SoundForgeWeb.SettingsLive do
  @moduledoc """
  Settings LiveView for per-user preferences and Spotify OAuth management.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Settings
  alias SoundForge.Spotify.OAuth
  alias SoundForge.Accounts.UserSettings
  alias SoundForge.Audio.SpotDL
  alias SoundForge.Audio.LalalAI
  alias SoundForge.LLM.{Providers, Provider, Client}

  @sections ~w(spotify downloads youtube demucs cloud_separation analysis storage control_surfaces general advanced ai_providers)a

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
      |> assign(:lalalai_configured, lalalai_configured?(user_id))
      |> assign(:lalalai_api_key_input, "")
      |> assign(:lalalai_testing, false)
      |> assign(:lalalai_test_result, nil)
      |> assign(:lalalai_quota, nil)
      |> assign(:form_dirty, false)
      |> assign_form(changeset)
      |> assign_provider_assigns(user_id)

    if connected?(socket), do: :timer.send_interval(60_000, self(), :refresh_quota)

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

  def handle_event("lalalai_key_input", %{"key" => key}, socket) do
    {:noreply, assign(socket, :lalalai_api_key_input, key)}
  end

  def handle_event("test_lalalai_key", _params, socket) do
    key = socket.assigns.lalalai_api_key_input

    if key == "" do
      {:noreply, assign(socket, :lalalai_test_result, {:error, "Please enter an API key"})}
    else
      socket = assign(socket, :lalalai_testing, true)
      lv_pid = self()

      Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
        result = LalalAI.test_api_key(key)
        send(lv_pid, {:lalalai_test_result, result, key})
      end)

      {:noreply, socket}
    end
  end

  def handle_event("save_lalalai_key", _params, socket) do
    user_id = socket.assigns.current_user_id
    key = socket.assigns.lalalai_api_key_input

    if user_id && key != "" do
      case Settings.save_lalalai_api_key(user_id, key) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:lalalai_configured, true)
           |> assign(:lalalai_test_result, nil)
      |> assign(:lalalai_quota, nil)
           |> put_flash(:info, "lalal.ai API key saved.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save API key.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please enter an API key.")}
    end
  end

  def handle_event("remove_lalalai_key", _params, socket) do
    user_id = socket.assigns.current_user_id

    if user_id do
      case Settings.save_lalalai_api_key(user_id, nil) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:lalalai_configured, false)
           |> assign(:lalalai_api_key_input, "")
           |> assign(:lalalai_test_result, nil)
      |> assign(:lalalai_quota, nil)
           |> put_flash(:info, "lalal.ai API key removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove API key.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_add_provider", _params, socket) do
    changeset = Providers.change_provider(%Provider{})

    {:noreply,
     socket
     |> assign(:provider_form_mode, :new)
     |> assign(:provider_editing_id, nil)
     |> assign(:provider_form, to_form(changeset, as: "provider"))}
  end

  def handle_event("cancel_provider_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:provider_form_mode, nil)
     |> assign(:provider_editing_id, nil)
     |> assign(:provider_form, nil)}
  end

  def handle_event("validate_provider", %{"provider" => params}, socket) do
    provider =
      case socket.assigns.provider_editing_id do
        nil -> %Provider{}
        id -> Providers.get_provider!(id)
      end

    changeset =
      provider
      |> Providers.change_provider(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :provider_form, to_form(changeset, as: "provider"))}
  end

  def handle_event("save_provider", %{"provider" => params}, socket) do
    user_id = socket.assigns.current_user_id

    result =
      case socket.assigns.provider_editing_id do
        nil ->
          Providers.create_provider(user_id, params)

        id ->
          provider = Providers.get_provider!(id)
          Providers.update_provider(provider, params)
      end

    case result do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> assign_provider_assigns(user_id)
         |> assign(:provider_form_mode, nil)
         |> assign(:provider_editing_id, nil)
         |> assign(:provider_form, nil)
         |> put_flash(:info, "Provider saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :provider_form, to_form(changeset, as: "provider"))}
    end
  end

  def handle_event("edit_provider", %{"id" => id}, socket) do
    provider = Providers.get_provider!(id)
    changeset = Providers.change_provider(provider)

    {:noreply,
     socket
     |> assign(:provider_form_mode, :edit)
     |> assign(:provider_editing_id, id)
     |> assign(:provider_form, to_form(changeset, as: "provider"))}
  end

  def handle_event("delete_provider", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user_id
    provider = Providers.get_provider!(id)

    case Providers.delete_provider(provider) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign_provider_assigns(user_id)
         |> put_flash(:info, "Provider removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove provider.")}
    end
  end

  def handle_event("toggle_provider", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user_id
    provider = Providers.get_provider!(id)

    case Providers.toggle_provider(provider) do
      {:ok, _} ->
        {:noreply, assign_provider_assigns(socket, user_id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle provider.")}
    end
  end

  def handle_event("test_provider", %{"id" => id}, socket) do
    provider = Providers.get_provider!(id)
    lv_pid = self()

    socket = assign(socket, :provider_testing_id, id)

    Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
      result = Client.test_connection(provider)
      send(lv_pid, {:provider_test_result, id, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_quota, socket) do
    lv_pid = self()

    Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
      result = LalalAI.get_quota()
      send(lv_pid, {:lalalai_quota_result, result})
    end)

    {:noreply, socket}
  end

  def handle_info({:lalalai_quota_result, result}, socket) do
    case result do
      {:ok, minutes} ->
        {:noreply, assign(socket, :lalalai_quota, minutes)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:lalalai_test_result, result, key}, socket) do
    case result do
      {:ok, :valid} ->
        user_id = socket.assigns.current_user_id

        # Auto-save on successful test
        if user_id do
          Settings.save_lalalai_api_key(user_id, key)
        end

        {:noreply,
         socket
         |> assign(:lalalai_testing, false)
         |> assign(:lalalai_configured, true)
         |> assign(:lalalai_test_result, {:ok, "API key is valid and has been saved."})
         |> put_flash(:info, "lalal.ai API key verified and saved.")}

      {:error, :invalid_api_key} ->
        {:noreply,
         socket
         |> assign(:lalalai_testing, false)
         |> assign(:lalalai_test_result, {:error, "Invalid API key. Please check and try again."})}

      {:error, :empty_api_key} ->
        {:noreply,
         socket
         |> assign(:lalalai_testing, false)
         |> assign(:lalalai_test_result, {:error, "API key cannot be empty."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:lalalai_testing, false)
         |> assign(:lalalai_test_result, {:error, "Connection failed: #{inspect(reason)}"})}
    end
  end

  def handle_info({:provider_test_result, id, result}, socket) do
    user_id = socket.assigns.current_user_id
    provider = Providers.get_provider!(id)
    health = if match?(:ok, result), do: :healthy, else: :unreachable

    provider
    |> Provider.changeset(%{health_status: health, last_health_check_at: DateTime.utc_now()})
    |> SoundForge.Repo.update()

    {flash_type, flash_msg} =
      case result do
        :ok -> {:info, "Provider connection successful."}
        {:error, reason} -> {:error, "Connection failed: #{inspect(reason)}"}
      end

    {:noreply,
     socket
     |> assign_provider_assigns(user_id)
     |> assign(:provider_testing_id, nil)
     |> put_flash(flash_type, flash_msg)}
  end

  # Handle Task.Supervisor async task results
  @impl true
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, :lalalai_testing, false)}
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

  defp lalalai_configured?(nil), do: LalalAI.configured?()

  defp lalalai_configured?(user_id) do
    LalalAI.configured_for_user?(user_id)
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
  defp section_label(:cloud_separation), do: "Cloud Separation"
  defp section_label(:analysis), do: "Analysis"
  defp section_label(:storage), do: "Storage"
  defp section_label(:general), do: "General"
  defp section_label(:advanced), do: "Advanced"
  defp section_label(:ai_providers), do: "AI Providers"

  defp assign_provider_assigns(socket, user_id) do
    providers = if user_id, do: Providers.list_providers(user_id), else: []

    socket
    |> assign(:llm_providers, providers)
    |> assign(:provider_form_mode, nil)
    |> assign(:provider_editing_id, nil)
    |> assign(:provider_form, nil)
    |> assign(:provider_testing_id, nil)
  end

  defp provider_type_label(:anthropic), do: "Anthropic"
  defp provider_type_label(:openai), do: "OpenAI"
  defp provider_type_label(:azure_openai), do: "Azure OpenAI"
  defp provider_type_label(:google_gemini), do: "Google Gemini"
  defp provider_type_label(:ollama), do: "Ollama"
  defp provider_type_label(:lm_studio), do: "LM Studio"
  defp provider_type_label(:litellm), do: "LiteLLM"
  defp provider_type_label(:custom_openai), do: "Custom OpenAI"

  defp provider_health_class(:healthy), do: "bg-green-500"
  defp provider_health_class(:degraded), do: "bg-yellow-500"
  defp provider_health_class(:unreachable), do: "bg-red-500"
  defp provider_health_class(_), do: "bg-gray-500"
end
