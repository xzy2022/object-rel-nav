#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <env-file> [output-tar]" >&2
    echo "Example:" >&2
    echo "  $0 docker/lab.env" >&2
    echo "  $0 docker/lab.env object-rel-nav-cu118.tar" >&2
    exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
fi

ENV_FILE="$1"
OUTPUT_TAR="${2:-}"

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

if [[ "${#IMAGE_NAMES[@]}" -gt 1 && -z "$OUTPUT_TAR" ]]; then
    echo "Multiple images found. Please specify output tar file explicitly:" >&2
    printf '  %s\n' "${IMAGE_NAMES[@]}" >&2
    exit 1
fi

# 单镜像时，如果没指定输出文件，则根据镜像名自动生成 tar 文件名。
if [[ -z "$OUTPUT_TAR" ]]; then
    SAFE_IMAGE_NAME="$(echo "${IMAGE_NAMES[0]}" | sed 's#[/:]#-#g')"
    OUTPUT_TAR="${SAFE_IMAGE_NAME}.tar"
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
        echo "  scripts/build_image.sh $ENV_FILE" >&2
        exit 1
    fi
done

echo "Exporting image..."
docker save -o "$OUTPUT_TAR" "${IMAGE_NAMES[@]}"

echo
echo "Export finished: $OUTPUT_TAR"