defmodule SoundForge.Accounts.SpotifyOAuthToken do
  @moduledoc """
  Encrypted Spotify OAuth2 tokens for a user.
  Access and refresh tokens are encrypted at rest using Phoenix.Token.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "spotify_oauth_tokens" do
    belongs_to :user, SoundForge.Accounts.User

    field :access_token, :binary
    field :refresh_token, :binary
    field :token_type, :string, default: "Bearer"
    field :expires_at, :utc_datetime
    field :scopes, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:access_token, :refresh_token, :token_type, :expires_at, :scopes, :user_id])
    |> validate_required([:access_token, :refresh_token, :expires_at, :user_id])
    |> unique_constraint(:user_id)
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) != :lt
  end

  def expired?(_), do: true
end
