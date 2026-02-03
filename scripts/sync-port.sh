#!/bin/bash
# Core sync logic - reads port file and updates qBittorrent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration with defaults
QBT_HOST="${QBT_HOST:-localhost}"
QBT_PORT="${QBT_PORT:-8080}"
QBT_PROTOCOL="${QBT_PROTOCOL:-http}"
QBT_USERNAME="${QBT_USERNAME:-}"
QBT_PASSWORD="${QBT_PASSWORD:-}"
QBT_PASSWORD_FILE="${QBT_PASSWORD_FILE:-}"
PORT_FILE="${PORT_FILE:-/tmp/gluetun/forwarded_port}"
BASIC_AUTH_USER="${BASIC_AUTH_USER:-}"
BASIC_AUTH_PASS="${BASIC_AUTH_PASS:-}"

QBT_URL="${QBT_PROTOCOL}://${QBT_HOST}:${QBT_PORT}"
COOKIE_JAR="/tmp/qbt/cookies_$$.txt"

cleanup() {
    rm -f "$COOKIE_JAR"
}
trap cleanup EXIT

# Read port from file
read_port_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "Port file not found: $file"
        return 1
    fi

    local port
    port=$(tr -d '[:space:]' < "$file")

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port (not a number): $port"
        return 1
    fi

    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        log_error "Invalid port (out of range): $port"
        return 1
    fi

    echo "$port"
}

# Authenticate with qBittorrent
qbt_login() {
    local password="$QBT_PASSWORD"

    # Read password from file if specified
    if [[ -n "$QBT_PASSWORD_FILE" && -f "$QBT_PASSWORD_FILE" ]]; then
        password=$(cat "$QBT_PASSWORD_FILE")
    fi

    # Skip auth if no username configured (bypass auth for localhost mode)
    if [[ -z "$QBT_USERNAME" ]]; then
        log_debug "No username configured, skipping authentication"
        return 0
    fi

    log_debug "Authenticating with qBittorrent..."

    # Clear any existing cookies before login
    rm -f "$COOKIE_JAR"

    local response
    if [[ -n "$BASIC_AUTH_USER" ]]; then
        response=$(curl -s -c "$COOKIE_JAR" \
            --user "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}" \
            --header "Referer: $QBT_URL" \
            --data "username=${QBT_USERNAME}&password=${password}" \
            "${QBT_URL}/api/v2/auth/login" 2>/dev/null) || {
            log_error "Failed to connect to qBittorrent"
            return 1
        }
    else
        response=$(curl -s -c "$COOKIE_JAR" \
            --header "Referer: $QBT_URL" \
            --data "username=${QBT_USERNAME}&password=${password}" \
            "${QBT_URL}/api/v2/auth/login" 2>/dev/null) || {
            log_error "Failed to connect to qBittorrent"
            return 1
        }
    fi

    if [[ "$response" != "Ok." ]]; then
        log_error "qBittorrent login failed: $response"
        return 1
    fi

    log_debug "Authentication successful"
    return 0
}

# Get current qBittorrent listening port
qbt_get_port() {
    local response
    if [[ -n "$BASIC_AUTH_USER" ]]; then
        response=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            --user "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}" \
            --header "Referer: $QBT_URL" \
            "${QBT_URL}/api/v2/app/preferences" 2>/dev/null) || {
            log_error "Failed to get preferences"
            return 1
        }
    else
        response=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            --header "Referer: $QBT_URL" \
            "${QBT_URL}/api/v2/app/preferences" 2>/dev/null) || {
            log_error "Failed to get preferences"
            return 1
        }
    fi

    local port
    port=$(echo "$response" | jq -r '.listen_port')

    if [[ -z "$port" ]]; then
        log_error "Could not parse listen_port from response"
        return 1
    fi

    echo "$port"
}

# Set qBittorrent listening port
qbt_set_port() {
    local port="$1"

    local response
    if [[ -n "$BASIC_AUTH_USER" ]]; then
        response=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            --user "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}" \
            --header "Referer: $QBT_URL" \
            --data "json={\"listen_port\":${port}}" \
            "${QBT_URL}/api/v2/app/setPreferences" 2>/dev/null) || {
            log_error "Failed to set port"
            return 1
        }
    else
        response=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            --header "Referer: $QBT_URL" \
            --data "json={\"listen_port\":${port}}" \
            "${QBT_URL}/api/v2/app/setPreferences" 2>/dev/null) || {
            log_error "Failed to set port"
            return 1
        }
    fi

    return 0
}

# Main sync function
main() {
    log_debug "Starting port sync"
    log_debug "qBittorrent URL: $QBT_URL"
    log_debug "Port file: $PORT_FILE"

    # Read target port from file
    local target_port
    target_port=$(read_port_file "$PORT_FILE") || exit 1
    log_info "Target port from file: $target_port"

    # Authenticate
    qbt_login || exit 1

    # Get current port
    local current_port
    current_port=$(qbt_get_port) || exit 1
    log_info "Current qBittorrent port: $current_port"

    # Compare and update if needed
    if [[ "$current_port" == "$target_port" ]]; then
        log_info "Port already set correctly, no update needed"
    else
        log_info "Updating port from $current_port to $target_port"
        qbt_set_port "$target_port" || exit 1
        log_info "Port updated successfully"
    fi
}

main "$@"
