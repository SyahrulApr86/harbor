#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

"${SCRIPT_DIR}/prepare-compose.sh"

cd "${SCRIPT_DIR}/installer/harbor"
docker compose up -d
