#!/bin/sh
set -eu

# Hytale Server Configuration Manager - Manages config.json creation, validation, and environment variable overrides

# Load dependencies
. "$SCRIPTS_PATH/utils.sh"

# Constants
readonly CONFIG_FILE="/home/container/config.json"
readonly CONFIG_BACKUP_SUFFIX=".invalid.bak"
readonly CONFIG_TMP_SUFFIX=".tmp"

# Create default configuration template
create_default_config() {
    cat <<'EOF' > "$CONFIG_FILE"
{
    "Version": 3,
    "ServerName": "Hytale Server",
    "MOTD": "",
    "Password": "",
    "MaxPlayers": 100,
    "MaxViewRadius": 32,
    "LocalCompressionEnabled": false,
    "Defaults": { 
        "World": "default", 
        "GameMode": "Adventure" 
    },
    "ConnectionTimeouts": { 
        "JoinTimeouts": {} 
    },
    "RateLimit": {},
    "Modules": {},
    "LogLevels": {},
    "Mods": {},
    "DisplayTmpTagsInStrings": false,
    "PlayerStorage": { 
        "Type": "Hytale" 
    }
}
EOF
}

# Validate that config file contains valid JSON - Returns: 0 if valid, 1 if invalid
validate_config_json() {
    jq empty "$CONFIG_FILE" >/dev/null 2>&1
}

# Apply environment variable to JSON config - Args: $1=JSON path, $2=value - Returns: 0 on success, 1 on failure
apply_env() {
    local path="$1"
    local value="$2"
    local tmp_file="${CONFIG_FILE}${CONFIG_TMP_SUFFIX}"

    # Skip if environment variable is not set
    [ -z "$value" ] && return 0

    # Determine value type and apply appropriate jq filter
    case "$value" in
        true|false|[0-9]*)
            # Boolean or numeric value (no quotes)
            if ! jq "$path = $value" "$CONFIG_FILE" > "$tmp_file" 2>/dev/null; then
                printf "      ${YELLOW}⚠ Failed to apply %s${NC}\n" "$path"
                rm -f "$tmp_file"
                return 1
            fi
            ;;
        *)
            # String value (wrap in quotes)
            if ! jq "$path = \"$value\"" "$CONFIG_FILE" > "$tmp_file" 2>/dev/null; then
                printf "      ${YELLOW}⚠ Failed to apply %s${NC}\n" "$path"
                rm -f "$tmp_file"
                return 1
            fi
            ;;
    esac

    # Atomically replace config file
    mv "$tmp_file" "$CONFIG_FILE"
    return 0
}

# Main Configuration Logic
log_section "Config Management"

# Step 1: Ensure configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_step "Generating new config"
    create_default_config
    log_success
else
    log_step "Updating existing config"
    
    # Validate existing configuration
    if ! validate_config_json; then
        printf "      ${YELLOW}⚠ Invalid JSON detected. Backing up and recreating...${NC}\n"
        mv "$CONFIG_FILE" "${CONFIG_FILE}${CONFIG_BACKUP_SUFFIX}"
        create_default_config
    fi
    
    log_success
fi

# Step 2: Apply environment variable overrides
log_step "Applying environment overrides"

apply_env ".ServerName"               "${HYTALE_SERVER_NAME:-}"
apply_env ".MOTD"                     "${HYTALE_MOTD:-}"
apply_env ".Password"                 "${HYTALE_PASSWORD:-}"
apply_env ".MaxPlayers"               "${HYTALE_MAX_PLAYERS:-}"
apply_env ".MaxViewRadius"            "${HYTALE_MAX_VIEW_RADIUS:-}"
apply_env ".LocalCompressionEnabled"  "${HYTALE_COMPRESSION:-}"
apply_env ".Defaults.World"           "${HYTALE_WORLD:-}"
apply_env ".Defaults.GameMode"        "${HYTALE_GAMEMODE:-}"

log_success