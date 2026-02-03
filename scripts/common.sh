#!/bin/bash
# Common functions for logging and configuration

LOG_LEVEL="${LOG_LEVEL:-info}"

# Log levels: debug=0, info=1, warn=2, error=3
get_log_level_num() {
    case "$1" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

log() {
    local level="$1"
    shift
    local level_num
    level_num=$(get_log_level_num "$level")
    local current_level_num
    current_level_num=$(get_log_level_num "$LOG_LEVEL")

    if [[ $level_num -ge $current_level_num ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [${level^^}] $*"
    fi
}

log_debug() { log debug "$@"; }
log_info()  { log info "$@"; }
log_warn()  { log warn "$@"; }
log_error() { log error "$@" >&2; }
