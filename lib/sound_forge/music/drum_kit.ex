defmodule SoundForge.Music.DrumKit do
  @moduledoc """
  A DrumKit groups Splice (or other) audio samples into a pad layout.

  Each kit has up to `pad_count` slots. Each slot references a track_id
  and maps to a MIDI note for playback.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  @valid_sources ~w(splice manual import)

  schema "drum_kits" do
    field :name, :string
    field :description, :string
    field :source, :string, default: "splice"
    # slots: list of %{slot: int, track_id: int, label: string, note: int}
    field :slots, {:array, :map}, default: []
    field :bpm, :float
    field :pad_count, :integer, default: 16
    field :is_public, :boolean, default: false

    belongs_to :user, SoundForge.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(drum_kit, attrs) do
    drum_kit
    |> cast(attrs, [:name, :description, :user_id, :source, :slots, :bpm, :pad_count, :is_public])
    |> validate_required([:name, :user_id])
    |> validate_inclusion(:source, @valid_sources)
    |> validate_number(:pad_count, greater_than: 0, less_than_or_equal_to: 64)
    |> validate_slots()
  end

  defp validate_slots(changeset) do
    case get_change(changeset, :slots) do
      nil -> changeset
      slots ->
        if Enum.all?(slots, &valid_slot?/1) do
          changeset
        else
          add_error(changeset, :slots, "each slot must have slot, track_id, label, and note")
        end
    end
  end

  defp valid_slot?(slot) when is_map(slot) do
    Map.has_key?(slot, "slot") or Map.has_key?(slot, :slot)
  end

  defp valid_slot?(_), do: false
end
