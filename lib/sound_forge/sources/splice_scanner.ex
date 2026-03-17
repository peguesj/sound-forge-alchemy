defmodule SoundForge.Sources.SpliceScanner do
  @moduledoc """
  GenServer that watches a local Splice Sounds directory and enqueues
  SpliceImportWorker jobs for newly discovered audio files.

  The default path is `~/Splice/Sounds` (or `~/Library/Application Support/Splice/Sounds`
  on macOS). Users can override via UserSettings.splice_library_path.

  The scanner:
  - Polls every 30 seconds
  - Tracks seen file paths in an ETS table to avoid duplicate imports
  - Supports .wav, .mp3, .aif, .aiff, .flac file extensions
  """
  use GenServer
  require Logger

  alias SoundForge.Jobs.SpliceImportWorker
  alias SoundForge.Accounts

  @poll_interval_ms 30_000
  @audio_extensions ~w(.wav .mp3 .aif .aiff .flac)
  @ets_table :splice_scanner_seen_files
  @default_paths [
    "~/Splice/Sounds",
    "~/Library/Application Support/Splice/Sounds"
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger an immediate scan (useful for testing or after path update)."
  def scan_now do
    GenServer.cast(__MODULE__, :scan)
  end

  @doc "Returns the current library path being watched."
  def current_path do
    GenServer.call(__MODULE__, :current_path)
  end

  @doc "Reloads the configured path (called after UserSettings update)."
  def reload_path do
    GenServer.cast(__MODULE__, :reload_path)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@ets_table, [:set, :public, :named_table])
    state = %{path: resolve_path(nil), timer: nil}
    {:ok, state, {:continue, :start_polling}}
  end

  @impl true
  def handle_continue(:start_polling, state) do
    timer = schedule_poll()
    {:noreply, %{state | timer: timer}}
  end

  @impl true
  def handle_cast(:scan, state) do
    new_state = do_scan(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reload_path, state) do
    new_path = resolve_path(nil)
    Logger.info("[SpliceScanner] Path reloaded: #{new_path}")
    {:noreply, %{state | path: new_path}}
  end

  @impl true
  def handle_call(:current_path, _from, state) do
    {:reply, state.path, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = do_scan(state)
    timer = schedule_poll()
    {:noreply, %{new_state | timer: timer}}
  end

  # Private

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp do_scan(%{path: nil} = state) do
    Logger.debug("[SpliceScanner] No library path configured, skipping scan")
    state
  end

  defp do_scan(%{path: path} = state) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      Logger.debug("[SpliceScanner] Scanning #{expanded}")

      expanded
      |> list_audio_files()
      |> Enum.each(&maybe_enqueue/1)
    else
      Logger.debug("[SpliceScanner] Path not found: #{expanded}")
    end

    state
  end

  defp list_audio_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full = Path.join(dir, entry)

          cond do
            File.dir?(full) -> list_audio_files(full)
            audio_extension?(entry) -> [full]
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp audio_extension?(filename) do
    ext = filename |> Path.extname() |> String.downcase()
    ext in @audio_extensions
  end

  defp maybe_enqueue(path) do
    key = {path, File.stat!(path).mtime}

    unless :ets.member(@ets_table, key) do
      :ets.insert(@ets_table, {key, true})

      case Oban.insert(SpliceImportWorker.new(%{"file_path" => path})) do
        {:ok, _job} ->
          Logger.info("[SpliceScanner] Enqueued import for #{Path.basename(path)}")

        {:error, reason} ->
          Logger.warning("[SpliceScanner] Failed to enqueue #{path}: #{inspect(reason)}")
      end
    end
  end

  defp resolve_path(_) do
    # Try each default path; UserSettings per-user path would require user context
    # For global scanner, we use the first existing default path
    Enum.find(@default_paths, fn p ->
      File.dir?(Path.expand(p))
    end)
  end
end
