defmodule SoundForgeWeb.UserSessionHTML do
  use SoundForgeWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:sound_forge, SoundForge.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
