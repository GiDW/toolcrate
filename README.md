# toolcrate

Container images that bundle CLI tools with all their dependencies, so you can run them
through **podman** instead of installing them on your machine. Images are multi-arch
(`linux/amd64`, `linux/arm64`) and published to GHCR.

## Tools

| Tool | Image | |
| --- | --- | --- |
| yt-dlp | `ghcr.io/gidw/toolcrate/yt-dlp` | [README](tools/yt-dlp/README.md) |
| poppler (pdftotext, pdftoppm, pdfinfo, ...) | `ghcr.io/gidw/toolcrate/poppler` | [README](tools/poppler/README.md) |
| unpack (zip, 7z, rar, tar.*, split archives) | `ghcr.io/gidw/toolcrate/unpack` | [README](tools/unpack/README.md) |

### Extras

Tools that don't follow the conventions above (they live in `extras/` and have their
own workflow):

| Tool | Image | |
| --- | --- | --- |
| edk2-tools (amd64 only, also published as a binary release) | `ghcr.io/gidw/toolcrate/edk2-tools` | [README](extras/edk2-tools/README.md) |

## Usage

```sh
podman pull ghcr.io/gidw/toolcrate/<tool>:latest
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 -v "$PWD:/work" \
  ghcr.io/gidw/toolcrate/<tool>:latest <args>
```

Each image runs as a non-root user (uid 1000) in `/work`. `--userns=keep-id:uid=1000,gid=1000`
maps that user to you, so files written to the mounted directory belong to you. Each
tool's README has the full command and a shell function to paste into your shell config.
Some tools also ship an executable wrapper (`tools/<name>/bin/<name>`). It's in the image
too, so you can copy it from there to a directory on your `PATH`:

```sh
mkdir -p ~/.local/bin
podman run --rm --entrypoint sh ghcr.io/gidw/toolcrate/<tool>:latest \
  -c 'cd /usr/local/share/toolcrate/bin && tar -cf - *' | tar -xf - -C ~/.local/bin
```

Or add the tool's `bin` directory in a clone of this repo to your `PATH`.

## Tags and updates

- `latest`: most recent build
- `<version>`: latest build of that upstream version
- `<version>-<yyyymmdd>`: a specific build
- `sha-<short>`: the build from that repo commit

Images are rebuilt and pushed whenever a tool changes on `main`. Upstream versions are
pinned and bumped by [Renovate](renovate.json). Every Monday all images are also rebuilt
from scratch, to pick up base image and OS package updates.

## Adding a tool

See [AGENTS.md](AGENTS.md): add `tools/<name>/` with a containerfile, README and smoke
test, and CI picks it up automatically.
