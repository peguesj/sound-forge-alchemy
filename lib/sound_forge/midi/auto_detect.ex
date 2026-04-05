defmodule SoundForge.MIDI.AutoDetect do
  @moduledoc """
  AI-assisted MIDI controller auto-detection.

  Given one or more raw MIDI signals captured in learn mode, identifies the
  controller make/model and returns a suggested mapping set.

  ## Detection Strategy

  1. **Fast path (ETS)**: check `SoundForge.MIDI.ControllerRegistry` — if the
     signal matches a known fingerprint, return immediately with 95% confidence.
  2. **LLM fallback**: if the registry has no match, build a structured prompt
     and route through `SoundForge.LLM.Router` using the cheapest/fastest
     provider available (prefer speed, fallback to quality).

  ## Return Values

      # Registry hit — synchronous, < 5ms
      {:ok, %{
        controller: %{model: "Akai MPC Live II", manufacturer: "...", ...},
        suggested_mappings: [...],
        confidence: 0.95,
        source: :registry
      }}

      # LLM detection — asynchronous-friendly, < 5s
      {:ok, %{
        controller: %{model: "...", manufacturer: "..."},
        suggested_mappings: [...],
        confidence: 0.80,
        source: :llm
      }}

      # Unknown
      {:error, :unknown}
  """

  alias SoundForge.MIDI.{ControllerFingerprints, Mappings}
  alias SoundForge.LLM.Router
  require Logger

  @type signal :: %{
          required(:msg_type) => atom(),
          required(:channel) => integer(),
          required(:number) => integer(),
          optional(:value) => integer()
        }

  @type detection_result :: %{
          controller: map(),
          suggested_mappings: [map()],
          confidence: float(),
          source: :registry | :llm
        }

  @doc """
  Detects the controller model from a list of observed MIDI signals.

  Tries the ETS registry fast path first, then falls back to the LLM.

  ## Parameters
  - `signals` — list of signal maps with at minimum `:msg_type`, `:channel`,
    `:number` keys (usually 3–5 signals from button presses)
  - `user_id` — required for LLM routing (provider selection)

  ## Returns
  `{:ok, detection_result()}` or `{:error, reason}`
  """
  @spec detect_controller([signal()], term()) ::
          {:ok, detection_result()} | {:error, term()}
  def detect_controller(signals, user_id \\ nil)

  def detect_controller([], _user_id), do: {:error, :no_signals}

  def detect_controller(signals, user_id) when is_list(signals) do
    case ControllerFingerprints.lookup(signals) do
      {:ok, controller_name, confidence} ->
        build_registry_result(controller_name, confidence, user_id)

      :unknown ->
        Logger.debug("MIDI.AutoDetect: registry miss — falling back to LLM")
        detect_via_llm(signals, user_id)
    end
  end

  @spec detect_controller(signal(), term()) :: {:ok, detection_result()} | {:error, term()}
  def detect_controller(%{msg_type: _} = signal, user_id) do
    detect_controller([signal], user_id)
  end

  # ---------------------------------------------------------------------------
  # Registry path
  # ---------------------------------------------------------------------------

  defp build_registry_result(controller_name, confidence, user_id) do
    # Try to get the full controller info from the registry
    controllers = ControllerFingerprints.list_controllers()
    controller_info = Enum.find(controllers, &(&1.model == controller_name)) || %{model: controller_name}

    suggested = build_suggested_mappings(controller_name, user_id)

    result = %{
      controller: controller_info,
      suggested_mappings: suggested,
      confidence: confidence,
      source: :registry
    }

    {:ok, result}
  end

  defp build_suggested_mappings(controller_name, user_id) when not is_nil(user_id) do
    case Mappings.insert_preset_for_controller(user_id, controller_name) do
      {:ok, _results} ->
        # Return the preset definition without inserting
        Mappings.default_mpc_live2_preset(user_id)

      {:error, :unknown_controller} ->
        []
    end
  end

  defp build_suggested_mappings(_controller_name, nil), do: []

  # ---------------------------------------------------------------------------
  # LLM fallback path
  # ---------------------------------------------------------------------------

  defp detect_via_llm(_signals, nil) do
    {:error, :no_user_id_for_llm}
  end

  defp detect_via_llm(signals, user_id) do
    prompt = build_detection_prompt(signals)

    messages = [
      %{
        role: "user",
        content: prompt
      }
    ]

    task_spec = %{
      task_type: :analysis,
      prefer: :speed,
      max_tokens: 512,
      temperature: 0.2,
      system: llm_system_prompt()
    }

    case Router.route(user_id, messages, task_spec) do
      {:ok, response} ->
        parse_llm_response(response.content, signals, user_id)

      {:error, reason} ->
        Logger.warning("MIDI.AutoDetect LLM fallback failed: #{inspect(reason)}")
        {:error, :llm_unavailable}
    end
  end

  defp llm_system_prompt do
    """
    You are a MIDI controller identification expert. Given a list of MIDI signals
    (message type, channel, CC/note number), identify the most likely controller make
    and model.

    Known controller fingerprints:
    - Akai MPC Live II: CC 118=play, CC 117=stop, CC 119=rec (channel 0)
    - Ableton Push 2: CC 85=play, CC 86=rec, CC 87=overdub (channel 0)
    - Novation Launchpad X: Note 19=play, Note 9=stop (channel 0)
    - Akai APC40 Mk2: Note 91=play, Note 92=stop, Note 93=rec (channel 0)
    - Maschine Mikro Mk3: CC 108=play (channel 0)

    Respond ONLY with a JSON object in this exact format:
    {
      "model": "Controller Model Name",
      "manufacturer": "Manufacturer Name",
      "confidence": 0.85,
      "reason": "Brief explanation"
    }

    If you cannot identify the controller, use model: "Unknown Controller" with
    confidence 0.0.
    """
  end

  defp build_detection_prompt(signals) do
    signal_lines =
      signals
      |> Enum.map(fn s ->
        type = Atom.to_string(s.msg_type)
        "  - #{type} ch=#{s.channel} num=#{s.number}#{if s[:value], do: " val=#{s.value}", else: ""}"
      end)
      |> Enum.join("\n")

    """
    Identify the MIDI controller that produced these signals:

    #{signal_lines}

    Respond with JSON only.
    """
  end

  defp parse_llm_response(content, _signals, _user_id) when is_nil(content) do
    {:error, :empty_llm_response}
  end

  defp parse_llm_response(content, _signals, _user_id) do
    # Strip markdown code fences if present
    cleaned =
      content
      |> String.replace(~r/```json\n?/, "")
      |> String.replace(~r/```\n?/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"model" => model, "manufacturer" => mfr, "confidence" => confidence}} ->
        result = %{
          controller: %{model: model, manufacturer: mfr},
          suggested_mappings: [],
          confidence: confidence,
          source: :llm
        }

        {:ok, result}

      {:ok, _other} ->
        {:error, :invalid_llm_json_shape}

      {:error, reason} ->
        Logger.warning("MIDI.AutoDetect: failed to parse LLM JSON: #{inspect(reason)}")
        {:error, :llm_parse_error}
    end
  end
end
