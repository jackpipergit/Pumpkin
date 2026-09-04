# syntax=docker/dockerfile:1

# Pumpkin server image, built from source against glibc.
#
# The upstream Alpine/musl image is unusable on our hosts: chunk-generation
# threads peg every core and "Loading terrain" never completes. Building on a
# Debian rust image produces a glibc binary, which behaves.
#
# Builder and runtime are pinned to the same Debian release (trixie) so the
# binary links against exactly the glibc it will run on.
#
# Build context is the repository root:
#   DOCKER_BUILDKIT=1 docker build -f fork/Dockerfile -t pumpkin .
#
# The checkout must have its submodules initialised (see the guard below).

FROM rust:1-trixie AS builder

# git is a build-time dependency: crates/pumpkin/build.rs shells out to it to
# embed the commit hash in the server version string.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /pumpkin
COPY . .

# The WIT definitions live in the pumpkin-plugin-wit submodule and are read at
# macro-expansion time by wasmtime's bindgen!. Without them the build dies deep
# into compiling the workspace, so fail immediately with an actionable message.
RUN test -d crates/pumpkin-plugin-wit/v0.1 \
    || { echo "crates/pumpkin-plugin-wit is empty - run 'git submodule update --init --recursive' before building" >&2; exit 1; }

# Keeps the build caches from colliding when the same builder produces images
# for more than one architecture.
ARG TARGETARCH

# The release profile (lto, codegen-units = 1) is left exactly as the workspace
# defines it: this is the deployable artifact, not a development loop.
#
# target/ and the cargo caches are cache mounts, so they do not survive the RUN.
# The binary has to be copied to a real path inside the same command.
RUN --mount=type=cache,id=pumpkin-target-${TARGETARCH},sharing=private,target=/pumpkin/target \
    --mount=type=cache,id=cargo-registry-${TARGETARCH},target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=/usr/local/cargo/git/db \
    cargo build --release -p pumpkin \
    && install -Dm755 target/release/pumpkin /out/pumpkin


FROM debian:trixie-slim AS runtime

# ca-certificates: online mode verifies sessions against Mojang over HTTPS.
# uid 2613 matches the upstream image, so world data on an existing volume
# stays readable when swapping this image in.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgcc-s1 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 2613 pumpkin \
    && useradd --system --uid 2613 --gid 2613 --home-dir /pumpkin --shell /usr/sbin/nologin pumpkin \
    && install -d -o pumpkin -g pumpkin /pumpkin

COPY --from=builder /out/pumpkin /usr/local/bin/pumpkin

# The server writes pumpkin.toml, world data and plugins/ into its working
# directory, which is where the data volume is mounted. It is created owned by
# the runtime user above so a fresh named volume inherits usable permissions.
WORKDIR /pumpkin

USER 2613:2613

ENV RUST_BACKTRACE=1

# 25565/tcp Java edition, 25565/udp query, 19132/udp Bedrock.
EXPOSE 25565 25565/udp 19132/udp

# debian-slim ships no nc, so probe the listener with bash's /dev/tcp. The long
# start period covers spawn-chunk generation on first boot.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=3 \
    CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/25565"]

ENTRYPOINT ["/usr/local/bin/pumpkin"]
