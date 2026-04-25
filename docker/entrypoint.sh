#!/bin/bash
set -e

SALT_ROLE="${SALT_ROLE:-master}"

echo "[entrypoint] Starting salt-${SALT_ROLE}..."

case "${SALT_ROLE}" in
  master)
    salt-master -l info &
    MASTER_PID=$!
    echo "[entrypoint] salt-master started (pid $MASTER_PID)"
    sleep 5
    echo "[entrypoint] syncing custom modules..."
    salt-run saltutil.sync_all
    salt-api -l info &
    API_PID=$!
    echo "[entrypoint] salt-api started (pid $API_PID)"
    wait $MASTER_PID
    ;;
  minion)
    exec salt-minion -l info
    ;;
  api)
    exec salt-api -l info
    ;;
  *)
    echo "[entrypoint] Unknown SALT_ROLE: ${SALT_ROLE}"
    exit 1
    ;;
esac
