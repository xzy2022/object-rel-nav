#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <env-file>" >&2
    echo "Example:" >&2
    echo "  $0 docker/local.env" >&2
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

ENV_FILE="$1"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMPOSE=(
    docker compose
    --env-file "$ENV_FILE"
    -f "${PROJECT_ROOT}/docker/docker-compose.yml"
)

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

COMPOSE_ENV=(
    HOST_UID="$HOST_UID"
    HOST_GID="$HOST_GID"
)

echo "Using env file: $ENV_FILE"
echo "Using compose file: ${PROJECT_ROOT}/docker/docker-compose.yml"
echo

# 先记录相关镜像。
# docker compose images -q: 记录当前该 compose 项目容器实际使用的镜像 ID
# docker compose config --images: 记录 compose 配置中声明的 image 名称
mapfile -t IMAGE_IDS < <(
    env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" images -q 2>/dev/null \
        | sed '/^$/d' \
        | sort -u
)

mapfile -t IMAGE_NAMES < <(
    env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" config --images 2>/dev/null \
        | sed '/^$/d' \
        | sort -u
)

echo "Stopping containers..."
env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" stop || true

echo "Removing containers..."
env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" rm -f || true

echo "Removing compose network and orphan containers..."
env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" down --remove-orphans || true

echo "Removing related images..."

if [[ "${#IMAGE_IDS[@]}" -gt 0 ]]; then
    echo "Removing image IDs:"
    printf '  %s\n' "${IMAGE_IDS[@]}"
    docker rmi -f "${IMAGE_IDS[@]}" || true
fi

if [[ "${#IMAGE_NAMES[@]}" -gt 0 ]]; then
    echo "Removing image names:"
    printf '  %s\n' "${IMAGE_NAMES[@]}"
    docker rmi -f "${IMAGE_NAMES[@]}" || true
fi

echo
echo "Clean finished."