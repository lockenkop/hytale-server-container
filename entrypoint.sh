#!/bin/sh
set -eu

# Force line buffering for TrueNAS Scale log compatibility
export PYTHONUNBUFFERED=1
stdbuf -oL -eL true 2>/dev/null && USE_STDBUF=true || USE_STDBUF=false

# --- Configuration defaults ---
export SCRIPTS_PATH="/usr/local/bin/scripts"
export SERVER_PORT="${SERVER_PORT:-5520}"
export SERVER_IP="${SERVER_IP:-0.0.0.0}"
export DEBUG="${DEBUG:-FALSE}"
export PROD="${PROD:-FALSE}"
export JAVA_ARGS="${JAVA_ARGS:-}"
export BASE_DIR="/home/container"
export GAME_DIR="$BASE_DIR/game"
export SERVER_JAR_PATH="$GAME_DIR/Server/HytaleServer.jar"
export CACHE="${CACHE:-FALSE}"
export UID="${UID:-1000}"
export GID="${GID:-1000}"
export NO_COLOR="${NO_COLOR:-FALSE}"

# --- Hytale specific environment variables ---
export HYTALE_ACCEPT_EARLY_PLUGINS="${HYTALE_ACCEPT_EARLY_PLUGINS:-FALSE}"
export HYTALE_ALLOW_OP="${HYTALE_ALLOW_OP:-FALSE}"
export HYTALE_AUTH_MODE="${HYTALE_AUTH_MODE:-FALSE}"
export HYTALE_BACKUP="${HYTALE_BACKUP:-FALSE}"
export HYTALE_BACKUP_FREQUENCY="${HYTALE_BACKUP_FREQUENCY:-}"

# Initialize flags as empty strings
export HYTALE_CACHE_FLAG=""
export HYTALE_ACCEPT_EARLY_PLUGINS_FLAG=""
export HYTALE_ALLOW_OP_FLAG=""
export HYTALE_AUTH_MODE_FLAG=""
export HYTALE_BACKUP_FLAG=""
export HYTALE_BACKUP_FREQUENCY_FLAG=""
export HYTALE_QUIET_FLAGS=""

# Load utilities
. "$SCRIPTS_PATH/utils.sh"

# --- 1. Audit Suite ---
log_section "Audit Suite"

if [ "$DEBUG" = "TRUE" ]; then
    sh "$SCRIPTS_PATH/checks/security.sh"
    sh "$SCRIPTS_PATH/checks/network.sh"
else
    printf "%sSystem debug skipped (DEBUG=FALSE)%s\n" "$DIM" "$NC"
fi

if [ "$PROD" = "TRUE" ]; then
    sh "$SCRIPTS_PATH/checks/prod.sh"
else
    printf "%sProduction audit skipped (PROD=FALSE)%s\n" "$DIM" "$NC"
fi

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    printf "############################################################\n"
    printf "  WARNING: UNSUPPORTED ARCHITECTURE DETECTED\n"
    printf "############################################################\n"
    printf " Architecture: %s\n\n" "$ARCH"
    printf " Hytale-Downloader only works for x86_64 at the moment.\n"
    printf " Status: Waiting for Hytale to release the native ARM64 binary.\n"
    printf "############################################################\n"
fi

# --- 2. Initialization ---
sh "$SCRIPTS_PATH/hytale/hytale_downloader.sh"
sh "$SCRIPTS_PATH/hytale/hytale_config.sh"
sh "$SCRIPTS_PATH/hytale/hytale_flags.sh"

# --- 3. Startup Preparation ---
log_section "Process Execution"
log_step "Finalizing Environment"
cd "$BASE_DIR"
log_success

# --- 4. Execution ---
printf "\n${BOLD}${CYAN}🚀 Launching Hytale Server...${NC}\n\n"

# Determine if we need to switch users
CURRENT_UID=$(id -u)
if [ "$CURRENT_UID" = "0" ]; then
    # Running as root, need to drop privileges
    if command -v gosu >/dev/null 2>&1; then
        RUNTIME="gosu $UID:$GID"
    elif command -v su-exec >/dev/null 2>&1; then
        RUNTIME="su-exec $UID:$GID"
    else
        RUNTIME=""
    fi
else
    # Already running as non-root, no need to switch
    RUNTIME=""
fi

# Execute Java server as non-root user
exec $RUNTIME java $JAVA_ARGS \
    -Dterminal.jline=false \
    -Dterminal.ansi=true \
    $HYTALE_CACHE_FLAG \
    $HYTALE_ACCEPT_EARLY_PLUGINS_FLAG \
    $HYTALE_ALLOW_OP_FLAG \
    $HYTALE_AUTH_MODE_FLAG \
    $HYTALE_BACKUP_FLAG \
    $HYTALE_BACKUP_FREQUENCY_FLAG \
    $HYTALE_QUIET_FLAGS \
    -jar "$SERVER_JAR_PATH" \
    --assets "$GAME_DIR/Assets.zip" \
    --bind "$SERVER_IP:$SERVER_PORT"