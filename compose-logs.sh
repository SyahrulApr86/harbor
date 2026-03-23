#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
COMPOSE_DIR="${SCRIPT_DIR}/installer/harbor"

if [ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]; then
  echo "No generated docker-compose.yml found at ${COMPOSE_DIR}. Run ./prepare-compose.sh first." >&2
  exit 1
fi

cd "${COMPOSE_DIR}"
docker compose logs --tail=200 "$@"
