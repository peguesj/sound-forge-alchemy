defmodule SoundForge.Vault do
  @moduledoc """
  Cloak encryption vault for AES-GCM-256 encryption of sensitive data
  (API keys, tokens, etc.).

  Key resolution order:
    1. LLM_ENCRYPTION_KEY env var (Base64-encoded 32-byte key)
    2. First 32 bytes derived from SECRET_KEY_BASE via SHA-256
  """
  use Cloak.Vault, otp_app: :sound_forge
end
