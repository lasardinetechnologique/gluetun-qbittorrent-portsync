#!/bin/bash
# File watcher - monitors port file for changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PORT_FILE="${PORT_FILE:-/tmp/gluetun/forwarded_port}"
WATCH_MODE="${WATCH_MODE:-inotify}"
POLL_INTERVAL="${POLL_INTERVAL:-60}"

run_sync() {
    log_debug "Running port sync..."
    "$SCRIPT_DIR/sync-port.sh" || log_warn "Sync failed, will retry on next event"
}

watch_inotify() {
    local port_dir
    port_dir=$(dirname "$PORT_FILE")
    local port_filename
    port_filename=$(basename "$PORT_FILE")

    log_info "Starting inotify watcher on $PORT_FILE"

    # Wait for directory to exist
    while [[ ! -d "$port_dir" ]]; do
        log_warn "Port directory not found: $port_dir, waiting..."
        sleep 10
    done

    # Watch for changes (close_write = file finished writing, moved_to = file renamed into dir)
    inotifywait -mq -e close_write,moved_to "$port_dir" |
    while read -r directory event filename; do
        if [[ "$filename" == "$port_filename" ]]; then
            log_info "File change detected: $event"
            sleep 1  # Brief delay to ensure file is fully written
            run_sync
        fi
    done
}

watch_poll() {
    log_info "Starting poll watcher on $PORT_FILE (interval: ${POLL_INTERVAL}s)"

    local last_content=""

    while true; do
        if [[ -f "$PORT_FILE" ]]; then
            local current_content
            current_content=$(cat "$PORT_FILE" 2>/dev/null || echo "")

            if [[ "$current_content" != "$last_content" && -n "$current_content" ]]; then
                log_info "Port file changed"
                last_content="$current_content"
                run_sync
            fi
        else
            log_debug "Port file not found, waiting..."
        fi

        sleep "$POLL_INTERVAL"
    done
}

main() {
    case "$WATCH_MODE" in
        inotify)
            if command -v inotifywait &> /dev/null; then
                watch_inotify
            else
                log_warn "inotifywait not available, falling back to poll mode"
                watch_poll
            fi
            ;;
        poll)
            watch_poll
            ;;
        *)
            log_error "Unknown watch mode: $WATCH_MODE"
            exit 1
            ;;
    esac
}

main "$@"
