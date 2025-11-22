#!/usr/bin/env bash

set -eo pipefail

# Color/formatting functions
print_formatted() {
    local format="$1"
    local text="$2"
    printf "\033[${format}m%s\033[0m" "$text"
}

print_bold() { print_formatted "1" "$1"; }
print_green() { print_formatted "32" "$1"; }
print_bold_green() { print_formatted "1;32" "$1"; }
print_blue() { print_formatted "34" "$1"; }
print_bold_blue() { print_formatted "1;34" "$1"; }
print_red() { print_formatted "31" "$1"; }

print_separator() {
    printf "\n"
    print_bold_blue "========================================================"
    printf "\n"
}

print_label_value() {
    print_bold "$1"
    printf ": "
    print_blue "$2"
    printf "\n"
}

# Function to prompt for input with a default value
prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local optional="${4:-}"

    printf "\n"
    print_bold_green "• $prompt"
    if [ -n "$optional" ]; then
        print_bold_green " (optional)"
    fi
    printf "\n"

    if [ -n "$default" ]; then
        printf "  "
        print_blue "Default: "
        print_bold_blue "$default"
        printf "\n"
    fi

    printf "  ▶ "
    read -r input
    input=$(echo "$input" | xargs)

    eval "$var_name=\${input:-$default}"

    local final_value
    final_value=$(eval "echo \$$var_name")

    if [ -z "$optional" ] && [ -z "$final_value" ]; then
        print_red "❌ Error: This field is required"
        printf "\n"
        exit 1
    fi
}

USER_WORKING_DIR="${USER_WORKING_DIR:-.}"
echo "Working directory is: $USER_WORKING_DIR"


# Default configuration values (fallback if setup-defaults.env is not found)
declare -A DEFAULTS=(
    ["PARTICIPANT_NAME"]="consumer"
    ["DOMAIN_NAME"]=""
    ["PARTICIPANT_ROOT_FOLDER"]="$USER_WORKING_DIR/participants"
    ["PROXY_FOLDER"]="$USER_WORKING_DIR/reverse-proxy/caddy"
    ["USE_LETSENCRYPT"]="true"
    ["OPENTUNITY_IDP_URL"]="https://idm.opentunity.que-tech.com"
    ["ISSUER_DID"]="did:web:idm.opentunity.que-tech.com:wallet-api:registry:6525bd9c-7010-49be-a9ff-358fb1649c5f"
    ["ISSUER_API_KEY"]=""
    ["CONNECTOR_OPENAPI_URL"]=""
)

# Load defaults from file if it exists
DEFAULTS_FILE="$USER_WORKING_DIR/setup-defaults.env"
if [ -f "$DEFAULTS_FILE" ]; then
    print_blue "📄 Loading defaults from: $DEFAULTS_FILE"
    printf "\n"
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Expand $USER_WORKING_DIR in value if present
        value="${value//\$USER_WORKING_DIR/$USER_WORKING_DIR}"

        # Update DEFAULTS array
        DEFAULTS["$key"]="$value"
    done < "$DEFAULTS_FILE"
fi

# Check if running in non-interactive mode
if [ "$SKIP_PROMPTS" = "true" ]; then
    # Non-interactive mode - use pre-set environment variables
    participant_name="$PARTICIPANT_NAME"
    domain_name="$DOMAIN_NAME"
    participant_root_folder="${PARTICIPANT_ROOT_FOLDER:-${DEFAULTS[PARTICIPANT_ROOT_FOLDER]}}"
    proxy_folder="${PROXY_FOLDER:-${DEFAULTS[PROXY_FOLDER]}}"
    use_letsencrypt="${USE_LETSENCRYPT:-${DEFAULTS[USE_LETSENCRYPT]}}"
    opentunity_idp_url="${OPENTUNITY_IDP_URL:-${DEFAULTS[OPENTUNITY_IDP_URL]}}"
    issuer_api_url="${ISSUER_API_BASE_URL:-$opentunity_idp_url}"
    issuer_did="${ISSUER_DID:-${DEFAULTS[ISSUER_DID]}}"
    issuer_api_key="$ISSUER_API_KEY"
    verifier_api_url="${VERIFIER_API_BASE_URL:-$opentunity_idp_url}"
    connector_openapi_url="${CONNECTOR_OPENAPI_URL:-}"

    # Validate required fields in non-interactive mode
    if [ -z "$participant_name" ] || [ -z "$domain_name" ] || [ -z "$issuer_api_key" ]; then
        print_red "❌ Error: Required environment variables missing in non-interactive mode"
        print_red "   Required: PARTICIPANT_NAME, DOMAIN_NAME, ISSUER_API_KEY"
        exit 1
    fi
