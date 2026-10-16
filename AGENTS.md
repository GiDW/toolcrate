# AGENTS.md

toolcrate builds and publishes container images that bundle a CLI tool with all of its
dependencies, so it can be used locally through **podman** instead of being installed on
the host. Images: `ghcr.io/gidw/toolcrate/<tool>`.

## Conventions

- Lowercase file and directory names. Only exceptions: `README.md`, `AGENTS.md`.
- One directory per tool, containing only:
  - `tools/<name>/<name>.containerfile`
  - `tools/<name>/README.md`
  - `tools/<name>/smoke-test.sh`
  - optionally `tools/<name>/bin/<name>`: an executable wrapper. Users add the `bin`
    directory to `$PATH` (no install or copy) as an alternative to the README's shell
    function. POSIX `sh` only
    (`#!/bin/sh`, no bashisms), podman only.
- Podman is the primary consumer: documented commands use `podman`. Images are standard
  OCI and must also work with docker, but don't document docker.
- Every upstream version is pinned as an `ARG` with a Renovate annotation directly
  above it:
  ```dockerfile
  # renovate: datasource=<pypi|github-releases|docker|...> depName=<name>
  ARG SOMETHING_VERSION=1.2.3
  ```
  Optional `versioning=<scheme>` and `extractVersion=<regex>` may follow `depName`, in
  that order (see `DENO_VERSION` in `tools/yt-dlp/yt-dlp.containerfile`).
- Base images go in a plain `FROM image:tag@sha256:digest` line. Renovate's dockerfile
  manager bumps them.
- If a `FROM` line interpolates an ARG (`FROM foo:${FOO_VERSION}`), add the image to the
  dockerfile-manager `enabled: false` rule in `renovate.json`. The ARG annotation bumps it.
- Every containerfile declares `ARG VERSION=<upstream tool version>` at the start of a
  line, before the first `FROM`. CI reads it with `sed -n 's/^ARG VERSION=//p'` to tag
  the image.
- Images run as non-root user `app` (uid/gid 1000), `HOME=/home/app`, `WORKDIR /work`,
  with `ENTRYPOINT` set to the tool. For a suite of tools (e.g. `tools/poppler`) the
  entrypoint is a small `exec "$@"` script: the first argument names the tool, and
  `bin/` holds a dispatcher named after the tool directory plus one symlink per tool.
- Must build for `linux/amd64` and `linux/arm64` (the only exception is `extras/`, below).
- Keep it simple: no vulnerability scanning, SBOM, signing or hadolint. Checks are: the
  image builds, and the smoke test passes.

## Adding a tool

1. Create `tools/<name>/`.
2. Write `tools/<name>/<name>.containerfile`:
   - `ARG VERSION=...` with a `# renovate:` annotation, plus an annotated ARG for
     every other pinned upstream version.
   - Base image pinned by tag and digest. Prefer a multi-stage build that copies only
     what the runtime needs.
   - OCI labels: `org.opencontainers.image.source=https://github.com/GiDW/toolcrate`,
     `.title`, `.description`, `.version` (`${VERSION}`), `.licenses`.
   - User `app` 1000:1000, `WORKDIR /work`, `ENTRYPOINT ["<tool>"]`.
3. Write `tools/<name>/smoke-test.sh` following the contract below, then `chmod +x` it.
4. Write `tools/<name>/README.md`: what's inside, the podman run command, a shell
   function wrapper, examples, and tags. Optionally add an executable wrapper
   `tools/<name>/bin/<name>` (POSIX `sh`, `chmod +x`) and document it in the README.
5. Add the tool to the list in the root `README.md`.
6. Build and smoke-test it locally (see below).
7. Open a PR. CI discovers tools from `tools/*/`, so no workflow changes are needed.

## Extras (exceptions)

`extras/<name>/` holds tools that don't fit the `tools/` conventions. CI doesn't
discover them: `list-tools.sh`, `pr.yml`, `publish.yml` and `build-tool.yml` ignore
`extras/`, and each extra has its own workflow in `.github/workflows/<name>.yml`.
Layout (containerfile, README, smoke test, optional wrapper), the `ARG VERSION` and
Renovate annotation rules, and the smoke-test contract still apply.

- `extras/edk2-tools`: `linux/amd64` only, and publishes the compiled binaries as a
  GitHub release asset (`edk2-tools-<version>`, created once per version) besides the
  image. Its containerfile has a `binaries` stage that the workflow exports.

## Smoke-test contract

`tools/<name>/smoke-test.sh <image-ref>`

- Executable, starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Runs the image with `${CONTAINER_ENGINE:-podman}`; CI sets `CONTAINER_ENGINE=docker`.
- Exits non-zero on any failure, and prints what failed.
- Needs **no network access to third-party sites** (CI runners get blocked, e.g. by
  YouTube). Run containers with `--network none`.
- Checks at least that the tool's version matches the containerfile's `ARG VERSION`,
  that every bundled dependency runs or imports, and that the default user is uid 1000.

## Local build and test

```sh
podman build -t localhost/<name>:dev -f tools/<name>/<name>.containerfile tools/<name>
tools/<name>/smoke-test.sh localhost/<name>:dev
```

For the other arch: `podman build --platform linux/amd64 ...` (slow, emulated).

## CI and publishing

- `.github/workflows/build-tool.yml` is the reusable workflow that holds all build
  logic (inputs `tool`, `push`, `no-cache`). Per arch, on native runners
  (`ubuntu-24.04`, `ubuntu-24.04-arm`) it builds with buildx, loads the image, runs the
  smoke test with docker and, if `push`, pushes by digest. A merge job then creates the
  multi-arch manifest. Uses the GHA build cache unless `no-cache` is set.
- `.github/scripts/list-tools.sh [<base> <head>]` prints a JSON list of tools: all
  tools, or the ones changed between two commits. A change under `.github/workflows/` or
  `.github/scripts/` counts as all tools.
- `pr.yml` builds and smoke-tests the changed tools without pushing. `pr-ok` is the
  single aggregate check to require in branch protection.
- `publish.yml` builds, tests and pushes:
  - on push to `main`: changed tools
  - weekly (Monday 04:00 UTC): all tools with `no-cache`, picking up base image and apt
    updates
  - `workflow_dispatch`: one tool (`tool` input) or all tools
- Tags: `latest`, `<VERSION>`, `<VERSION>-<yyyymmdd>`, `sha-<short>`.
- Renovate (`renovate.json`) bumps the annotated ARGs, base image tags and digests, and
  the SHA-pinned GitHub Actions. yt-dlp bumps automerge once PR checks pass. Everything
  else opens normal PRs on a weekly schedule; Actions updates are grouped into one PR.
  Merging to `main` triggers a publish.
- Third-party actions are pinned to full commit SHAs with a `# vX.Y.Z` comment.
