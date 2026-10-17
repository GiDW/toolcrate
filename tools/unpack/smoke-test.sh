#!/usr/bin/env bash
# Offline smoke test for the unpack image. Usage: smoke-test.sh <image-ref>
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"
engine="${CONTAINER_ENGINE:-podman}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() { "$engine" run --rm --network none "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

main() {
  expected="$(sed -n 's/^ARG VERSION=//p' "$here/unpack.containerfile")"
  [[ -n "$expected" ]] || fail "no ARG VERSION in unpack.containerfile"

  versions="$(run "$image" --version)"
  grep -q "^7-Zip $expected " <<<"$versions" || fail "7-Zip is '$(head -n1 <<<"$versions")', expected $expected"
  ok "7-Zip $expected"
  grep -q '^UNRAR ' <<<"$versions" || fail "unrar doesn't run: $versions"
  grep -q '^unar v' <<<"$versions" || fail "unar doesn't run: $versions"
  grep -q '^tar (GNU tar)' <<<"$versions" || fail "tar doesn't run: $versions"
  for tool in xz bzip2 zstd; do
    run --entrypoint "$tool" "$image" --version >/dev/null 2>&1 || fail "$tool doesn't run"
  done
  ok "unrar, unar, tar, xz, bzip2 and zstd run"

  if run "$image" >/dev/null 2>&1; then fail "no arguments should exit non-zero"; fi
  ok "no-argument usage error"

  box 'unpack /tmp/a/rar5.part2.rar /tmp/a/rar5.part3.rar
       cmp numbers.txt /tmp/numbers.txt; [ "$(ls -A)" = numbers.txt ]' \
    || fail "RAR5 multi-volume (.partN.rar), from a later volume, extracted once"
  ok "RAR5 multi-volume"

  box 'unpack /tmp/a/rar4.r01; cmp numbers.txt /tmp/numbers.txt' \
    || fail "RAR4 multi-volume (.rar, .r00, .r01)"
  ok "RAR4 multi-volume, old naming"

  box 'if unpack /tmp/a/secret.rar; then exit 1; fi; [ -z "$(ls -A)" ]
       unpack -p secret /tmp/a/secret.rar; grep -qx "hello toolcrate" hello.txt
       echo secret | unpack -p - -o p /tmp/a/secret.rar; grep -qx "hello toolcrate" p/hello.txt' \
    || fail "encrypted RAR5: no password must fail cleanly, -p and -p - must work"
  ok "encrypted RAR5 (-p, -p -)"

  box 'unpack /tmp/a/spanned.z01; seq 1 30000 | cmp - big.txt' || fail "spanned zip (.zip, .z01, .z02)"
  ok "spanned zip"

  box 'unpack /tmp/a/split.7z.003; cmp random /tmp/random' || fail "split 7z (.7z.001, ...)"
  ok "split 7z"

  box 'for f in t.tgz t.tar.xz t.tar.bz2 t.tar.zst t.tar t.7z t.zip zip-named.rar; do
         unpack -o "$f" "/tmp/a/$f" && [ "$(cat "$f/d/one" "$f/d/two")" = "$(printf "one\ntwo")" ] \
           || { echo "failed: $f"; exit 1; }
       done' \
    || fail "tar.gz, tar.xz, tar.bz2, tar.zst, tar, 7z, zip or zip named .rar"
  ok "tar.gz, tar.xz, tar.bz2, tar.zst, tar, 7z, zip, zip named .rar"

  box 'unpack /tmp/a/single.gz; cmp single /tmp/numbers.txt' || fail "single gzip-compressed file"
  ok "single compressed file"

  box 'unpack /tmp/a/multi.tar.gz
       [ -f multi/a ] && [ -f multi/b ] && [ ! -e multi/link ] && [ ! -L multi/link ]
       unpack --keep-symlinks /tmp/a/multi.tar.gz; [ -L multi-1/link ] && [ -f multi-1/a ]
       [ "$(ls -A)" = "$(printf "multi\nmulti-1")" ]' \
    || fail "several top-level entries: directory per archive, numbered names, symlinks removed by default"
  ok "directory per archive, no overwrites, symlinks removed unless --keep-symlinks"

  # The wrappers ship in the image: copy them out the way the README does, and compare.
  wrappers="$(mktemp -d)"
  trap 'rm -rf "$wrappers"' EXIT
  run --entrypoint sh "$image" -c 'cd /usr/local/share/toolcrate/bin && tar -cf - *' \
    | tar -xf - -C "$wrappers" || fail "can't copy the wrappers out of the image"
  [[ "$(ls -A "$wrappers")" == "$(ls -A "$here/bin")" ]] \
    || fail "wrappers in the image are '$(ls -A "$wrappers" | tr '\n' ' ')', expected bin/"
  for f in "$here"/bin/*; do
    w="$wrappers/${f##*/}"
    if [[ -L "$f" ]]; then
      [[ "$(readlink "$w")" == "$(readlink "$f")" ]] || fail "${f##*/} in the image is not a symlink to $(readlink "$f")"
    else
      [[ -x "$w" ]] && cmp -s "$w" "$f" || fail "${f##*/} in the image differs from bin/${f##*/}, or isn't executable"
    fi
  done
  ok "wrappers in the image match bin/"

  uid="$(run --entrypoint id "$image" -u)"
  gid="$(run --entrypoint id "$image" -g)"
  [[ "$uid:$gid" == "1000:1000" ]] || fail "runs as $uid:$gid, expected 1000:1000"
  ok "runs as uid/gid 1000"

  echo "smoke test passed: $image"
}

# Run a bash script in the container, in an empty /tmp/o. /tmp/a holds the fixtures:
# the RAR and spanned-zip files at the end of this file (free tools can't create RAR
# archives), plus archives of the other formats built here with tar and 7z.
box() {
  fixtures | run -i --entrypoint bash "$image" -c '
set -e
mkdir -p /tmp/a /tmp/o && cd /tmp/a
base64 -d | xz -d | tar -x
seq 1 600 > /tmp/numbers.txt
mkdir d && echo one > d/one && echo two > d/two
tar -czf t.tgz d && tar -cJf t.tar.xz d && tar -cjf t.tar.bz2 d && tar --zstd -cf t.tar.zst d && tar -cf t.tar d
7z a -bso0 t.7z d && 7z a -bso0 t.zip d && cp t.zip zip-named.rar
head -c 5000 /dev/urandom > /tmp/random && 7z a -bso0 -v1k split.7z /tmp/random
cp /tmp/numbers.txt single && gzip single
mkdir m && echo a > m/a && echo b > m/b && ln -s /etc/passwd m/link && tar -czf multi.tar.gz -C m a b link
rm -rf d m
cd /tmp/o
'"$1"
}

# tar.xz, base64: rar5.part{1,2,3}.rar and rar4.{rar,r00,r01} (RAR 7.11 and 6.24, seq 1
# 600, stored, 1 KB volumes), secret.rar (RAR5, password and headers encrypted with
# "secret", holds hello.txt) and spanned.{zip,z01,z02} (zip -s 64k, seq 1 30000).
fixtures() {
  cat <<'EOF'
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
oAsAE+12v7HEZ/sCAAAAAARZWg==
EOF
}

main