else
    # Interactive mode - collect user inputs
    prompt_user "Enter participant name" "${DEFAULTS[PARTICIPANT_NAME]}" participant_name
    prompt_user "Enter domain name" "${DEFAULTS[DOMAIN_NAME]}" domain_name
    prompt_user "Enter participant root folder" "${DEFAULTS[PARTICIPANT_ROOT_FOLDER]}" participant_root_folder
    prompt_user "Enter proxy folder" "${DEFAULTS[PROXY_FOLDER]}" proxy_folder
    prompt_user "Use Let's Encrypt? (true/false)" "${DEFAULTS[USE_LETSENCRYPT]}" use_letsencrypt
    prompt_user "Set URL of OPENTUNITY's Identity Provider" "${DEFAULTS[OPENTUNITY_IDP_URL]}" opentunity_idp_url
    prompt_user "Set URL of the Issuer API" "$opentunity_idp_url" issuer_api_url
    prompt_user "Set DID of the trust anchor (i.e., the central trusted issuer)" "${DEFAULTS[ISSUER_DID]}" issuer_did
    prompt_user "Set API key to access the Issuer API" "${DEFAULTS[ISSUER_API_KEY]}" issuer_api_key
    prompt_user "Set URL of the Verifier API" "$opentunity_idp_url" verifier_api_url
    OPENAPI_URL_PROMPT="Enter the URL of the OpenAPI file that defines your connector's API, \
or leave it blank if your connector functions strictly as a consumer \
(e.g., https://petstore3.swagger.io/api/v3/openapi.json)"
    prompt_user "$OPENAPI_URL_PROMPT" "${DEFAULTS[CONNECTOR_OPENAPI_URL]}" connector_openapi_url "true"
fi

# Export environment variables
declare -A ENV_VARS=(
    ["PARTICIPANT_ROOT_FOLDER"]="$participant_root_folder"
    ["PARTICIPANT_NAME"]="$participant_name"
    ["DOMAIN_NAME"]="$domain_name"
    ["PROXY_FOLDER"]="$proxy_folder"
    ["USE_LETSENCRYPT"]="$use_letsencrypt"
    ["OPENTUNITY_IDP_URL"]="$opentunity_idp_url"
    ["ISSUER_API_BASE_URL"]="$issuer_api_url"
    ["ISSUER_DID"]="$issuer_did"
    ["ISSUER_API_KEY"]="$issuer_api_key"
    ["VERIFIER_API_BASE_URL"]="$verifier_api_url"
    ["CONNECTOR_OPENAPI_URL"]="$connector_openapi_url"
)

for key in "${!ENV_VARS[@]}"; do
    export "$key"="${ENV_VARS[$key]}"
done

# Setup derived paths
PARTICIPANT_FOLDER="$PARTICIPANT_ROOT_FOLDER/$PARTICIPANT_NAME"
PARTICIPANT_TEMPLATE="$USER_WORKING_DIR/../participant-template/"
EXTERNAL_PROXY_FOLDER="$PROXY_FOLDER"
PROXY_CERT_FOLDER="$PROXY_FOLDER/certs"

export PARTICIPANT_FOLDER PARTICIPANT_TEMPLATE EXTERNAL_PROXY_FOLDER PROXY_CERT_FOLDER

# Display configuration
print_separator
print_bold_green "🚀 Setting up OPENTUNITY participant"
print_separator

declare -A DISPLAY_VARS=(
    ["Name"]="$PARTICIPANT_NAME"
    ["Folder"]="$PARTICIPANT_FOLDER"
    ["Domain"]="$DOMAIN_NAME"
    ["Proxy folder"]="$PROXY_FOLDER"
    ["Using Let's Encrypt"]="$USE_LETSENCRYPT"
)

printf "\n📋 Configuration Summary:\n\n"
for label in "${!DISPLAY_VARS[@]}"; do
    printf "  "
    print_label_value "$label" "${DISPLAY_VARS[$label]}"
done

if [ -n "$CONNECTOR_OPENAPI_URL" ]; then
    printf "  "
    print_label_value "API exposed by the connector" "$CONNECTOR_OPENAPI_URL"
fi

printf "\n"
print_bold_green "🔧 Setting up participant environment..."
printf "\n"

# Setup participant
if [ -d "$PARTICIPANT_FOLDER" ]; then
    print_blue "📦 Cleaning up existing participant..."
    # Only stop services if not in package generation mode
    if [ "$SKIP_PROMPTS" != "true" ]; then
        (cd "$PARTICIPANT_FOLDER" && task stop-all) || print_red "⚠️  Failed to stop participant"
    fi
    printf "\n"
    sudo rm -R "$PARTICIPANT_FOLDER" || print_red "⚠️  Failed to remove participant folder"
fi

mkdir -p "$PARTICIPANT_FOLDER"
cp -R "$PARTICIPANT_TEMPLATE"/* "$PARTICIPANT_FOLDER/"
envsubst <"$PARTICIPANT_TEMPLATE/.env.tmpl" >"$PARTICIPANT_FOLDER/.env"

# Only perform configuration and deployment steps if not in package generation mode
if [ "$SKIP_PROMPTS" != "true" ]; then
    print_bold_green "⚙️ Configuring participant services..."
    printf "\n"
    (cd "$PARTICIPANT_FOLDER" && task config-all)
    cp "$PARTICIPANT_FOLDER/reverse-proxy/caddy/conf.d/$PARTICIPANT_NAME.caddy" "$EXTERNAL_PROXY_FOLDER/conf.d/$PARTICIPANT_NAME.caddy"
    docker compose -f "$EXTERNAL_PROXY_FOLDER/../docker-compose.yml" restart caddy
fi

print_bold_green "✨ Configuration complete!"
printf "\n"

if [ "$SKIP_PROMPTS" != "true" ]; then
    print_blue "📋 Next steps:"
    print_blue "   1. Navigate to the participant folder: cd '$PARTICIPANT_FOLDER'"
    print_blue "   2. Start all services: task start-all"
    print_blue "   3. The start-all task will handle Docker network and proxy setup"
fi
