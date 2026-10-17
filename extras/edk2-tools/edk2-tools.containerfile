# renovate: datasource=github-tags depName=tianocore/edk2 extractVersion=^edk2-stable(?<version>\d+)$
ARG VERSION=202608

FROM docker.io/library/debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f AS builder
ARG VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential ca-certificates git python3 uuid-dev \
 && rm -rf /var/lib/apt/lists/*
# GitHub's release tarballs lack submodules, so clone; only the brotli submodule is
# needed for the C tools.
RUN git clone --depth 1 --branch "edk2-stable${VERSION}" https://github.com/tianocore/edk2.git /edk2 \
 && git -C /edk2 submodule update --init --depth 1 BaseTools/Source/C/BrotliCompress/brotli \
 && make -C /edk2/BaseTools/Source/C -j"$(nproc)"

# Only the compiled tools; CI exports this stage as the release tarball.
FROM scratch AS binaries
COPY --from=builder /edk2/BaseTools/Source/C/bin/ /

FROM docker.io/library/debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
ARG VERSION

LABEL org.opencontainers.image.source="https://github.com/GiDW/toolcrate" \
      org.opencontainers.image.title="edk2-tools" \
      org.opencontainers.image.description="TianoCore EDK II BaseTools (EfiRom, GenFw, ...)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="BSD-2-Clause-Patent"

COPY --from=binaries / /usr/local/bin/

RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin app \
 && mkdir /work && chown app:app /work

# The executable wrappers, for users to copy out of the image (see README).
COPY bin/ /usr/local/share/toolcrate/bin/

USER app:app
ENV HOME=/home/app
WORKDIR /work
ENTRYPOINT ["EfiRom"]
