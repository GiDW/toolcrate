#!/usr/bin/env bash
# Offline smoke test for the yt-dlp image. Usage: smoke-test.sh <image-ref>
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"
engine="${CONTAINER_ENGINE:-podman}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() { "$engine" run --rm --network none "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

# yt-dlp prints zero-padded calver (2026.08.19), PyPI normalizes it (2026.8.19).
normalize() { sed -E 's/(^|\.)0+([0-9])/\1\2/g' <<<"$1"; }

expected="$(sed -n 's/^ARG VERSION=//p' "$here/yt-dlp.containerfile")"
[[ -n "$expected" ]] || fail "no ARG VERSION in yt-dlp.containerfile"
actual="$(run "$image" --version)"
[[ "$(normalize "$actual")" == "$(normalize "$expected")" ]] \
  || fail "yt-dlp --version is '$actual', expected '$expected'"
ok "yt-dlp $actual"

run --entrypoint ffmpeg "$image" -hide_banner -version >/dev/null || fail "ffmpeg -version"
run --entrypoint ffprobe "$image" -hide_banner -version >/dev/null || fail "ffprobe -version"
ok "ffmpeg and ffprobe"

run --entrypoint deno "$image" --version >/dev/null || fail "deno --version"
ok "deno"

run --entrypoint python "$image" -c \
  'import yt_dlp_ejs, curl_cffi, brotli, certifi, mutagen, Cryptodome, websockets' \
  || fail "python imports"
ok "python dependencies import"

targets="$(run "$image" --list-impersonate-targets)"
grep -q 'curl_cffi' <<<"$targets" || fail "no curl_cffi impersonate targets"
! grep -q 'unavailable' <<<"$targets" || fail "curl_cffi impersonate targets unavailable"
ok "curl_cffi impersonate targets"

# -v without a URL prints the debug header, then exits non-zero.
debug="$(run "$image" -v 2>&1 || true)"
grep -q 'JS runtimes: deno-' <<<"$debug" || fail "yt-dlp does not detect deno as JS runtime"
ok "yt-dlp detects deno"

uid="$(run --entrypoint id "$image" -u)"
gid="$(run --entrypoint id "$image" -g)"
[[ "$uid:$gid" == "1000:1000" ]] || fail "runs as $uid:$gid, expected 1000:1000"
ok "runs as uid/gid 1000"

echo "smoke test passed: $image"
