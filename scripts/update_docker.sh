#!/bin/bash

# This script updates all Docker services by pulling the latest images,
# stopping all services, starting them again, and cleaning up unused resources.

set -eo pipefail

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

if ! docker compose version &>/dev/null; then
  log "ERROR: docker compose is not installed or not in PATH."
  exit 1
fi

# The CI/CD pipeline deploys by running `docker compose down` + `up` over SSH in
# this same directory, as this same user. Two concurrent compose runs on one
# project fight over containers and networks - the second one fails with
# "container name is already in use". Serialise on a shared lock so a manual
# update waits for an in-flight deploy (and vice versa) instead of colliding.
LOCK_FILE="${HOME}/.sullivan-compose.lock"
LOCK_WAIT=900

if command -v flock &>/dev/null; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "INFO: Another compose operation holds $LOCK_FILE (CI/CD deploy or a second update run)."
    log "INFO: Waiting up to ${LOCK_WAIT}s for it to finish..."
    if ! flock -w "$LOCK_WAIT" 9; then
      log "ERROR: Timed out after ${LOCK_WAIT}s waiting for $LOCK_FILE."
      log "ERROR: Check for a stuck deploy before retrying."
      exit 1
    fi
  fi
else
  log "WARN: flock not found - running without a lock. A concurrent CI/CD deploy may cause container name conflicts."
fi

log "INFO: Starting Docker update process..."

log "INFO: Pulling all images..."
# --ignore-pull-failures stops a single unresolvable image from interrupting
# the pulls of every other service; failures are reported below instead.
docker compose pull --ignore-pull-failures ||
  log "WARN: One or more images failed to pull."

log "INFO: Verifying images are available locally..."
missing=()
while IFS= read -r image; do
  [ -n "$image" ] || continue
  docker image inspect "$image" &>/dev/null || missing+=("$image")
done < <(docker compose config --images)

if [ "${#missing[@]}" -gt 0 ]; then
  log "ERROR: ${#missing[@]} image(s) could not be pulled and are not present locally:"
  for image in "${missing[@]}"; do
    log "ERROR:   - $image"
  done
  log "ERROR: Aborting before stopping services - fix these references in docker-compose.yml first."
  exit 1
fi

log "INFO: Stopping all services..."
docker compose down

log "INFO: Starting all services..."
docker compose up -d --remove-orphans

log "INFO: Cleaning up unused Docker resources..."
docker system prune -f

log "INFO: Docker update process completed successfully."
