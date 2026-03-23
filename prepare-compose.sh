#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/.env"

ARCHIVE="harbor-online-installer-${HARBOR_VERSION}.tgz"
URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${ARCHIVE}"
DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"
INSTALLER_DIR="${SCRIPT_DIR}/installer"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE}"
TEMPLATE="${SCRIPT_DIR}/harbor.yml.template"
INSTALLER_OUTPUT="${INSTALLER_DIR}/harbor/harbor.yml"
GENERATED_COMPOSE="${INSTALLER_DIR}/harbor/docker-compose.yml"

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

mkdir -p "${DOWNLOAD_DIR}" "${INSTALLER_DIR}"

if ! docker network inspect "${HARBOR_PROXY_NETWORK}" >/dev/null 2>&1; then
  echo "Docker network ${HARBOR_PROXY_NETWORK} was not found." >&2
  echo "Create it first or change HARBOR_PROXY_NETWORK in ./.env." >&2
  exit 1
fi

if [ ! -f "${ARCHIVE_PATH}" ]; then
  echo "Downloading ${ARCHIVE} ..."
  curl -fL "${URL}" -o "${ARCHIVE_PATH}"
else
  echo "Using cached ${ARCHIVE_PATH}"
fi

if [ -e "${INSTALLER_DIR}/harbor" ]; then
  docker run --rm \
    -v "${INSTALLER_DIR}:/work" \
    alpine:3.20 \
    sh -lc 'rm -rf /work/harbor'
fi

tar -xzf "${ARCHIVE_PATH}" -C "${INSTALLER_DIR}"

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

if ! mkdir -p "${HARBOR_DATA_VOLUME}" "${HARBOR_LOG_LOCATION}" 2>/dev/null; then
  echo "Warning: could not create ${HARBOR_DATA_VOLUME} or ${HARBOR_LOG_LOCATION} as the current user." >&2
  echo "Create them manually (for example with sudo) before running Harbor in a real deployment." >&2
fi

cd "${SCRIPT_DIR}/installer/harbor"
# shellcheck disable=SC2086
./prepare ${HARBOR_PREPARE_FLAGS}

# Harbor's prepare step writes several generated config files as root or uid 10000
# with restrictive modes. Relax them so the current user can inspect and run
# `docker compose` against the generated stack.
docker run --rm \
  -v "${SCRIPT_DIR}/installer/harbor:/work" \
  alpine:3.20 \
  sh -lc 'chmod -R a+rX /work/common /work/docker-compose.yml /work/harbor.yml'

export HARBOR_HTTP_PORT HARBOR_PROXY_ALIAS HARBOR_PROXY_NETWORK
perl -0pi -e '
  my $port = $ENV{HARBOR_HTTP_PORT};
  my $alias = $ENV{HARBOR_PROXY_ALIAS};
  my $network = $ENV{HARBOR_PROXY_NETWORK};

  s/container_name: nginx/container_name: $alias/;
  s/\n    networks:\n      - harbor\n    ports:\n      - \Q$port:$port\E\n/\n    networks:\n      harbor:\n      $network:\n        aliases:\n          - $alias\n/s;
  s/\nnetworks:\n  harbor:\n    external: false\n/\nnetworks:\n  harbor:\n    external: false\n  $network:\n    external: true\n/s;
' "${GENERATED_COMPOSE}"

echo "Prepared official Harbor docker-compose stack in ${SCRIPT_DIR}/installer/harbor"
