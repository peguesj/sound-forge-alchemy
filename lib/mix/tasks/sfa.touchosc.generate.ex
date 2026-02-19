defmodule Mix.Tasks.Sfa.Touchosc.Generate do
  @moduledoc "Generates a TouchOSC layout file for the SFA stem mixer."
  @shortdoc "Generate TouchOSC layout"

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.shell().info("Generating TouchOSC layout...")

    output_dir = Path.join(["priv", "touchosc"])
    File.mkdir_p!(output_dir)
    output_path = Path.join(output_dir, "sfa_mixer.tosc")

    xml = SoundForge.OSC.TouchOSCLayout.generate_xml()

    # .tosc files are ZIP archives containing index.xml
    {:ok, zip_binary} = :zip.create("sfa_mixer.tosc", [{~c"index.xml", xml}], [:memory])
    File.write!(output_path, zip_binary)

    Mix.shell().info("Layout written to #{output_path}")
  end
end
