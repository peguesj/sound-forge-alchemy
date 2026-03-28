defmodule SoundForge.MIDI.ModulePreset do
  @moduledoc """
  Schema for per-module MIDI presets. Each preset stores a named collection
  of MIDI mappings for a specific application module (dj, daw, crate, etc.)
  and optional layout metadata (controller name, grid size, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  @valid_modules ~w(dj daw crate pads library settings)
  @valid_sources ~w(custom tsi serato rekordbox touchosc bundled)

  schema "midi_module_presets" do
    belongs_to :user, SoundForge.Accounts.User, type: :integer
    field :module, :string
    field :name, :string
    field :is_default, :boolean, default: false
    field :source, :string, default: "custom"
    field :mappings, :map, default: %{}
    field :layout_metadata, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [:user_id, :module, :name, :is_default, :source, :mappings, :layout_metadata])
    |> validate_required([:user_id, :module, :name, :mappings])
    |> validate_inclusion(:module, @valid_modules)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_length(:name, min: 1, max: 80)
  end
end
