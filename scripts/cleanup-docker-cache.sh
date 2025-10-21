#!/bin/bash

# =============================================================================
# SULLIVAN Docker Cache Cleanup Script
# Safely removes Docker cache volumes while preserving configs
# =============================================================================

set -e  # Exit on error

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/docker-cleanup-sullivan.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Function to log messages
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log "${BLUE}=========================================="
log "SULLIVAN Docker Cleanup - ${DATE}"
log "==========================================${NC}"

# Get initial disk usage
DISK_BEFORE=$(df -h / | awk 'NR==2 {print $4}')
log "${YELLOW}Disk space available before cleanup: ${DISK_BEFORE}${NC}"

# Step 1: Remove stopped containers
log "\n${YELLOW}Step 1: Removing stopped containers...${NC}"
STOPPED_CONTAINERS=$(docker container prune -f 2>&1 | grep 'Total reclaimed space' || echo "None removed")
log "${GREEN}✓ ${STOPPED_CONTAINERS}${NC}"

# Step 2: Remove dangling images
log "\n${YELLOW}Step 2: Removing dangling images...${NC}"
DANGLING_IMAGES=$(docker image prune -f 2>&1 | grep 'Total reclaimed space' || echo "None removed")
log "${GREEN}✓ ${DANGLING_IMAGES}${NC}"

# Step 3: Remove unused images (older than 30 days)
log "\n${YELLOW}Step 3: Removing unused images (older than 30 days)...${NC}"
UNUSED_IMAGES=$(docker image prune -a -f --filter "until=720h" 2>&1 | grep 'Total reclaimed space' || echo "None removed")
log "${GREEN}✓ ${UNUSED_IMAGES}${NC}"

# Step 4: Remove build cache
log "\n${YELLOW}Step 4: Removing build cache...${NC}"
BUILD_CACHE=$(docker builder prune -f 2>&1 | grep 'Total' || echo "None removed")
log "${GREEN}✓ ${BUILD_CACHE}${NC}"

# Step 5: Remove unused networks
log "\n${YELLOW}Step 5: Removing unused networks...${NC}"
UNUSED_NETWORKS=$(docker network prune -f 2>&1 | grep 'Deleted Networks' || echo "None removed")
log "${GREEN}✓ ${UNUSED_NETWORKS}${NC}"

# Step 6: Clean up cache volumes (SAFE after migration to bind mounts)
log "\n${YELLOW}Step 6: Listing cache volumes...${NC}"

# Protected volumes (databases and important data - DO NOT REMOVE!)
PROTECTED_VOLUMES=(
    "sullivan_ytdl_mongodb"
    "sullivan_wiki_postgres"
)

# Cache volumes (SAFE to remove - will be regenerated)
CACHE_VOLUMES=(
    "sullivan_emby_cache"
    "sullivan_jellyfin_cache"
    "sullivan_plex_cache"
)

log "\n${YELLOW}Cache volumes that can be safely removed:${NC}"
for vol in "${CACHE_VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        SIZE=$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null || echo "")
        log "  - ${vol}"
    fi
done

# Remove cache volumes
log "\n${YELLOW}Removing cache volumes...${NC}"
for vol in "${CACHE_VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        docker volume rm "$vol" 2>/dev/null && log "${GREEN}✓ Removed ${vol}${NC}" || log "${YELLOW}! ${vol} in use, skipping${NC}"
    fi
done

# Remove unnamed/unused volumes
log "\n${YELLOW}Removing unused/unnamed volumes...${NC}"
VOLUME_CLEANUP=$(docker volume prune -f 2>&1 | grep 'Total reclaimed space' || echo "None removed")
log "${GREEN}✓ ${VOLUME_CLEANUP}${NC}"

# Step 7: Clean up /tmp directory and transcode files
log "\n${YELLOW}Step 7: Cleaning temporary files...${NC}"
sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
log "${GREEN}✓ Old temporary files removed${NC}"

# Step 8: Clean qBittorrent .fastresume files (if needed)
log "\n${YELLOW}Step 8: Checking qBittorrent fastresume files...${NC}"
if [ -d "./services/qbittorrent/config" ]; then
    FASTRESUME_COUNT=$(find ./services/qbittorrent/config -name "*.fastresume" 2>/dev/null | wc -l)
    log "${YELLOW}Found ${FASTRESUME_COUNT} fastresume files (not removing)${NC}"
fi

# Step 9: Summary
log "\n${BLUE}=========================================="
log "Cleanup Summary"
log "==========================================${NC}"

DISK_AFTER=$(df -h / | awk 'NR==2 {print $4}')
log "${GREEN}Disk space available after cleanup: ${DISK_AFTER}${NC}"
log "${GREEN}Previous: ${DISK_BEFORE} → Current: ${DISK_AFTER}${NC}"

# Docker system df
log "\n${YELLOW}Current Docker disk usage:${NC}"
docker system df | tee -a "$LOG_FILE"

log "\n${BLUE}=========================================="
log "Protected Volumes (NOT removed):"
log "==========================================${NC}"
for vol in "${PROTECTED_VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        log "${GREEN}✓ ${vol}${NC}"
    fi
done

log "\n${GREEN}Cleanup completed successfully!${NC}"
log "Log saved to: ${LOG_FILE}"

# Note about services restart
log "\n${YELLOW}NOTE: Services may need restart to recreate cache volumes:${NC}"
log "  docker compose restart emby jellyfin plex"

log "\n${BLUE}==========================================\n${NC}"
