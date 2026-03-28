defmodule SoundForge.CrateDigger.Crate do
  @moduledoc """
  A Crate represents a curated or imported collection of tracks.

  ## Source types
    - `"playlist"` — single Spotify playlist
    - `"album"` — Spotify album import
    - `"folder"` — aggregated from multiple playlists (Spotify folder analogue)
    - `"manual"` — user-assembled manually

  ## Crate profile
  The `crate_profile` field holds discovered or guided audio fingerprint:
    - `bpm_center`, `bpm_stddev` — BPM cluster statistics
    - `top_keys` — list of most common Camelot keys
    - `energy_mean`, `energy_range` — energy statistics
    - `mood_tags` — user-defined or AI-suggested mood/genre tags
    - `mode` — `"auto"` (SimilarityEngine-computed) or `"guided"` (user-set)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_source_types ~w(playlist album folder manual)

  schema "crates" do
    field :name, :string
    field :spotify_playlist_id, :string
    field :playlist_data, {:array, :map}, default: []
    field :stem_config, :map, default: %{"enabled_stems" => ["vocals", "drums", "bass", "other"]}
    # v2 fields
    field :source_type, :string, default: "playlist"
    field :collection_id, :binary_id
    field :crate_profile, :map, default: %{}
    field :source_urls, {:array, :string}, default: []

    belongs_to :user, SoundForge.Accounts.User, type: :integer
    belongs_to :collection, SoundForge.CrateDigger.CrateCollection,
      foreign_key: :collection_id,
      define_field: false

    has_many :track_configs, SoundForge.CrateDigger.CrateTrackConfig

    timestamps()
  end

  @doc false
  def changeset(crate, attrs) do
    crate
    |> cast(attrs, [
      :name, :spotify_playlist_id, :playlist_data, :stem_config, :user_id,
      :source_type, :collection_id, :crate_profile, :source_urls
    ])
    |> validate_required([:name, :spotify_playlist_id, :user_id])
    |> validate_inclusion(:source_type, @valid_source_types)
  end
end
