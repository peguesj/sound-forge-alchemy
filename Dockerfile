# Stage 1: Build Elixir release
FROM hexpm/elixir:1.18.3-erlang-27.2.4-debian-bookworm-20250224-slim AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js for asset compilation
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Copy everything needed for compilation
COPY mix.exs mix.lock ./
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel

# Fetch deps, install npm, compile, build assets, and release in one layer
RUN mix deps.get --only $MIX_ENV \
    && cd assets && npm ci && cd .. \
    && mix deps.compile \
    && mix compile \
    && mix assets.setup \
    && mix assets.deploy \
    && mix release

# Stage 2: Runtime image
FROM debian:bookworm-20250224-slim

RUN apt-get update -y && apt-get install -y \
    libstdc++6 openssl libncurses6 locales ca-certificates curl \
    python3 python3-pip python3-venv ffmpeg \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Python audio dependencies
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir demucs librosa numpy spotdl

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod"

# Copy release from builder
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/sound_forge ./
# Ensure release scripts are executable
RUN chmod +x /app/bin/server /app/bin/migrate /app/bin/sound_forge
# Copy Python scripts
COPY --chown=nobody:root priv/python priv/python

# Create uploads directory
RUN mkdir -p priv/uploads && chown nobody priv/uploads

USER nobody

ENV PHX_SERVER=true

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT:-4000}/health || exit 1

CMD ["/app/bin/server"]
