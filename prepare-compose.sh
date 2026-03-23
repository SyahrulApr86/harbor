#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "${SCRIPT_DIR}/.env"

ARCHIVE="harbor-online-installer-${HARBOR_VERSION}.tgz"
URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${ARCHIVE}"

DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"
INSTALLER_DIR="${SCRIPT_DIR}/installer"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE}"

TEMPLATE="${SCRIPT_DIR}/harbor.yml.template"
INSTALLER_OUTPUT="${INSTALLER_DIR}/harbor/harbor.yml"
GENERATED_COMPOSE="${INSTALLER_DIR}/harbor/docker-compose.yml"

HOST_UID=$(id -u)
HOST_GID=$(id -g)

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

echo "[INFO] Using UID:GID = ${HOST_UID}:${HOST_GID}"

mkdir -p "${DOWNLOAD_DIR}" "${INSTALLER_DIR}"

# ===== Validate docker network =====
if ! docker network inspect "${HARBOR_PROXY_NETWORK}" >/dev/null 2>&1; then
  echo "[ERROR] Docker network ${HARBOR_PROXY_NETWORK} not found." >&2
  exit 1
fi

# ===== Download Harbor =====
if [ ! -f "${ARCHIVE_PATH}" ]; then
  echo "[INFO] Downloading ${ARCHIVE} ..."
  curl -fL "${URL}" -o "${ARCHIVE_PATH}"
else
  echo "[INFO] Using cached ${ARCHIVE_PATH}"
fi

# ===== Clean previous installer safely =====
if [ -e "${INSTALLER_DIR}/harbor" ]; then
  echo "[INFO] Cleaning previous Harbor installer..."
  docker run --rm \
    -u "${HOST_UID}:${HOST_GID}" \
    -v "${INSTALLER_DIR}:/work" \
    alpine:3.20 \
    sh -lc 'rm -rf /work/harbor'
fi

# ===== Extract =====
echo "[INFO] Extracting Harbor installer..."
tar -xzf "${ARCHIVE_PATH}" -C "${INSTALLER_DIR}"

# ===== Generate harbor.yml =====
echo "[INFO] Generating harbor.yml..."
mkdir -p "$(dirname "${INSTALLER_OUTPUT}")"

sed \
  -e "s/__HARBOR_HOSTNAME__/$(escape_sed "${HARBOR_HOSTNAME}")/g" \
  -e "s/__HARBOR_EXTERNAL_URL__/$(escape_sed "${HARBOR_EXTERNAL_URL}")/g" \
  -e "s/__HARBOR_HTTP_PORT__/$(escape_sed "${HARBOR_HTTP_PORT}")/g" \
  -e "s/__HARBOR_ADMIN_PASSWORD__/$(escape_sed "${HARBOR_ADMIN_PASSWORD}")/g" \
  -e "s/__HARBOR_DB_PASSWORD__/$(escape_sed "${HARBOR_DB_PASSWORD}")/g" \
  -e "s/__HARBOR_DATA_VOLUME__/$(escape_sed "${HARBOR_DATA_VOLUME}")/g" \
  -e "s/__HARBOR_LOG_LOCATION__/$(escape_sed "${HARBOR_LOG_LOCATION}")/g" \
  -e "s/__HARBOR_HTTP_PROXY__/$(escape_sed "${HARBOR_HTTP_PROXY}")/g" \
  -e "s/__HARBOR_HTTPS_PROXY__/$(escape_sed "${HARBOR_HTTPS_PROXY}")/g" \
  -e "s/__HARBOR_NO_PROXY__/$(escape_sed "${HARBOR_NO_PROXY}")/g" \
  -e "s/__HARBOR_TRIVY_SKIP_UPDATE__/$(escape_sed "${HARBOR_TRIVY_SKIP_UPDATE}")/g" \
  "${TEMPLATE}" > "${INSTALLER_OUTPUT}"

# ===== Ensure directories =====
mkdir -p "${HARBOR_DATA_VOLUME}" "${HARBOR_LOG_LOCATION}" || true

# ===== Run prepare =====
echo "[INFO] Running Harbor prepare..."
cd "${SCRIPT_DIR}/installer/harbor"
./prepare ${HARBOR_PREPARE_FLAGS:-}

# ===== FIX PERMISSION (CRITICAL) =====
echo "[INFO] Fixing ownership after prepare..."

docker run --rm \
  -v "${SCRIPT_DIR}/installer/harbor:/work" \
  alpine:3.20 \
  sh -lc "
    chown -R ${HOST_UID}:${HOST_GID} /work || true
    chmod -R u+rwX /work
  "

# ===== Relax permission for compose =====
docker run --rm \
  -u "${HOST_UID}:${HOST_GID}" \
  -v "${SCRIPT_DIR}/installer/harbor:/work" \
  alpine:3.20 \
  sh -lc 'chmod -R a+rX /work/common /work/docker-compose.yml /work/harbor.yml || true'

# ===== Patch docker-compose =====
echo "[INFO] Patching docker-compose..."

export HARBOR_HTTP_PORT HARBOR_PROXY_ALIAS HARBOR_PROXY_NETWORK

perl -0pi -e '
  my $port = $ENV{HARBOR_HTTP_PORT};
  my $alias = $ENV{HARBOR_PROXY_ALIAS};
  my $network = $ENV{HARBOR_PROXY_NETWORK};

  s/container_name: nginx/container_name: $alias/;

  s/\n    networks:\n      - harbor\n    ports:\n      - \Q$port:$port\E\n/
    \n    networks:\n      harbor:\n      $network:\n        aliases:\n          - $alias\n/s;

  s/\nnetworks:\n  harbor:\n    external: false\n/
    \nnetworks:\n  harbor:\n    external: false\n  $network:\n    external: true\n/s;
' "${GENERATED_COMPOSE}"

echo "[SUCCESS] Harbor prepared successfully!"
echo "Path: ${SCRIPT_DIR}/installer/harbor"
