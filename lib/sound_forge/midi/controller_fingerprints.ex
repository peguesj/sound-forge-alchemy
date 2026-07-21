defmodule SoundForge.MIDI.ControllerFingerprints do
  @moduledoc """
  ETS-backed GenServer registry of known MIDI controller fingerprints.

  On startup, loads seed data from `priv/midi/controller_registry.json`
  into an ETS table keyed by `{msg_type, channel, number}` signal tuples.
  Multiple signature signals may map to the same controller.

  ## ETS Table: `:midi_controller_fingerprints`

  Each entry is keyed by `{msg_type, channel, number}` and stores:

      %{
        model: String.t(),
        manufacturer: String.t(),
        slug: String.t(),
        cc_map: map(),
        note_map: map()
      }

  ## Public API

      iex> SoundForge.MIDI.ControllerFingerprints.lookup_by_signal(:cc, 0, 118)
      {:ok, %{model: "Akai MPC Live II", manufacturer: "Akai Professional", ...}}

      iex> SoundForge.MIDI.ControllerFingerprints.lookup_by_signal(:cc, 0, 99)
      :not_found

      iex> SoundForge.MIDI.ControllerFingerprints.list_controllers()
      [%{model: "Akai MPC Live II", ...}, ...]
  """

  use GenServer

  require Logger

  @table :midi_controller_fingerprints
  @seed_file "priv/midi/controller_registry.json"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the ControllerFingerprints GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Looks up a controller by a single MIDI signal (msg_type, channel, number).

  Returns `{:ok, controller_info}` on a match, `:not_found` otherwise.
  This is a direct ETS lookup and completes in < 5ms.

  ## Parameters
  - `msg_type` - `:cc`, `:note_on`, or `:note_off`
  - `channel` - MIDI channel (0–15)
  - `number` - CC number or note number (0–127)
  """
  @spec lookup_by_signal(atom(), integer(), integer()) ::
          {:ok, map()} | :not_found
  def lookup_by_signal(msg_type, channel, number) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, {msg_type, channel, number}) do
        [{_key, controller_info}] -> {:ok, controller_info}
        [] -> :not_found
      end
    else
      :not_found
    end
  end

  @doc """
  Returns all registered controllers (deduplicated by slug).
  """
  @spec list_controllers() :: [map()]
  def list_controllers do
    if :ets.whereis(@table) != :undefined do
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, controller} -> controller end)
      |> Enum.uniq_by(& &1.slug)
    else
      []
    end
  end

  @doc """
  Finds the best matching controller from a list of observed signals.

  Tries each signal in order; returns the first match with its confidence
  level (`:high` for named-signal match, `:low` for generic fallback).

  Returns `{:ok, controller_info, confidence}` or `:unknown`.
  """
  @spec lookup(list(map())) :: {:ok, String.t(), float()} | :unknown
  def lookup(signals) when is_list(signals) do
    result =
      Enum.find_value(signals, fn %{msg_type: msg_type, channel: channel, number: number} ->
        case lookup_by_signal(msg_type, channel, number) do
          {:ok, info} -> info
          :not_found -> nil
        end
      end)

    case result do
      nil -> :unknown
      info -> {:ok, info.model, 0.95}
    end
  end

  def lookup(_), do: :unknown

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_seed_data()
    Logger.info("MIDI.ControllerFingerprints started — #{controller_count()} controllers loaded")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp load_seed_data do
    seed_path = Application.app_dir(:sound_forge, @seed_file)

    case File.read(seed_path) do
      {:ok, raw_json} ->
        case Jason.decode(raw_json) do
          {:ok, %{"controllers" => controllers}} ->
            Enum.each(controllers, &index_controller/1)

          {:error, reason} ->
            Logger.error(
              "MIDI.ControllerFingerprints: failed to parse seed JSON: #{inspect(reason)}"
            )
        end

      {:error, _} ->
        # Fall back to relative path when not running as a release
        relative_path =
          Path.join(:code.priv_dir(:sound_forge) |> to_string(), "midi/controller_registry.json")

        case File.read(relative_path) do
          {:ok, raw_json} ->
            case Jason.decode(raw_json) do
              {:ok, %{"controllers" => controllers}} ->
                Enum.each(controllers, &index_controller/1)

              {:error, reason} ->
                Logger.error(
                  "MIDI.ControllerFingerprints: failed to parse seed JSON: #{inspect(reason)}"
                )
            end

          {:error, reason} ->
            Logger.warning(
              "MIDI.ControllerFingerprints: seed file not found (#{inspect(reason)}), " <>
                "starting with built-in MPC Live II fingerprint"
            )

            load_builtin_seeds()
        end
    end
  end

  defp index_controller(%{"model" => model, "manufacturer" => mfr, "slug" => slug} = controller) do
    cc_map = Map.get(controller, "cc_map", %{})
    note_map = Map.get(controller, "note_map", %{})
    signatures = Map.get(controller, "signatures", [])

    info = %{
      model: model,
      manufacturer: mfr,
      slug: slug,
      cc_map: cc_map,
      note_map: note_map
    }

    Enum.each(signatures, fn sig ->
      msg_type = String.to_atom(sig["msg_type"])
      channel = sig["channel"]
      number = sig["number"]
      :ets.insert(@table, {{msg_type, channel, number}, info})
    end)
  end

  defp index_controller(bad_entry) do
    Logger.warning("MIDI.ControllerFingerprints: skipping malformed entry: #{inspect(bad_entry)}")
  end

  # Fallback hard-coded seeds in case JSON file is unavailable
  defp load_builtin_seeds do
    mpc_info = %{
      model: "Akai MPC Live II",
      manufacturer: "Akai Professional",
      slug: "mpc_live2",
      cc_map: %{
        "117" => "stop",
        "118" => "play",
        "119" => "rec"
      },
      note_map: %{}
    }

    :ets.insert(@table, {{:cc, 0, 118}, mpc_info})
    :ets.insert(@table, {{:cc, 0, 117}, mpc_info})
    :ets.insert(@table, {{:cc, 0, 119}, mpc_info})
  end

  defp controller_count do
    if :ets.whereis(@table) != :undefined do
      list_controllers() |> length()
    else
      0
    end
  end
end
