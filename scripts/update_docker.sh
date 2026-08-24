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
docker compose up -d

log "INFO: Cleaning up unused Docker resources..."
docker system prune -f

log "INFO: Docker update process completed successfully."
