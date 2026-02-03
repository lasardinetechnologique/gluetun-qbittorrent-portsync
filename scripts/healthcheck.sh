#!/bin/bash
# Healthcheck script - verifies the container is working properly

set -euo pipefail

# Check if main processes are running
if [[ "${FILE_WATCH:-true}" == "true" ]]; then
    # Check if watch-port.sh or inotifywait is running
    pgrep -f "watch-port.sh|inotifywait" > /dev/null || exit 1
fi

if [[ -n "${CRON_SCHEDULE:-}" ]]; then
    # Check if supercronic is running
    pgrep -f "supercronic" > /dev/null || exit 1
fi

# If we get here, container is healthy
exit 0
