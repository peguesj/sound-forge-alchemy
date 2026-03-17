defmodule SoundForge.BigLoopy.LoopExtractor do
  @moduledoc """
  Elixir wrapper around priv/python/loop_extractor.py.

  Extracts a loop segment from an audio file (WAV/MP3/AIFF/FLAC) by
  calling the Python script via System.cmd/3 and returning the path to
  the extracted WAV file.

  ## Usage

      iex> LoopExtractor.extract_loop("/path/to/stem.wav", 4.0, 8.0)
      {:ok, "/path/to/output.wav"}

  """

  require Logger

  @python_script "priv/python/loop_extractor.py"
  @output_dir "priv/static/uploads/loops"

  @doc """
  Extracts a loop segment from `input_path` between `start_seconds` and `end_seconds`.

  Returns `{:ok, output_path}` on success or `{:error, reason}` on failure.
  The output WAV is written to `priv/static/uploads/loops/<unique_name>.wav`.
  """
  @spec extract_loop(String.t(), float(), float()) :: {:ok, String.t()} | {:error, term()}
  def extract_loop(input_path, start_seconds, end_seconds)
      when is_binary(input_path) and is_number(start_seconds) and is_number(end_seconds) do
    output_path = build_output_path(input_path, start_seconds, end_seconds)
    script_path = Application.app_dir(:sound_forge, @python_script)
    output_abs = Path.join(File.cwd!(), output_path)

    args = [
      script_path,
      "--input", input_path,
      "--start", to_string(start_seconds),
      "--end", to_string(end_seconds),
      "--output", output_abs
    ]

    Logger.debug("[LoopExtractor] Extracting loop #{start_seconds}s-#{end_seconds}s from #{Path.basename(input_path)}")

    case System.cmd("python3", args, stderr_to_stdout: true) do
      {output, 0} ->
        parse_python_output(output, output_abs)

      {output, exit_code} ->
        Logger.warning("[LoopExtractor] Python exit #{exit_code}: #{String.trim(output)}")
        {:error, {:python_exit, exit_code, String.trim(output)}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_output_path(input_path, start_seconds, end_seconds) do
    base = Path.basename(input_path, Path.extname(input_path))
    unique = :erlang.unique_integer([:positive])
    filename = "#{base}_#{round(start_seconds * 1000)}_#{round(end_seconds * 1000)}_#{unique}.wav"
    Path.join(@output_dir, filename)
  end

  defp parse_python_output(output, output_path) do
    # The Python script prints a JSON line as the last line of output
    lines = output |> String.trim() |> String.split("\n")
    json_line = List.last(lines) || ""

    case Jason.decode(json_line) do
      {:ok, %{"ok" => true}} ->
        {:ok, output_path}

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      {:error, _} ->
        Logger.warning("[LoopExtractor] Could not parse Python output: #{json_line}")
        # If the file exists despite parse failure, consider it a success
        if File.exists?(output_path) do
          {:ok, output_path}
        else
          {:error, :output_file_missing}
        end
    end
  end
end
