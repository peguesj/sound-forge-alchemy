defmodule SoundForge.Encrypted.Binary do
  @moduledoc """
  An Ecto type that transparently encrypts/decrypts binary data
  using SoundForge.Vault (AES-GCM-256).

  Usage in schemas:

      field :api_key, SoundForge.Encrypted.Binary
  """
  use Cloak.Ecto.Binary, vault: SoundForge.Vault
end
