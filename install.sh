#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/opt/signoz-collector"

SIGNOZ_ENDPOINT="${SIGNOZ_ENDPOINT:-}"
DEPLOYMENT_ENV="${DEPLOYMENT_ENV:-production}"
COLLECTOR_VERSION="${COLLECTOR_VERSION:-0.139.0}"

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo."
    exit 1
fi

if [[ -z "$SIGNOZ_ENDPOINT" ]]; then
    echo "SIGNOZ_ENDPOINT is required."
    echo
    echo "Example:"
    echo "  sudo SIGNOZ_ENDPOINT=135.148.42.245:4317 ./install.sh"
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

sed \
    -e "s|__SIGNOZ_ENDPOINT__|${SIGNOZ_ENDPOINT}|g" \
    config.yaml.template \
    > "$INSTALL_DIR/config.yaml"

sed \
    -e "s|__DEPLOYMENT_ENV__|${DEPLOYMENT_ENV}|g" \
    -e "s|__COLLECTOR_VERSION__|${COLLECTOR_VERSION}|g" \
    docker-compose.yaml \
    > "$INSTALL_DIR/docker-compose.yaml"

cd "$INSTALL_DIR"

echo "Starting collector..."

docker compose pull
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

if docker logs --tail 100 signoz-collection-agent 2>&1 \
    | grep -q "Everything is ready"; then

    echo
    echo "SigNoz collector installed successfully."
    echo
    echo "Host: $(hostname)"
    echo "Config: $INSTALL_DIR/config.yaml"
    echo
    echo "Check logs with:"
    echo "  docker logs -f signoz-collection-agent"
else
    echo
    echo "Collector is running, but the ready message was not found."
    echo "Check its logs with:"
    echo "  docker logs --tail 100 signoz-collection-agent"
fi
