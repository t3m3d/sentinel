#!/usr/bin/env bash
# build_linux.sh — build Sentinel (proof of concept) for KryptOS Linux x86_64.
#
# Produces a single static, syscall-only ELF binary at ./sentinel using the
# Linux native backend. No libc, no dynamic linker, no gcc.
#
# Prereqs:
#   - x86_64 Linux (KryptOS, or the `krypton` Lima VM on a macOS host)
#   - a krypton checkout reachable via $KRYPTON_ROOT (default: ../krypton)
#   - a Wayland compositor to run the GUI (weston works: --backend=headless
#     for smoke testing)
#
# Usage:
#   ./build_linux.sh            build only
#   ./build_linux.sh --smoke    build, then run ./sentinel --smoke (no GUI)
#   ./build_linux.sh --run      build, then run ./sentinel (one frame)

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KRYPTON_ROOT="${KRYPTON_ROOT:-$SCRIPT_DIR/../krypton}"
KCC="$KRYPTON_ROOT/bootstrap/kcc_driver_linux_x86_64"

if [[ ! -x "$KCC" ]]; then
    echo "build_linux.sh: cannot find $KCC" >&2
    echo "  Set KRYPTON_ROOT to your krypton checkout, e.g." >&2
    echo "    KRYPTON_ROOT=/path/to/krypton ./build_linux.sh" >&2
    exit 1
fi

SRC="$SCRIPT_DIR/src/sentinel.k"
OUT="$SCRIPT_DIR/sentinel"

echo "build_linux.sh: $SRC -> $OUT"
"$KCC" "$SRC" -o "$OUT"

if [[ ! -x "$OUT" ]]; then
    echo "build_linux.sh: build failed — $OUT not produced" >&2
    exit 1
fi
echo "build_linux.sh: built ${OUT} ($(wc -c <"$OUT") bytes)"

case "${1:-}" in
    --smoke) exec "$OUT" --smoke ;;
    --run)   exec "$OUT" ;;
esac
