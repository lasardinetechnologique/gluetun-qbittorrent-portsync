FROM alpine:3.21

LABEL description="Sync Gluetun forwarded port to qBittorrent"

# Build argument for architecture-specific supercronic
ARG TARGETARCH

# Install runtime dependencies
# hadolint ignore=DL3018
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache \
    bash \
    curl \
    jq \
    inotify-tools

# Install supercronic (cron for containers)
RUN set -ex; \
    case "${TARGETARCH}" in \
        amd64) ARCH="linux-amd64" ;; \
        arm64) ARCH="linux-arm64" ;; \
        arm)   ARCH="linux-arm" ;; \
        *)     ARCH="linux-amd64" ;; \
    esac; \
    wget -q -O /usr/local/bin/supercronic \
        "https://github.com/aptible/supercronic/releases/download/v0.2.42/supercronic-${ARCH}"; \
    chmod +x /usr/local/bin/supercronic

# Create non-root user (UID 65532 - standard nonroot UID)
RUN addgroup -g 65532 -S portsync && \
    adduser -u 65532 -S -G portsync -H -s /sbin/nologin portsync

# Create app directory with proper ownership
WORKDIR /app
RUN mkdir -p /tmp/qbt && chown -R 65532:65532 /app /tmp/qbt

# Copy scripts
COPY --chown=65532:65532 scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Environment defaults
ENV QBT_HOST=localhost \
    QBT_PORT=8080 \
    QBT_PROTOCOL=http \
    PORT_FILE=/tmp/gluetun/forwarded_port \
    RUN_AT_START=true \
    FILE_WATCH=true \
    WATCH_MODE=inotify \
    POLL_INTERVAL=60 \
    LOG_LEVEL=info

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/app/scripts/healthcheck.sh"]

# Run as non-root
USER 65532:65532

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
