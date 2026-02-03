#!/bin/bash
# Container entrypoint - orchestrates execution modes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration with defaults
QBT_HOST="${QBT_HOST:-localhost}"
QBT_PORT="${QBT_PORT:-8080}"
QBT_PROTOCOL="${QBT_PROTOCOL:-http}"
PORT_FILE="${PORT_FILE:-/tmp/gluetun/forwarded_port}"
RUN_AT_START="${RUN_AT_START:-true}"
FILE_WATCH="${FILE_WATCH:-true}"
CRON_SCHEDULE="${CRON_SCHEDULE:-}"

QBT_URL="${QBT_PROTOCOL}://${QBT_HOST}:${QBT_PORT}"

# Track background processes
PIDS=()

cleanup() {
    log_info "Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Wait for qBittorrent to be available (with auth)
wait_for_qbt() {
    local max_attempts=60
    local attempt=0

    log_info "Waiting for qBittorrent at $QBT_URL..."

    # Get password from file if specified
    local password="${QBT_PASSWORD:-}"
    if [[ -n "${QBT_PASSWORD_FILE:-}" && -f "$QBT_PASSWORD_FILE" ]]; then
        password=$(cat "$QBT_PASSWORD_FILE")
    fi

    while true; do
        # Try to login and get version
        local cookie_jar="/tmp/qbt/healthcheck_cookies.txt"
        local login_ok=false

        # Clear any existing cookies before login attempt
        rm -f "$cookie_jar"

        # Attempt login if credentials provided
        if [[ -n "${QBT_USERNAME:-}" ]]; then
            local login_response
            login_response=$(curl -s -c "$cookie_jar" \
                --header "Referer: $QBT_URL" \
                --data "username=${QBT_USERNAME}&password=${password}" \
                "${QBT_URL}/api/v2/auth/login" 2>/dev/null || echo "")

            if [[ "$login_response" == "Ok." ]]; then
                login_ok=true
            fi
        else
            # No auth configured, just check if API responds
            login_ok=true
        fi

        if [[ "$login_ok" == "true" ]]; then
            # Try to get version
            local version
            version=$(curl -s -b "$cookie_jar" --header "Referer: $QBT_URL" \
                "${QBT_URL}/api/v2/app/version" 2>/dev/null || echo "")

            if [[ -n "$version" && "$version" != "Forbidden" ]]; then
                rm -f "$cookie_jar"
                log_info "qBittorrent is available (version: $version)"
                return 0
            fi
        fi

        rm -f "$cookie_jar"
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "qBittorrent not available after $max_attempts attempts"
            exit 1
        fi
        log_debug "Attempt $attempt/$max_attempts - qBittorrent not ready yet..."
        sleep 2
    done
}

main() {
    log_info "Starting gluetun-qbittorrent-portsync"
    log_info "Configuration:"
    log_info "  QBT_HOST: $QBT_HOST"
    log_info "  QBT_PORT: $QBT_PORT"
    log_info "  QBT_PROTOCOL: $QBT_PROTOCOL"
    log_info "  PORT_FILE: $PORT_FILE"
    log_info "  RUN_AT_START: $RUN_AT_START"
    log_info "  FILE_WATCH: $FILE_WATCH"
    log_info "  CRON_SCHEDULE: ${CRON_SCHEDULE:-(disabled)}"
    log_info "  LOG_LEVEL: ${LOG_LEVEL:-info}"

    # Wait for qBittorrent
    wait_for_qbt

    # Run at start if enabled
    if [[ "$RUN_AT_START" == "true" ]]; then
        log_info "Running initial sync..."
        "$SCRIPT_DIR/sync-port.sh" || log_warn "Initial sync failed, will retry"
    fi

    # Start cron if schedule provided
    if [[ -n "$CRON_SCHEDULE" ]]; then
        log_info "Starting cron with schedule: $CRON_SCHEDULE"
        # Write crontab dynamically
        echo "$CRON_SCHEDULE $SCRIPT_DIR/sync-port.sh" > /tmp/qbt/crontab
        supercronic /tmp/qbt/crontab &
        PIDS+=($!)
    fi

    # Start file watcher if enabled
    if [[ "$FILE_WATCH" == "true" ]]; then
        "$SCRIPT_DIR/watch-port.sh" &
        PIDS+=($!)
    fi

    # If no background processes, exit (one-shot mode)
    if [[ ${#PIDS[@]} -eq 0 ]]; then
        log_info "No background processes configured, exiting"
        exit 0
    fi

    # Wait for any process to exit
    log_info "Running in background mode, waiting for signals..."
    wait -n "${PIDS[@]}" 2>/dev/null || true

    # If we get here, a process exited unexpectedly
    log_error "A background process exited unexpectedly"
    cleanup
}

main "$@"
