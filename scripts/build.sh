#!/usr/bin/env bash
#
# Release build wrapper.
#
# Usage: scripts/build.sh
#   NATIVE=1  build for the host CPU

set -euo pipefail

BINARY="target/release/pumpkin"

cd "$(git rev-parse --show-toplevel)"

# Local builds only: the CI build host is not the deploy host, so a binary built
# with target-cpu=native there may fault on the server.
if [ "${NATIVE:-}" = "1" ]; then
    export RUSTFLAGS="-C target-cpu=native"
    printf '==> RUSTFLAGS=%s\n' "$RUSTFLAGS"
fi

cargo build --release

printf '==> %s/%s\n' "$PWD" "$BINARY"
