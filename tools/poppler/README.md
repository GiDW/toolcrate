# poppler

The [poppler](https://poppler.freedesktop.org/) PDF command-line utilities (`pdftotext`,
`pdftoppm`, `pdfinfo`, ...) with all their libraries and fonts, for podman. Nothing to
install on the host.

Image: `ghcr.io/gidw/toolcrate/poppler` (`linux/amd64`, `linux/arm64`)

## What's inside

- **poppler-utils** from Debian trixie, with all 13 tools: `pdfattach`, `pdfdetach`,
  `pdffonts`, `pdfimages`, `pdfinfo`, `pdfseparate`, `pdfsig`, `pdftocairo`, `pdftohtml`,
  `pdftoppm`, `pdftops`, `pdftotext`, `pdfunite`
- **poppler-data**: encoding maps for CJK and Cyrillic text
- **fontconfig** with **DejaVu** and **Liberation** fonts (metric-compatible with Arial,
  Times New Roman and Courier New), used when a PDF doesn't embed its fonts. CJK fonts
  are not included.

Poppler is a set of tools, so the image has no single tool as entrypoint: the first
argument names the tool to run.

It runs as user `app` (uid/gid 1000) in `/work`, with `HOME=/home/app`.

## Usage

```sh
podman pull ghcr.io/gidw/toolcrate/poppler:latest

podman run --rm -i --userns=keep-id:uid=1000,gid=1000 -v "$PWD:/work" \
  ghcr.io/gidw/toolcrate/poppler:latest pdftotext in.pdf out.txt
```

- `--userns=keep-id:uid=1000,gid=1000` maps your host user to the container's `app`
  user, so output files belong to you.
- `-v "$PWD:/work"` makes the current directory available: use relative paths, or paths
  below it. Other host paths don't exist in the container.
- `-i` lets you pipe a PDF in (`cat in.pdf | ... pdftotext - -`). Without arguments the
  image prints the list of tools.

### Shell function

Paste into `~/.zshrc` or `~/.bashrc`. The first argument is the tool:

```sh
poppler() {
  podman run --rm -i --userns=keep-id:uid=1000,gid=1000 -v "$PWD:/work" \
    ghcr.io/gidw/toolcrate/poppler:latest "$@"
}
```

### Executable wrapper

Alternatively, use the wrapper: `poppler` (a POSIX `sh` script) and a symlink for each
tool (`pdftotext`, `pdftoppm`, ...) that points to it, so the tools work by their own
name, also from scripts. The wrapper ships in the image: copy it with its symlinks to a
directory on your `PATH`, here `~/.local/bin`:

```sh
mkdir -p ~/.local/bin
podman run --rm --entrypoint sh ghcr.io/gidw/toolcrate/poppler:latest \
  -c 'cd /usr/local/share/toolcrate/bin && tar -cf - *' | tar -xf - -C ~/.local/bin
```

Run that again after a `podman pull` to update the wrapper too. Or, in a clone of this
repo, add the [`bin`](bin) directory to your `PATH` instead:

```sh
export PATH="$PWD/tools/poppler/bin:$PATH"

pdftotext in.pdf -          # via the symlink
poppler pdftotext in.pdf -  # the same, via the dispatcher
```

The wrapper doesn't allocate a TTY: poppler never prompts, and a TTY would corrupt binary
output.

### Examples

With the `poppler` function above (or the symlinks, without the `poppler` prefix):

```sh
# Text of a PDF, keeping the layout
poppler pdftotext -layout in.pdf out.txt

# Page 1 as a 150 dpi PNG (writes page-1.png)
poppler pdftoppm -png -r 150 -f 1 -l 1 in.pdf page

# Metadata, and the fonts used
poppler pdfinfo in.pdf
poppler pdffonts in.pdf

# Pull out all embedded images as PNG
poppler pdfimages -png in.pdf img

# Merge, and split into one file per page
poppler pdfunite a.pdf b.pdf merged.pdf
poppler pdfseparate in.pdf page-%d.pdf

# HTML or SVG
poppler pdftohtml -c in.pdf out
poppler pdftocairo -svg -f 1 -l 1 in.pdf page.svg
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
| `<version>`, e.g. `25.03.0` | latest build of that poppler version |
| `<version>-<yyyymmdd>` | a specific build of that version (immutable in practice) |
| `sha-<short>` | the build from that repo commit |

The poppler version is the one Debian trixie ships, pinned in the containerfile and bumped
by Renovate. Every Monday the image is rebuilt from scratch to pick up Debian security
updates, so a `<version>` tag can move to a newer Debian patch of the same release.
