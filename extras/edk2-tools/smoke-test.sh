#!/usr/bin/env bash
set -euo pipefail

# Usage: extras/edk2-tools/smoke-test.sh <image-ref>
# Runs offline (--network none).

image="${1:?usage: $0 <image-ref>}"
engine="${CONTAINER_ENGINE:-podman}"
dir="$(cd "$(dirname "$0")" && pwd)"
fail=0

run() { "$engine" run --rm --network none "$@"; }
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   $desc"
  else
    echo "FAIL $desc" >&2
    fail=1
  fi
}

# Some tools exit non-zero when printing their usage, so accept that too.
runs() {
  local out
  out="$(run --entrypoint "$1" "$image" --version 2>&1)" && return 0
  grep -qiE 'version|usage' <<<"$out"
}

version="$(sed -n 's/^ARG VERSION=//p' "$dir/edk2-tools.containerfile")"
[[ -n "$version" ]] || { echo "FAIL no ARG VERSION in containerfile" >&2; exit 1; }

label="$("$engine" image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$image")"
check "version label is ${version}" test "$label" = "$version"

check "default user is uid 1000" test "$(run --entrypoint id "$image" -u)" = 1000

for tool in BrotliCompress DevicePath EfiRom GenCrc32 GenFfs GenFv GenFw GenSec \
            LzmaCompress TianoCompress VfrCompile VolInfo; do
  check "${tool} runs" runs "$tool"
done

# Hand-built 512-byte option ROM (vendor 0x8086, device 0x1234); EfiRom -d must parse it.
rom_test='
  { printf "\125\252"; head -c 22 /dev/zero; printf "\034\000\000\000"
    printf "PCIR\206\200\064\022\000\000\030\000\000\000\000\000\001\000\000\000\000\200\000\000"
    head -c 512 /dev/zero; } | head -c 512 > /tmp/test.rom
  EfiRom -d /tmp/test.rom | grep -q "Vendor ID *0x8086"
'
check "EfiRom -d parses a ROM" run --entrypoint sh "$image" -c "$rom_test"

exit "$fail"
