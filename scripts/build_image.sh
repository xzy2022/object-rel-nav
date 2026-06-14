#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker/docker-compose.yml"
SERVICE_NAME="proj"
ENV_FILE="${1:-}"

usage() {
    echo "Usage: $0 <env-file>" >&2
}

if [[ "$#" -ne 1 ]]; then
    usage
    echo "Error: exactly one env file path must be specified." >&2
    exit 1
fi

if [[ "$ENV_FILE" != /* ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        ENV_FILE="$(cd "$(dirname "$ENV_FILE")" && pwd)/$(basename "$ENV_FILE")"
    elif [[ -f "${PROJECT_ROOT}/${ENV_FILE}" ]]; then
        ENV_FILE="${PROJECT_ROOT}/${ENV_FILE}"
    else
        echo "Env file not found: ${ENV_FILE}" >&2
        exit 1
    fi
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${DOCKER_IMPORT_DIR:-}" ]]; then
    echo "Error: DOCKER_IMPORT_DIR must be specified in ${ENV_FILE}." >&2
    exit 1
fi

if [[ -f "$DOCKER_IMPORT_DIR" ]]; then
    echo "Importing image from: ${DOCKER_IMPORT_DIR}"
    docker load -i "$DOCKER_IMPORT_DIR"
    exit 0
fi

HOST_UID="$(id -u)" HOST_GID="$(id -g)" \
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
    build --progress=plain "$SERVICE_NAME"
