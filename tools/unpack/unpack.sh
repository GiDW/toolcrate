#!/usr/bin/env bash
# unpack: extract archives, picking the extractor from the file's content (not its name)
# and falling back to the next one when it fails. Split archives are extracted once,
# from their first volume.
set -uo pipefail
shopt -s nullglob dotglob

usage() {
  cat <<'EOF'
usage: unpack [options] <archive>...

Extracts zip, 7z, rar and tar (.tar, .tar.gz/.tgz, .tar.xz/.txz, .tar.bz2, .tar.zst)
archives, and anything else unar or 7-Zip can read. The format is detected from the
file's content. Split archives (x.part1.rar, x.r00, x.7z.001, x.zip.001, x.z01) are
extracted once; pass any volume, or all of them.

Each archive is extracted into the output directory: as is when it holds a single file
or directory, otherwise into a new directory named after the archive. Existing files
are never overwritten: a numbered name (x-1) is used instead.

options:
  -o, --output <dir>      output directory (default: the current directory)
  -p, --password <pw>     password for encrypted archives; '-' reads it from stdin
                          (a prompt on a terminal)
      --keep-symlinks     keep symbolic links from the archive (default: remove them)
  -V, --version           print the versions of the bundled extractors
  -h, --help              show this help
EOF
}

