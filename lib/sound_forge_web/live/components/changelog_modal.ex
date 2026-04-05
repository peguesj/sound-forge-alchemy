defmodule SoundForgeWeb.Live.Components.ChangelogModal do
  @moduledoc """
  Changelog modal component. Parses CHANGELOG.md at compile time and renders
  a styled, scrollable modal triggered by the version badge in the app header.
  """
  use Phoenix.Component

  @changelog_path Path.expand("../../../../CHANGELOG.md", __DIR__)
  @external_resource @changelog_path

  @changelog_entries (
    try do
      raw = File.read!(@changelog_path)

      raw
      |> String.split("\n## ")
      |> Enum.drop(1)
      |> Enum.map(fn section ->
        lines = String.split(section, "\n")
        header = List.first(lines) || ""
        rest = Enum.drop(lines, 1) |> Enum.join("\n")

        {version, date} =
          case Regex.run(~r/\[([^\]]+)\](?:\s*-\s*(.+))?/, header) do
            [_, v, d] -> {String.trim(v), String.trim(d)}
            [_, v] -> {String.trim(v), nil}
            _ -> {String.trim(header), nil}
          end

        sections =
          rest
          |> String.split("\n### ")
          |> Enum.drop(1)
          |> Enum.map(fn sub ->
            sub_lines = String.split(sub, "\n")
            type = List.first(sub_lines) |> to_string() |> String.trim()

            items =
              Enum.drop(sub_lines, 1)
              |> Enum.map(&String.trim/1)
              |> Enum.filter(&String.starts_with?(&1, "- "))
              |> Enum.map(&String.slice(&1, 2..-1//1))

            %{type: type, items: items}
          end)
          |> Enum.reject(&Enum.empty?(&1.items))

        %{version: version, date: date, sections: sections}
      end)
      |> Enum.reject(&(&1.version == "Unreleased" and Enum.empty?(&1.sections)))
    rescue
      _ -> []
    end
  )

  def changelog_modal(assigns) do
    assigns = assign(assigns, :entries, @changelog_entries)

    ~H"""
    <dialog id="changelog-modal" class="modal">
      <div class="modal-box max-w-2xl max-h-[82vh] bg-gray-900 border border-gray-700 text-white p-0 overflow-hidden flex flex-col">
        <!-- Header -->
        <div class="flex items-center justify-between px-6 py-4 border-b border-gray-700 shrink-0">
          <div>
            <h2 class="text-lg font-bold text-white">Changelog</h2>
            <p class="text-xs text-gray-500">Sound Forge Alchemy — release history</p>
          </div>
          <form method="dialog">
            <button class="p-1.5 rounded-md text-gray-400 hover:text-white hover:bg-gray-700 transition-colors" aria-label="Close">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </form>
        </div>

        <!-- Entry list -->
        <div class="overflow-y-auto flex-1 divide-y divide-gray-800">
          <div :for={{entry, idx} <- Enum.with_index(@entries)} class="px-6 py-4 space-y-3">
            <!-- Version row -->
            <div class="flex items-center gap-2.5">
              <span class={[
                "text-sm font-bold px-2.5 py-0.5 rounded-full",
                if(idx == 0,
                  do: "bg-purple-600 text-white",
                  else: "bg-gray-800 text-gray-300 border border-gray-700"
                )
              ]}>
                v{entry.version}
              </span>
              <span :if={entry.date} class="text-xs text-gray-500">{entry.date}</span>
              <span :if={idx == 0} class="text-[10px] font-semibold uppercase tracking-wide bg-green-900/50 text-green-400 px-1.5 py-0.5 rounded">
                Latest
              </span>
            </div>

            <!-- Sub-sections -->
            <div :for={section <- entry.sections} class="space-y-1.5">
              <p class={["text-[11px] font-bold uppercase tracking-widest", section_color(section.type)]}>
                {section.type}
              </p>
              <ul class="space-y-1 pl-1">
                <li :for={item <- section.items} class="flex items-start gap-2 text-xs text-gray-300 leading-relaxed">
                  <span class="text-gray-600 shrink-0 mt-px select-none">▸</span>
                  <span>{item}</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
    """
  end

  defp section_color("Added"), do: "text-green-400"
  defp section_color("Fixed"), do: "text-blue-400"
  defp section_color("Changed"), do: "text-yellow-400"
  defp section_color("Removed"), do: "text-red-400"
  defp section_color("Security"), do: "text-orange-400"
  defp section_color("Deprecated"), do: "text-amber-400"
  defp section_color(_), do: "text-gray-400"
end
