# unpack

One command to extract zip, 7z, rar and tar archives, including split archives, for
podman. It reads the archive's content to pick the extractor, and when that one fails it
tries the next. Nothing to install on the host.

Image: `ghcr.io/gidw/toolcrate/unpack` (`linux/amd64`, `linux/arm64`)

## What's inside

- **unpack**: a small bash script ([`unpack.sh`](unpack.sh)) that detects the format and
  runs the right extractor
- **7-Zip** (`7z`) from Debian trixie: 7z, zip, split archives (`.001`), and many more
  formats. Debian's build has no RAR support; that's what the next two are for.
- **unrar** from RARLAB (Debian non-free): the reference RAR extractor, for all RAR
  versions, solid and encrypted archives, and multi-volume sets
- **unar**, the command-line version of [The Unarchiver](https://theunarchiver.com/)
  (XADMaster): a second opinion for RAR and zip (old RAR versions, odd filename
  encodings), and a lot of legacy formats
- **GNU tar** with gzip, xz, bzip2 and zstd

It runs as user `app` (uid/gid 1000) in `/work`, with `HOME=/home/app`. Image tags follow
the 7-Zip version.

### How the extractor is picked

The format comes from the file's first bytes, so a zip named `.rar` works too. The first
tool that succeeds wins:

| Format | Tried in order |
| --- | --- |
| RAR (1.5 to 5) | `unrar`, `unar` |
| 7z, zip, self-extracting `.exe` | `7z`, `unar` |
| tar, also compressed (`.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`, `.tar.zst`, ...) | `tar`, `7z`, `unar` |
| a single compressed file (`.gz`, `.xz`, `.bz2`, `.zst`) | `7z`, `unar` |
| split archive (`.001`, `.002`, ...) | `7z`, `unar` |
| anything else | `unar`, `7z` |

### Split archives

Pass any volume, or all of them (`unpack *.rar`): each set is extracted once, from its
first volume. All volumes must be in the same directory.

| Naming | First volume |
| --- | --- |
| `x.part1.rar`, `x.part2.rar`, ... (also `part01`, `part001`) | `x.part1.rar` |
| `x.rar`, `x.r00`, `x.r01`, ... | `x.rar` |
| `x.zip`, `x.z01`, `x.z02`, ... | `x.zip` |
| `x.7z.001`, `x.zip.001`, `x.tar.001`, ... | `x.<ext>.001` |

### Where the files go

Each archive is extracted into the output directory (`-o`, default: the current
directory):

- an archive with a single top-level file or directory: that file or directory as is
- otherwise: a new directory named after the archive (`photos.zip` -> `photos/`)
- existing files are never overwritten: a numbered name is used instead (`photos-1/`,
  `report-1.pdf`)
- symbolic links from the archive are removed, unless you pass `--keep-symlinks`

## Usage

```
unpack [options] <archive>...

  -o, --output <dir>      output directory (default: the current directory)
  -p, --password <pw>     password for encrypted archives; '-' reads it from stdin
                          (a prompt on a terminal)
      --keep-symlinks     keep symbolic links from the archive (default: remove them)
  -V, --version           print the versions of the bundled extractors
  -h, --help              show this help
```

It exits non-zero if any archive failed.

### Executable wrapper (recommended)

Add the [`bin`](bin) directory to your `PATH`. It holds `unpack`, a POSIX `sh` script
that runs the image with podman. Nothing to install or copy.

```sh
export PATH="$PWD/tools/unpack/bin:$PATH"
```

Archives can be anywhere on the host. The wrapper mounts only what it needs:

- the directory of each archive, **read-only** (so the other volumes of a split archive
  are there too)
- the output directory, read-write; it creates it if needed

Host paths appear under `/host` inside the container. The container also gets no
network, no capabilities and a read-only root filesystem, so a malicious archive or a bug
in an extractor can at worst write to the output directory. The image is
`ghcr.io/gidw/toolcrate/unpack:latest`; set `UNPACK_IMAGE` to use another one (for
example a local build).

### Plain podman

Without the wrapper, mount the current directory and use paths below it:

```sh
podman pull ghcr.io/gidw/toolcrate/unpack:latest

podman run --rm -it --userns=keep-id:uid=1000,gid=1000 --network none -v "$PWD:/work" \
  ghcr.io/gidw/toolcrate/unpack:latest archive.rar
```

- `--userns=keep-id:uid=1000,gid=1000` maps your host user to the container's `app`
  user, so extracted files belong to you.
- `-v "$PWD:/work"` makes the current directory available, read-write. Other host paths
  don't exist in the container.

### Shell function

Paste into `~/.zshrc` or `~/.bashrc` for the same, as `unpack`:

```sh
unpack() {
  podman run --rm -it --userns=keep-id:uid=1000,gid=1000 --network none -v "$PWD:/work" \
    ghcr.io/gidw/toolcrate/unpack:latest "$@"
}
```

This mounts the whole current directory read-write and only sees archives below it. The
wrapper above does neither.

### Examples

```sh
# Any format: the content decides, not the name
unpack photos.zip backup.7z movie.rar src.tar.zst

# A split RAR: any volume, or all of them
unpack ~/Downloads/movie.part3.rar
unpack ~/Downloads/movie.part*.rar

# Into another directory
unpack -o ~/extracted ~/Downloads/*.zip

# Encrypted: prompt for the password, or pipe it in
unpack -p - secret.rar
pass show archives/secret | unpack -p - secret.rar
```

`-p <password>` works too, but leaves the password in your shell history.

### macOS

On macOS, podman runs containers in a Linux VM (`podman machine`). Bind mounts only work
for directories the VM shares with the host; your home directory is shared by default.
For archives on other paths, such as `/Volumes/USB`, add them to the machine's volumes.

### SELinux hosts

On Linux hosts with SELinux enforcing (Fedora, RHEL), add `--security-opt label=disable`
so the container can access the mounted directories. Don't relabel your home directory
with `:Z`.

## Licenses

7-Zip is LGPL-2.1-or-later and unar is LGPL-2.1. unrar is freeware with source available
under the unRAR license: free to use and redistribute, but it may not be used to create
RAR archives.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | most recent build |
| `<version>`, e.g. `25.01` | latest build with that 7-Zip version |
| `<version>-<yyyymmdd>` | a specific build of that version (immutable in practice) |
| `sha-<short>` | the build from that repo commit |

7-Zip, unrar and unar are the versions Debian trixie ships, pinned in the containerfile
and bumped by Renovate. Every Monday the image is rebuilt from scratch to pick up Debian
security updates, so a `<version>` tag can move to a newer Debian patch of the same
release.
