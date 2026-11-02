# renovate: datasource=repology depName=debian_13/poppler-utils
ARG VERSION=25.03.0

FROM docker.io/library/debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
ARG VERSION

LABEL org.opencontainers.image.source="https://github.com/GiDW/toolcrate" \
      org.opencontainers.image.title="poppler" \
      org.opencontainers.image.description="Poppler PDF utilities (pdftotext, pdftoppm, pdfinfo, ...) with fonts" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

# poppler-data: CJK/Cyrillic encoding maps. fontconfig + fonts: text rendering in
# pdftoppm/pdftocairo/pdftops falls back to these (Liberation is metric-compatible with
# Arial, Times New Roman and Courier New).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      "poppler-utils=${VERSION}-*" poppler-data \
      fontconfig fonts-dejavu-core fonts-liberation2 \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint

RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app \
 && mkdir -p /work \
 && chown -R app:app /home/app /work

# The executable wrappers, for users to copy out of the image (see README).
COPY bin/ /usr/local/share/toolcrate/bin/

ENV HOME=/home/app

USER app
WORKDIR /work
ENTRYPOINT ["entrypoint"]
