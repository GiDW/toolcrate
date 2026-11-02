# The image is versioned by 7-Zip, the main extractor; unpack itself is the small
# dispatcher script next to this file.
# renovate: datasource=repology depName=debian_13/7zip
ARG VERSION=25.01
# renovate: datasource=repology depName=debian_13/unrar
ARG UNRAR_VERSION=7.1.8
# renovate: datasource=repology depName=debian_13/unar
ARG UNAR_VERSION=1.10.8

FROM docker.io/library/debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
ARG VERSION
ARG UNRAR_VERSION
ARG UNAR_VERSION

LABEL org.opencontainers.image.source="https://github.com/GiDW/toolcrate" \
      org.opencontainers.image.title="unpack" \
      org.opencontainers.image.description="Extract zip, 7z, rar (incl. split archives) and tar.* with 7-Zip, unrar and The Unarchiver's unar, picked automatically" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="LGPL-2.1-or-later AND LicenseRef-unRAR"

# unrar is in Debian's non-free component (freeware, redistributable). xz-utils, bzip2
# and zstd let tar read .tar.xz, .tar.bz2 and .tar.zst; gzip is in the base image.
RUN sed -i 's/^Components: main$/Components: main non-free/' /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "7zip=${VERSION}+*" "unrar=1:${UNRAR_VERSION}-*" "unar=${UNAR_VERSION}+*" \
      xz-utils bzip2 zstd \
 && rm -rf /var/lib/apt/lists/*

COPY unpack.sh /usr/local/bin/unpack

RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app \
 && mkdir -p /work \
 && chown -R app:app /home/app /work

# The executable wrappers, for users to copy out of the image (see README).
COPY bin/ /usr/local/share/toolcrate/bin/

ENV HOME=/home/app

USER app
WORKDIR /work
ENTRYPOINT ["unpack"]
