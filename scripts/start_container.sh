#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <env-file> [-r]" >&2
    echo "Example:" >&2
    echo "  $0 docker/local.env" >&2
    echo "  $0 docker/local.env -r" >&2
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

ENV_FILE="$1"
shift

RECREATE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r)
            RECREATE=1
            shift
            ;;
        *)
            usage
            ;;
    esac
done

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
HOST_USER="$(id -un)"
HOST_GROUP="$(id -gn)"

COMPOSE_ENV=(
    HOST_UID="$HOST_UID"
    HOST_GID="$HOST_GID"
)

if [[ "$RECREATE" -eq 1 ]]; then
    env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" down
    env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" up -d
else
    env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" up -d
fi

# 容器已启动后，用 root 进去补 /etc/passwd 和 /etc/group。
# 这样后面以 HOST_UID:HOST_GID 进入 bash 时不会显示 "I have no name!"。
env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" exec \
    -T \
    -u 0 \
    -e HOST_UID="$HOST_UID" \
    -e HOST_GID="$HOST_GID" \
    -e HOST_USER="$HOST_USER" \
    -e HOST_GROUP="$HOST_GROUP" \
    proj bash -lc '
set -euo pipefail

uid="${HOST_UID}"
gid="${HOST_GID}"
user_name="${HOST_USER:-hostuser}"
group_name="${HOST_GROUP:-hostgroup}"

# 如果 GID 不存在，创建组。
if ! getent group "${gid}" >/dev/null; then
    if getent group "${group_name}" >/dev/null; then
        group_name="hostgroup_${gid}"
    fi
    groupadd -g "${gid}" "${group_name}"
fi

# 以实际 GID 对应的组名为准。
group_name="$(getent group "${gid}" | cut -d: -f1)"

# 如果 UID 不存在，创建用户。
if ! getent passwd "${uid}" >/dev/null; then
    if getent passwd "${user_name}" >/dev/null; then
        user_name="hostuser_${uid}"
    fi
    useradd -m -u "${uid}" -g "${gid}" -s /bin/bash "${user_name}"
fi

# 保证用户 home 存在。
home_dir="$(getent passwd "${uid}" | cut -d: -f6)"
mkdir -p "${home_dir}"
chown "${uid}:${gid}" "${home_dir}" || true

# 给该 UID 对应用户免密码 sudo 权限。
user_name="$(getent passwd "${uid}" | cut -d: -f1)"

mkdir -p /etc/sudoers.d
echo "${user_name} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${user_name}"
chmod 0440 "/etc/sudoers.d/${user_name}"

# 给该用户配置 conda 自动进入 object-rel-nav。
touch "${home_dir}/.bashrc"

if ! grep -q "/opt/conda/etc/profile.d/conda.sh" "${home_dir}/.bashrc"; then
    echo ". /opt/conda/etc/profile.d/conda.sh" >> "${home_dir}/.bashrc"
fi

if ! grep -q "conda activate object-rel-nav" "${home_dir}/.bashrc"; then
    echo "conda activate object-rel-nav" >> "${home_dir}/.bashrc"
fi

chown "${uid}:${gid}" "${home_dir}/.bashrc" || true
'

env "${COMPOSE_ENV[@]}" "${COMPOSE[@]}" exec proj bash