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
| `/home/app/.config/yt-dlp` | yt-dlp config directory (`config`, `cookies.txt`) |
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
If `~/.config/yt-dlp` exists, it is mounted read-write, also at its own host path.

```sh
yt-dlp() {
  local cfg=() d="$HOME/.config/yt-dlp"
  if [[ -d "$d" ]]; then
    cfg=(-v "$d:/home/app/.config/yt-dlp" -v "$d:$d")
  fi
  podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
    -v "$PWD:/work" -v yt-dlp-cache:/home/app/.cache "${cfg[@]}" \
    ghcr.io/gidw/toolcrate/yt-dlp:latest "$@"
}
```

### Executable wrapper

Alternatively, use the `yt-dlp` wrapper, a POSIX `sh` script that does the same as the
shell function. It also works from scripts and cron because it only allocates a TTY when
there is one. The wrapper ships in the image: copy it to a directory on your `PATH`, here
`~/.local/bin`:

```sh
mkdir -p ~/.local/bin
podman run --rm --entrypoint sh ghcr.io/gidw/toolcrate/yt-dlp:latest \
  -c 'cd /usr/local/share/toolcrate/bin && tar -cf - *' | tar -xf - -C ~/.local/bin
```

Run that again after a `podman pull` to update the wrapper too. Or, in a clone of this
repo, add the [`bin`](bin) directory to your `PATH` instead:

```sh
export PATH="$PWD/tools/yt-dlp/bin:$PATH"
```

### Config file and cookies

The wrapper and the shell function mount `~/.config/yt-dlp` read-write (yt-dlp writes
refreshed cookies back) at `/home/app/.config/yt-dlp`, and again at its own host path.
Absolute paths into that directory therefore work unchanged, for example in your config:

```
--cookies /Users/me/.config/yt-dlp/cookies.txt
```

Absolute host paths outside that directory don't exist in the container. Write downloads
to `/work` (the current directory) and use the bundled ffmpeg.

Without the wrapper, mount the directory yourself:

```sh
d="$HOME/.config/yt-dlp"
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
  -v "$PWD:/work" -v yt-dlp-cache:/home/app/.cache \
  -v "$d:/home/app/.config/yt-dlp" -v "$d:$d" \
  ghcr.io/gidw/toolcrate/yt-dlp:latest <args>
```

`--cookies-from-browser` doesn't work: the container can't see your host browser's
profile. Export a `cookies.txt` instead (Netscape format), for example with the "Get
cookies.txt LOCALLY" extension, save it as `~/.config/yt-dlp/cookies.txt` and pass it
with `--cookies`. Cookies are credentials: keep the file private and re-export it when
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
