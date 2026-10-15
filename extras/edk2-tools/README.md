# edk2-tools

[TianoCore EDK II](https://github.com/tianocore/edk2) BaseTools, compiled from source:
`EfiRom`, `GenFw`, `GenFv`, `GenFfs`, `GenSec`, `GenCrc32`, `VolInfo`, `DevicePath`,
`BrotliCompress`, `LzmaCompress`, `TianoCompress` and `VfrCompile`. The main use is
parsing option ROMs with `EfiRom -d`, for example to decide whether a device's ROM has to
be accounted for when [setting up your own Secure Boot keys](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Using_your_own_keys).

This tool is an **exception** to the other toolcrate tools: it lives in `extras/`, is
built for `linux/amd64` only, has its own workflow
([`edk2-tools.yml`](../../.github/workflows/edk2-tools.yml)), and also publishes the
compiled binaries as a GitHub release asset.

Image: `ghcr.io/gidw/toolcrate/edk2-tools` (`linux/amd64`)

## What's inside

- The tools above in `/usr/local/bin`, built with `make -C BaseTools/Source/C` from the
  `edk2-stable<version>` tag on Debian trixie. The entrypoint is `EfiRom`; run another
  tool with `--entrypoint`.
- Runs as user `app` (uid/gid 1000) in `/work`.

## Usage

```sh
podman pull ghcr.io/gidw/toolcrate/edk2-tools:latest

podman run --rm -it --userns=keep-id:uid=1000,gid=1000 -v "$PWD:/work" \
  ghcr.io/gidw/toolcrate/edk2-tools:latest <EfiRom args>

# another tool
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 -v "$PWD:/work" \
  --entrypoint GenFw ghcr.io/gidw/toolcrate/edk2-tools:latest <args>
```

### Executable wrapper

Put [`edk2-tools`](edk2-tools) (a POSIX `sh` script) on your `PATH`. It runs `EfiRom`,
or the tool you name as the first argument.

```sh
install -m 755 extras/edk2-tools/edk2-tools ~/.local/bin/edk2-tools
```

### Shell function

```sh
edk2-tools() {
  local tool=EfiRom
  case "${1:-}" in
    BrotliCompress|DevicePath|EfiRom|GenCrc32|GenFfs|GenFv|GenFw|GenSec|LzmaCompress|TianoCompress|VfrCompile|VolInfo)
      tool="$1"; shift ;;
  esac
  podman run --rm -it --userns=keep-id:uid=1000,gid=1000 \
    --entrypoint "$tool" -v "$PWD:/work" \
    ghcr.io/gidw/toolcrate/edk2-tools:latest "$@"
}
```

### Compiled binaries

Each edk2 version is also published as a release,
`edk2-tools-<version>`, with `edk2-tools-<version>-linux-amd64.tar.gz` and
`SHA256SUMS`. The binaries are dynamically linked against glibc only (`BrotliCompress`
also uses libm, `VfrCompile` libstdc++).

```sh
v=202608
curl -fLO "https://github.com/GiDW/toolcrate/releases/download/edk2-tools-$v/edk2-tools-$v-linux-amd64.tar.gz"
curl -fLO "https://github.com/GiDW/toolcrate/releases/download/edk2-tools-$v/SHA256SUMS"
sha256sum -c SHA256SUMS
mkdir -p ~/.local/share/edk2-tools && tar -xzf "edk2-tools-$v-linux-amd64.tar.gz" -C ~/.local/share/edk2-tools
~/.local/share/edk2-tools/EfiRom -d ~/intel_ssd.rom
```

The release asset is created once per edk2 version and not replaced by the weekly image
rebuild.

### Examples

Dump a device's option ROM on the host first (the container can't see `/sys`):

```sh
dev=/sys/bus/pci/devices/0000:01:00.0
echo 1 | sudo tee $dev/rom >/dev/null
sudo cat $dev/rom > ~/intel_ssd.rom
echo 0 | sudo tee $dev/rom >/dev/null
```

Then parse it from the directory containing it:

```sh
edk2-tools -d intel_ssd.rom
```

### macOS and SELinux

The same notes as the other tools apply: on macOS run from a directory under `$HOME`; on
SELinux hosts add `--security-opt label=disable`.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | most recent build |
| `<version>`, e.g. `202608` | latest build of that edk2 release (`edk2-stable<version>`) |
| `<version>-<yyyymmdd>` | a specific build of that release |
| `sha-<short>` | the build from that repo commit |
