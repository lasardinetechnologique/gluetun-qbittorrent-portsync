# gluetun-qbittorrent-portsync

Sync the forwarded port from Gluetun to qBittorrent automatically.

When using Gluetun with ProtonVPN (or other providers with port forwarding), the forwarded port changes on each connection. This container watches the port file and updates qBittorrent's listening port via its WebUI API.

## Features

- Watch port file for changes (inotify)
- Run sync at container startup
- Optional cron schedule
- Polling fallback if inotify unavailable
- Supports qBittorrent authentication
- Supports basic auth (reverse proxy)

## Quick Start

```yaml
services:
  portsync:
    image: ghcr.io/lasardinetechnologique/gluetun-qbittorrent-portsync
    network_mode: "service:gluetun"
    volumes:
      - gluetun_data:/tmp/gluetun:ro
    environment:
      - QBT_USERNAME=admin
      - QBT_PASSWORD=adminadmin
```

See [docker-compose.yml](docker-compose.yml) for a complete example with Gluetun and qBittorrent.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `QBT_HOST` | `localhost` | qBittorrent host |
| `QBT_PORT` | `8080` | qBittorrent WebUI port |
| `QBT_PROTOCOL` | `http` | Protocol (`http` or `https`) |
| `QBT_USERNAME` | - | qBittorrent username |
| `QBT_PASSWORD` | - | qBittorrent password |
| `QBT_PASSWORD_FILE` | - | Path to password file (Docker secrets) |
| `PORT_FILE` | `/tmp/gluetun/forwarded_port` | Path to forwarded port file |
| `BASIC_AUTH_USER` | - | Basic auth username (reverse proxy) |
| `BASIC_AUTH_PASS` | - | Basic auth password |
| `RUN_AT_START` | `true` | Run sync on container start |
| `FILE_WATCH` | `true` | Watch file for changes |
| `WATCH_MODE` | `inotify` | Watch mode: `inotify` or `poll` |
| `POLL_INTERVAL` | `60` | Polling interval in seconds |
| `CRON_SCHEDULE` | - | Cron expression (e.g., `*/5 * * * *`) |
| `LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |

## Usage Modes

### File Watching (default)

Watches the port file using inotify and syncs immediately when it changes:

```yaml
environment:
  - FILE_WATCH=true
  - RUN_AT_START=true
```

### Cron Schedule

Runs sync on a schedule (useful as backup or if inotify doesn't work):

```yaml
environment:
  - FILE_WATCH=false
  - CRON_SCHEDULE=*/5 * * * *
```

### Both

Use both file watching and cron for extra reliability:

```yaml
environment:
  - FILE_WATCH=true
  - CRON_SCHEDULE=*/15 * * * *
```

### One-shot

Run sync once and exit (for external scheduling):

```yaml
environment:
  - FILE_WATCH=false
  - RUN_AT_START=true
```

## Docker Compose Example

See [docker-compose.yml](docker-compose.yml) for a complete example with Gluetun and qBittorrent.

## Building

```bash
docker build -t gluetun-qbittorrent-portsync .
```

Multi-arch build:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t gluetun-qbittorrent-portsync .
```

## License

MIT