# The bin/unpack wrapper mounts host directories below this prefix; hide it in messages.
prefix="${UNPACK_HOST_PREFIX:-}"
show() {
  local p="$1"
  if [[ -n "$prefix" && "$p" == "$prefix"/* ]]; then p="${p#"$prefix"}"; fi
  printf '%s' "$p"
}
say() { echo "unpack: $*" >&2; }
die() { say "$*"; exit 2; }

versions() {
  7z | sed -n '/7-Zip/{p;q}'
  unrar | sed -n '/UNRAR/{p;q}'
  echo "unar $(unar --version)"
  tar --version | head -n1
}

out=.
password=
have_password=0
keep_symlinks=0
archives=()
while (($#)); do
  case "$1" in
    -o|--output) (($# >= 2)) || die "$1 needs a directory"; out="$2"; shift 2 ;;
    --output=*) out="${1#*=}"; shift ;;
    -p|--password) (($# >= 2)) || die "$1 needs a password"; password="$2"; have_password=1; shift 2 ;;
    --password=*) password="${1#*=}"; have_password=1; shift ;;
    --keep-symlinks) keep_symlinks=1; shift ;;
    -V|--version) versions; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; archives+=("$@"); break ;;
    -?*) die "unknown option $1 (see unpack --help)" ;;
    *) archives+=("$1"); shift ;;
  esac
done
((${#archives[@]})) || { usage >&2; exit 2; }

if ((have_password)) && [[ "$password" == - ]]; then
  if [[ -t 0 ]]; then
    read -rsp 'Password: ' password; echo >&2
  else
    IFS= read -r password || true
  fi
fi

mkdir -p -- "$out" || die "cannot create output directory $(show "$out")"
[[ -w "$out" ]] || die "output directory $(show "$out") is not writable"

# Format from the magic bytes: rar, 7z, zip, tar (also compressed with gzip, xz, bzip2
# or zstd), compressed, exe (possibly self-extracting) or unknown.
format() {
  local hex
  hex="$(od -An -tx1 -N8 -- "$1" 2>/dev/null | tr -d ' \n')"
  case "$hex" in
    526172211a0701*|526172211a0700*|52457e5e*) echo rar ;;
    377abcaf271c*) echo 7z ;;
    504b0304*|504b0506*|504b0708*) echo zip ;;
    1f8b*) is_tar gzip "$1" ;;
    fd377a585a00*) is_tar xz "$1" ;;
    425a68*) is_tar bzip2 "$1" ;;
    28b52ffd*) is_tar zstd "$1" ;;
    4d5a*) echo exe ;;
    *) is_tar cat "$1" ;;
  esac
}

# tar if the (decompressed) file has the ustar magic, else compressed (a single
# compressed file) or unknown. GNU tar "succeeds" on a compressed non-tar file.
is_tar() {
  local decompress=(cat)
  [[ "$1" == cat ]] || decompress=("$1" -dc)
  if [[ "$("${decompress[@]}" -- "$2" 2>/dev/null | head -c 262 | tail -c 5 | tr -d '\0')" == ustar ]]; then
    echo tar
  elif [[ "$1" == cat ]]; then
    echo unknown
  else
    echo compressed
  fi
}

# The first volume of a split archive, or the file itself.
first_volume() {
  local f="$1" dir base c n
  dir="$(dirname -- "$f")"
  base="$(basename -- "$f")"
  local -a candidates=()
  shopt -s nocasematch
  if [[ "$base" =~ ^(.+\.part)([0-9]+)(\.rar)$ ]]; then
    n="${BASH_REMATCH[2]}"
    candidates=("$dir/${BASH_REMATCH[1]}$(printf '%0*d' "${#n}" 1)${BASH_REMATCH[3]}")
  elif [[ "$base" =~ ^(.+)\.r[0-9]{2,3}$ ]]; then
    candidates=("$dir/${BASH_REMATCH[1]}.rar" "$dir/${BASH_REMATCH[1]}.RAR")
  elif [[ "$base" =~ ^(.+)\.z[0-9]{2,}$ ]]; then
    candidates=("$dir/${BASH_REMATCH[1]}.zip" "$dir/${BASH_REMATCH[1]}.ZIP")
  elif [[ "$base" =~ ^(.+\.)([0-9]{3,})$ ]]; then
    n="${BASH_REMATCH[2]}"
    candidates=("$dir/${BASH_REMATCH[1]}$(printf '%0*d' "${#n}" 1)")
  fi
  shopt -u nocasematch
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then printf '%s' "$c"; return; fi
  done
  printf '%s' "$f"
}

# The archive's name without archive extensions and volume numbers.
archive_name() {
  local b
  b="$(basename -- "$1")"
  shopt -s nocasematch
  if [[ "$b" =~ ^(.+)\.part[0-9]+\.rar$ ]]; then
    b="${BASH_REMATCH[1]}"
  elif [[ "$b" =~ ^(.+)\.tar\.[a-z0-9]+(\.[0-9]{3,})?$ ]]; then
    b="${BASH_REMATCH[1]}"
  elif [[ "$b" =~ ^(.+)\.(tgz|txz|tbz2?|tzst|tar|rar|zip|7z|gz|xz|bz2|zst|exe)(\.[0-9]{3,})?$ ]]; then
    b="${BASH_REMATCH[1]}"
  elif [[ "$b" =~ ^(.+)\.[0-9]{3,}$ ]]; then
    b="${BASH_REMATCH[1]}"
  fi
  shopt -u nocasematch
  printf '%s' "$b"
}

# A path that doesn't exist yet: $1, or $1 with -1, -2, ... before a file's extension.
unique() {
  local p="$1" is_file="$2" stem ext i=1
  if [[ ! -e "$p" && ! -L "$p" ]]; then printf '%s' "$p"; return; fi
  stem="$p" ext=
  if ((is_file)) && [[ "$(basename -- "$p")" == ?*.* ]]; then
    stem="${p%.*}" ext=".${p##*.}"
  fi
  while [[ -e "$stem-$i$ext" || -L "$stem-$i$ext" ]]; do ((i++)); done
  printf '%s' "$stem-$i$ext"
}

# Extractors: <archive> <empty destination directory>. stdin is /dev/null, so none of
# them waits for a password prompt.
x_unrar() {
  local pw=-p-
  ((have_password)) && pw="-p$password"
  unrar x -idq -o- -y "$pw" -- "$1" "$2/" </dev/null
}
x_7z() {
  local -a pw=()
  ((have_password)) && pw=("-p$password")
  7z x -y -bso0 -bsp0 "${pw[@]}" "-o$2" -- "$1" </dev/null
}
x_unar() {
  local -a pw=()
  ((have_password)) && pw=(-p "$password")
  unar -q -D -k skip "${pw[@]}" -o "$2" -- "$1" </dev/null >/dev/null
}
x_tar() {
  tar -xf "$1" -C "$2" --no-same-owner </dev/null
}

tmp=
cleanup() {
  if [[ -n "$tmp" && -e "$tmp" ]]; then chmod -R u+rwx -- "$tmp" 2>/dev/null; rm -rf -- "$tmp"; fi
  tmp=
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Move the extracted files from $tmp into the output directory.
place() {
  local name="$1" target n
  local -a entries
  if ((!keep_symlinks)); then
    n="$(find "$tmp" -type l -print -delete | wc -l)"
    ((n)) && say "removed $n symbolic link(s); use --keep-symlinks to keep them"
  fi
  entries=("$tmp"/*)
  case "${#entries[@]}" in
    0) say "$(show "$archive") is empty"; cleanup; return ;;
    1)
      local is_file=0
      [[ -d "${entries[0]}" && ! -L "${entries[0]}" ]] || is_file=1
      target="$(unique "$out/$(basename -- "${entries[0]}")" "$is_file")"
      mv -- "${entries[0]}" "$target" && cleanup ;;
    *)
      target="$(unique "$out/$name" 0)"
      # mktemp created the directory as 0700: give it the default mode.
      chmod "$(umask -S)" -- "$tmp" && mv -- "$tmp" "$target" && tmp= ;;
  esac
  say "$(show "$archive") -> $(show "$target")"
}

failed=0
declare -A done_volumes=()
for arg in "${archives[@]}"; do
  if [[ ! -f "$arg" ]]; then say "$(show "$arg"): no such file"; failed=1; continue; fi
  archive="$(first_volume "$arg")"
  [[ -z "${done_volumes[$archive]:-}" ]] || continue
  done_volumes[$archive]=1

  shopt -s nocasematch
  if [[ "$archive" =~ \.[0-9]{3,}$ ]]; then
    tools=(7z unar)  # 7-Zip joins x.001, x.002, ... and opens what's inside
  else
    case "$(format "$archive")" in
      rar) tools=(unrar unar) ;;
      7z|zip|exe) tools=(7z unar) ;;
      tar) tools=(tar 7z unar) ;;
      compressed) tools=(7z unar) ;;
      *) tools=(unar 7z) ;;
    esac
  fi
  shopt -u nocasematch

  ok=0
  for tool in "${tools[@]}"; do
    tmp="$(mktemp -d "$out/.unpack.XXXXXX")" || die "cannot write to $(show "$out")"
    if "x_$tool" "$archive" "$tmp"; then ok=1; break; fi
    cleanup
    say "$tool could not extract $(show "$archive")"
  done
  if ((ok)); then
    place "$(archive_name "$archive")"
  else
    ((have_password)) || say "if $(show "$archive") is encrypted, pass -p <password>"
    failed=1
  fi
done
exit "$failed"
