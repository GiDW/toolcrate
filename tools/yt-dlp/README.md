# yt-dlp

A full-featured [yt-dlp](https://github.com/yt-dlp/yt-dlp) image for podman. It works
with YouTube out of the box, with nothing installed on the host.

Image: `ghcr.io/gidw/toolcrate/yt-dlp` (`linux/amd64`, `linux/arm64`)

## What's inside

- **yt-dlp** installed from PyPI with the `default` and `curl-cffi` extras:
  - `yt-dlp-ejs`: the JavaScript challenge solver YouTube needs
  - `curl_cffi`: browser impersonation (`--impersonate`)
  - `brotli`, `certifi`, `mutagen`, `pycryptodomex`, `requests`, `urllib3`, `websockets`
- **deno**: the JS runtime yt-dlp uses for YouTube challenge solving
- **ffmpeg** and **ffprobe** from Debian, for merging, remuxing and audio extraction
- Python on Debian slim (`python:*-slim-trixie`), `ca-certificates`

It runs as user `app` (uid/gid 1000) in `/work`, with `HOME=/home/app`:

| Path | Purpose |
| --- | --- |
| `/work` | working directory; mount the directory you download into |
| `/home/app/.config/yt-dlp/config` | yt-dlp config file |
| `/home/app/.cache/yt-dlp` | yt-dlp cache, including the EJS solver cache |

## Usage

```sh
podman pull ghcr.io/gidw/toolcrate/yt-dlp:latest

podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
  -v "$PWD:/work" -v yt-dlp-cache:/home/app/.cache \
  ghcr.io/gidw/toolcrate/yt-dlp:latest <args>
```

- `--userns=keep-id:uid=1000,gid=1000` maps your host user to the container's `app`
  user, so downloaded files belong to you.
- `-v "$PWD:/work"` saves downloads to the current directory.
- `-v yt-dlp-cache:/home/app/.cache` keeps the cache in a named volume, so the EJS
  solver cache survives between runs.

### Shell function

Paste into `~/.zshrc` or `~/.bashrc` to use `yt-dlp` as if it were installed locally.
If `~/.config/yt-dlp/config` exists, it is mounted read-only.

```sh
yt-dlp() {
  local cfg=()
  if [[ -f "$HOME/.config/yt-dlp/config" ]]; then
    cfg=(-v "$HOME/.config/yt-dlp/config:/home/app/.config/yt-dlp/config:ro")
  fi
  podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
    -v "$PWD:/work" -v yt-dlp-cache:/home/app/.cache "${cfg[@]}" \
    ghcr.io/gidw/toolcrate/yt-dlp:latest "$@"
}
```

### Executable wrapper

Alternatively, put [`yt-dlp`](yt-dlp) (a POSIX `sh` script) in a directory on your
`PATH`. It does the same as the shell function, and it also works from scripts and cron
because it only allocates a TTY when there is one.

```sh
install -m 755 tools/yt-dlp/yt-dlp ~/.local/bin/yt-dlp
```

### Config file

Mount your host config read-only at the path yt-dlp reads it from:

```sh
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
  -v "$PWD:/work" -v yt-dlp-cache:/home/app/.cache \
  -v "$HOME/.config/yt-dlp/config:/home/app/.config/yt-dlp/config:ro" \
  ghcr.io/gidw/toolcrate/yt-dlp:latest <args>
```

### Cookies

`--cookies-from-browser` doesn't work: the container can't see your host browser's
profile. Export a `cookies.txt` instead (Netscape format) and pass it with `--cookies`:

1. Export the cookies for the site from your browser with a cookies.txt export
   extension, for example "Get cookies.txt LOCALLY". Save the file somewhere private,
   such as `~/.config/yt-dlp/cookies.txt`.
2. Mount it and point `--cookies` at it. Don't mount it read-only: yt-dlp writes
   updated cookies back to the file.

```sh
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
  -v "$PWD:/work" -v yt-dlp-cache:/home/app/.cache \
  -v "$HOME/.config/yt-dlp/cookies.txt:/home/app/cookies.txt" \
  ghcr.io/gidw/toolcrate/yt-dlp:latest --cookies /home/app/cookies.txt <url>
```

Cookies are credentials: keep the file out of shared directories, and re-export it when
it expires.

### Examples

With the `yt-dlp` function above:

```sh
# Best audio, converted to mp3
yt-dlp -x --audio-format mp3 --audio-quality 0 "<url>"

# Best video + best audio, merged into mp4
yt-dlp -f "bv*+ba/b" --merge-output-format mp4 "<url>"

# A playlist, one numbered file per entry in a folder named after the playlist
yt-dlp -o "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s" "<playlist-url>"

# Browser impersonation via curl_cffi
yt-dlp --impersonate chrome "<url>"
```

### macOS

On macOS, podman runs containers in a Linux VM (`podman machine`). Bind mounts only work
for directories the VM shares with the host; your home directory is shared by default.
Run the command from a directory under `$HOME`, or add other paths to the machine's
volumes.

### SELinux hosts

On Linux hosts with SELinux enforcing (Fedora, RHEL), add `--security-opt label=disable`
so the container can access `$PWD`. Don't relabel your home directory with `:Z`.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | most recent build |
| `<version>`, e.g. `2026.8.19` | latest build of that yt-dlp release |
| `<version>-<yyyymmdd>` | a specific build of that release (immutable in practice) |
| `sha-<short>` | the build from that repo commit |

The image is rebuilt when a new yt-dlp release comes out (Renovate bumps it and
automerges it once checks pass), when any other dependency is bumped, and every Monday
from scratch to pick up Debian and Python base image updates. Run `podman pull` now and
then, or pin a `<version>-<yyyymmdd>` tag for reproducibility.
