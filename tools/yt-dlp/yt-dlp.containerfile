# renovate: datasource=pypi depName=yt-dlp
ARG VERSION=2026.10.26
# renovate: datasource=docker depName=denoland/deno extractVersion=^bin-(?<version>.+)$
ARG DENO_VERSION=2.9.7

FROM docker.io/denoland/deno:bin-${DENO_VERSION} AS deno

FROM docker.io/library/python:3.14.8-slim-trixie@sha256:fbecd461fc72d21b2143c6eaba25143738079154a6d0ea3da3aec724f50eed4a AS builder
ARG VERSION
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --disable-pip-version-check \
      "yt-dlp[default,curl-cffi]==${VERSION}"

FROM docker.io/library/python:3.14.8-slim-trixie@sha256:fbecd461fc72d21b2143c6eaba25143738079154a6d0ea3da3aec724f50eed4a
ARG VERSION

LABEL org.opencontainers.image.source="https://github.com/GiDW/toolcrate" \
      org.opencontainers.image.title="yt-dlp" \
      org.opencontainers.image.description="yt-dlp with ffmpeg, deno, yt-dlp-ejs and curl_cffi" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="Unlicense"

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
 && rm -rf /var/lib/apt/lists/*

COPY --from=deno /deno /usr/local/bin/deno
COPY --from=builder /opt/venv /opt/venv

RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app \
 && mkdir -p /home/app/.config/yt-dlp /home/app/.cache/yt-dlp /work \
 && chown -R app:app /home/app /work

# The executable wrappers, for users to copy out of the image (see README).
COPY bin/ /usr/local/share/toolcrate/bin/

ENV PATH="/opt/venv/bin:${PATH}" \
    HOME=/home/app \
    PYTHONUNBUFFERED=1 \
    DENO_NO_UPDATE_CHECK=1

USER app
WORKDIR /work
ENTRYPOINT ["yt-dlp"]
