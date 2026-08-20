#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/opt/signoz-collector"

REPO_RAW_BASE="https://raw.githubusercontent.com/tlun0911/signoz-collector/main"

SIGNOZ_ENDPOINT="${SIGNOZ_ENDPOINT:-https://otel.lunt.app}"
OTEL_BASIC_AUTH="${OTEL_BASIC_AUTH:-}"
DEPLOYMENT_ENV="${DEPLOYMENT_ENV:-production}"
COLLECTOR_VERSION="${COLLECTOR_VERSION:-0.139.0}"

CONFIG_TEMPLATE_URL="${REPO_RAW_BASE}/config.yaml.template"
COMPOSE_TEMPLATE_URL="${REPO_RAW_BASE}/docker-compose.yaml"

CONFIG_TEMPLATE_PATH="${INSTALL_DIR}/config.yaml.template"
COMPOSE_TEMPLATE_PATH="${INSTALL_DIR}/docker-compose.yaml.template"

CONFIG_PATH="${INSTALL_DIR}/config.yaml"
COMPOSE_PATH="${INSTALL_DIR}/docker-compose.yaml"
ENV_PATH="${INSTALL_DIR}/.env"

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo."
    exit 1
fi

if [[ -z "$OTEL_BASIC_AUTH" ]]; then
    echo "OTEL_BASIC_AUTH is required."
    echo
    echo "Generate it with:"
    echo "  printf 'otel:YOUR_PASSWORD' | base64 -w0"
    echo
    echo "Then run:"
    echo
    echo "  read -rsp \"OTEL Basic Auth value: \" OTEL_BASIC_AUTH"
    echo "  echo"
    echo "  export OTEL_BASIC_AUTH"
    echo
    echo "  curl -fsSL ${REPO_RAW_BASE}/install.sh \\"
    echo "    | sudo --preserve-env=OTEL_BASIC_AUTH bash"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is not installed."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose plugin is not installed."
    exit 1
fi

echo "Installing SigNoz OpenTelemetry collector..."
echo
echo "SigNoz endpoint: $SIGNOZ_ENDPOINT"
echo "Environment:     $DEPLOYMENT_ENV"
echo "Collector:       $COLLECTOR_VERSION"
echo

mkdir -p "$INSTALL_DIR"

echo "Downloading collector configuration..."

curl -fsSL \
    "$CONFIG_TEMPLATE_URL" \
    -o "$CONFIG_TEMPLATE_PATH"

curl -fsSL \
    "$COMPOSE_TEMPLATE_URL" \
    -o "$COMPOSE_TEMPLATE_PATH"

echo "Rendering configuration..."

sed \
    -e "s|__SIGNOZ_ENDPOINT__|${SIGNOZ_ENDPOINT}|g" \
    "$CONFIG_TEMPLATE_PATH" \
    > "$CONFIG_PATH"

sed \
    -e "s|__DEPLOYMENT_ENV__|${DEPLOYMENT_ENV}|g" \
    -e "s|__COLLECTOR_VERSION__|${COLLECTOR_VERSION}|g" \
    "$COMPOSE_TEMPLATE_PATH" \
    > "$COMPOSE_PATH"

echo "Writing environment configuration..."

cat > "$ENV_PATH" <<EOF
OTEL_BASIC_AUTH=${OTEL_BASIC_AUTH}
EOF

chmod 600 "$ENV_PATH"

cd "$INSTALL_DIR"

echo
echo "Pulling collector image..."

docker compose pull

echo
echo "Starting collector..."

docker compose up -d

echo
echo "Waiting for collector to start..."
sleep 5

if ! docker ps \
    --filter "name=signoz-collection-agent" \
    --filter "status=running" \
    --format '{{.Names}}' \
    | grep -q '^signoz-collection-agent$'; then

    echo
    echo "Collector failed to start."
    echo
    docker logs --tail 100 signoz-collection-agent || true
    exit 1
fi

echo
echo "Collector container is running."

if docker logs --tail 100 signoz-collection-agent 2>&1 \
    | grep -q "Everything is ready"; then

    echo
    echo "SigNoz collector installed successfully."
else
    echo
    echo "Collector is running, but the ready message was not found."
    echo "Review the logs below:"
    echo
    docker logs --tail 50 signoz-collection-agent || true
fi

echo
echo "Installation details:"
echo
echo "  Host:        $(hostname)"
echo "  Install dir: $INSTALL_DIR"
echo "  Config:      $CONFIG_PATH"
echo "  Compose:     $COMPOSE_PATH"
echo "  Env file:    $ENV_PATH"
echo
echo "Useful commands:"
echo
echo "  docker logs -f signoz-collection-agent"
echo "  cd $INSTALL_DIR && docker compose ps"
echo "  cd $INSTALL_DIR && docker compose restart"
echo
