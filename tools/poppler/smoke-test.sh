#!/usr/bin/env bash
# Offline smoke test for the poppler image. Usage: smoke-test.sh <image-ref>
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"
engine="${CONTAINER_ENGINE:-podman}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() { "$engine" run --rm --network none "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

expected="$(sed -n 's/^ARG VERSION=//p' "$here/poppler.containerfile")"
[[ -n "$expected" ]] || fail "no ARG VERSION in poppler.containerfile"

# Every poppler binary prints its version (to stderr) with -v. pdfattach and pdfdetach
# exit 99 afterwards, so check the output, not the exit code.
tools="pdfattach pdfdetach pdffonts pdfimages pdfinfo pdfseparate pdfsig pdftocairo pdftohtml pdftoppm pdftops pdftotext pdfunite"
for tool in $tools; do
  out="$(run "$image" "$tool" -v 2>&1 || true)"
  grep -q "version $expected" <<<"$out" || fail "$tool is '$(head -n1 <<<"$out")', expected version $expected"
done
ok "all poppler tools report $expected"

# Running without arguments must explain itself, not succeed silently.
if run "$image" >/dev/null 2>&1; then fail "no arguments should exit non-zero"; fi
ok "no-argument usage error"

# A minimal one-page PDF (Helvetica text), built in the container; poppler rebuilds the
# missing xref table by itself.
mkpdf='printf "%s\n" \
  "%PDF-1.4" \
  "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj" \
  "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj" \
  "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj" \
  "4 0 obj<</Length 44>>stream" \
  "BT /F1 24 Tf 10 40 Td (Hello toolcrate) Tj ET" \
  "endstream endobj" \
  "5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj" \
  "trailer<</Root 1 0 R/Size 6>>" \
  "%%EOF" > /tmp/t.pdf'

text="$(run "$image" sh -c "$mkpdf; pdftotext /tmp/t.pdf -")"
grep -q 'Hello toolcrate' <<<"$text" || fail "pdftotext output is '$text'"
ok "pdftotext"

info="$(run "$image" sh -c "$mkpdf; pdfinfo /tmp/t.pdf")"
grep -q '^Pages: *1$' <<<"$info" || fail "pdfinfo: $info"
ok "pdfinfo"

# Rendering needs a font: if fontconfig finds none, nothing is drawn and the image stays white.
# Count the non-white pixel bytes (0xff) after the PGM header.
ink="$(run "$image" sh -c "$mkpdf; pdftoppm -gray -r 72 /tmp/t.pdf /tmp/o && tr -d '\377' < /tmp/o-1.pgm | wc -c")"
(( ink > 100 )) || fail "pdftoppm rendered no text (fonts missing?)"
ok "pdftoppm renders text"

run "$image" sh -c "$mkpdf; pdftocairo -png -r 72 /tmp/t.pdf /tmp/out && test -s /tmp/out-1.png" \
  || fail "pdftocairo"
ok "pdftocairo"

fonts="$(run "$image" fc-list)"
grep -qi 'DejaVu' <<<"$fonts" || fail "DejaVu fonts not installed"
grep -qi 'Liberation' <<<"$fonts" || fail "Liberation fonts not installed"
ok "fonts installed"

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

uid="$(run "$image" id -u)"
gid="$(run "$image" id -g)"
[[ "$uid:$gid" == "1000:1000" ]] || fail "runs as $uid:$gid, expected 1000:1000"
ok "runs as uid/gid 1000"

echo "smoke test passed: $image"
