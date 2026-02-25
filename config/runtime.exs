import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/sound_forge start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# Load .env file in dev/test (Phoenix doesn't auto-load .env)
if config_env() in [:dev, :test] do
  env_file = Path.join(File.cwd!(), ".env")

  if File.exists?(env_file) do
    for line <- File.stream!(env_file),
        line = String.trim(line),
        line != "" and not String.starts_with?(line, "#"),
        [key | rest] = String.split(line, "=", parts: 2),
        value = List.first(rest, "") do
      System.put_env(String.trim(key), String.trim(value))
    end
  end
end

if System.get_env("PHX_SERVER") do
  config :sound_forge, SoundForgeWeb.Endpoint, server: true
end

config :sound_forge, SoundForgeWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Configure Spotify API credentials from environment variables
config :sound_forge, :spotify,
  client_id: System.get_env("SPOTIFY_CLIENT_ID"),
  client_secret: System.get_env("SPOTIFY_CLIENT_SECRET")

# Configure lalal.ai API key for cloud stem separation
config :sound_forge, :lalalai_api_key, System.get_env("LALALAI_API_KEY")
config :sound_forge, :system_lalalai_key, System.get_env("SYSTEM_LALALAI_ACTIVATION_KEY")

# Configure Cloak Vault for at-rest encryption (API keys, tokens, etc.)
# Key resolution: LLM_ENCRYPTION_KEY env var (Base64-encoded 32 bytes),
# otherwise derive 32 bytes from SECRET_KEY_BASE via SHA-256.
vault_key =
  case System.get_env("LLM_ENCRYPTION_KEY") do
    key when is_binary(key) and byte_size(key) > 0 ->
      Base.decode64!(key)

    _ ->
      # Fall back to SECRET_KEY_BASE (env var or hardcoded dev/test value)
      secret =
        System.get_env("SECRET_KEY_BASE") ||
          case config_env() do
            :dev -> "QqSvLpq9KwsEZOGkhwja/3h8iuY5st7SPoZHQAeYyHAPO9Zm/xoofeEa32T9MBKB"
            :test -> "LHyTDWwDtX849e0NHhwpWFZi9n1ApqAzO6/Adf7ILFp+373yCm9LJuGYARSTxjbT"
            :prod -> raise "SECRET_KEY_BASE or LLM_ENCRYPTION_KEY must be set in production"
          end

      :crypto.hash(:sha256, secret)
  end

config :sound_forge, SoundForge.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: vault_key,
      iv_length: 12
    }
  ]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :sound_forge, SoundForge.Repo,
    url: database_url,
    ssl: System.get_env("DATABASE_SSL", "false") in ~w(true 1),
    ssl_opts: [verify: :verify_none],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :sound_forge, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :sound_forge, SoundForgeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :sound_forge, SoundForgeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :sound_forge, SoundForgeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :sound_forge, SoundForge.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
