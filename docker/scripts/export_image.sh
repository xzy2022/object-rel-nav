#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <env-file>" >&2
    echo "Example:" >&2
    echo "  $0 docker/lab.env" >&2
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

ENV_FILE="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "$ENV_FILE" != /* && -f "${PROJECT_ROOT}/${ENV_FILE}" ]]; then
    ENV_FILE="${PROJECT_ROOT}/${ENV_FILE}"
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

OUTPUT_TAR="${DOCKER_EXPORT_DIR:-}"

if [[ -z "$OUTPUT_TAR" ]]; then
    echo "Error: DOCKER_EXPORT_DIR must be specified in ${ENV_FILE}." >&2
    exit 1
fi

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

# 从 compose 配置中解析镜像名。
mapfile -t IMAGE_NAMES < <(
    env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" config --images 2>/dev/null \
        | sed '/^$/d' \
        | sort -u
)

if [[ "${#IMAGE_NAMES[@]}" -eq 0 ]]; then
    echo "No image found from compose config." >&2
    exit 1
fi

echo "Images to export:"
printf '  %s\n' "${IMAGE_NAMES[@]}"
echo
echo "Output tar: $OUTPUT_TAR"
echo

# 检查镜像是否存在本地。
for image in "${IMAGE_NAMES[@]}"; do
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "Image not found locally: $image" >&2
        echo "You may need to build it first, for example:" >&2
        echo "  docker/scripts/build_image.sh $ENV_FILE" >&2
        exit 1
    fi
done

echo "Exporting image..."
docker save -o "$OUTPUT_TAR" "${IMAGE_NAMES[@]}"

echo
echo "Export finished: $OUTPUT_TAR"
