# Stage 1: Build Elixir release
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.2.4
ARG DEBIAN_VERSION=bookworm-20250224-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js for asset compilation
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy source and compile (needed before assets.deploy for colocated hooks)
COPY assets/package.json assets/package-lock.json ./assets/
RUN cd assets && npm ci
COPY priv priv
COPY assets assets
COPY lib lib
RUN mix compile

# Build assets (after compile so phoenix-colocated resolves from build path)
RUN mix assets.setup
RUN mix assets.deploy

# Build release
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# Stage 2: Runtime image
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y \
    libstdc++6 openssl libncurses6 locales ca-certificates \
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
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/sound_forge ./
# Copy Python scripts
COPY --chown=nobody:root priv/python priv/python

# Create uploads directory
RUN mkdir -p priv/uploads && chown nobody priv/uploads

USER nobody

ENV PHX_SERVER=true

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT:-4000}/health || exit 1

CMD ["/app/bin/server"]
