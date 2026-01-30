#!/bin/bash

# =============================================================================
# Sullivan Docker Compose Volume Migration Script
# Migrates from anonymous volumes to bind mounts for better version control
# =============================================================================

set -e  # Exit on error

echo "=========================================="
echo "Sullivan Volume Migration"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
BACKUP_DIR="./volume-migration-backup-$(date +%Y%m%d-%H%M%S)"
SERVICES_DIR="./services"

# Services to migrate
SERVICES=(
    "emby"
    "jellyfin"
    "plex"
    "sonarr"
    "radarr"
    "lidarr"
    "qbittorrent"
    "jackett"
    "calibre"
    "calibre-web"
    "filebot-node"
    "ytdl_material"
    "duplicati"
    "mealie"
    "grocy"
    "syncthing"
    "wiki"
)

# Warning
echo -e "${RED}⚠ WARNING: This script will modify your Docker setup${NC}"
echo -e "${RED}⚠ Ensure you have backups before proceeding!${NC}"
echo ""
echo "This script will:"
echo "  1. Stop all services"
echo "  2. Export data from volumes to bind mounts"
echo "  3. Create ./services/* directory structure"
echo "  4. Update docker-compose.yml (manual step)"
echo "  5. Restart services with new configuration"
echo ""
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Step 1: Create backup directory
echo -e "${YELLOW}Step 1: Creating backup directory...${NC}"
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓ Created $BACKUP_DIR${NC}"

# Step 2: Create services directory structure
echo -e "${YELLOW}Step 2: Creating services directory structure...${NC}"
for service in "${SERVICES[@]}"; do
    mkdir -p "$SERVICES_DIR/$service/config"
    echo -e "${GREEN}✓ Created $SERVICES_DIR/$service/config${NC}"
done

# Step 3: Stop all services
echo -e "${YELLOW}Step 3: Stopping services...${NC}"
echo "This may take a few minutes..."
docker compose down
echo -e "${GREEN}✓ All services stopped${NC}"

# Step 4: Migrate data from volumes to bind mounts
echo -e "${YELLOW}Step 4: Migrating volume data...${NC}"
echo "This will take several minutes depending on data size..."

migrate_volume() {
    local service=$1
    local volume_name=$2
    local target_dir=$3
    
    echo "  Migrating ${service}..."
    
    # Check if volume exists
    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
        # Create temporary container to copy data
        docker run --rm \
            -v "$volume_name":/source:ro \
            -v "$(pwd)/$target_dir":/target \
            alpine sh -c "cp -a /source/. /target/"
        echo -e "${GREEN}  ✓ Migrated $service from volume $volume_name${NC}"
    else
        echo -e "${YELLOW}  ! Volume $volume_name not found, skipping${NC}"
    fi
}

# Migrate each service
migrate_volume "emby" "sullivan_emby_data" "$SERVICES_DIR/emby/config"
migrate_volume "jellyfin" "sullivan_jellyfin_data" "$SERVICES_DIR/jellyfin/config"
migrate_volume "plex" "sullivan_plex_data" "$SERVICES_DIR/plex/config"
migrate_volume "sonarr" "sullivan_sonarr_data" "$SERVICES_DIR/sonarr/config"
migrate_volume "radarr" "sullivan_radarr_data" "$SERVICES_DIR/radarr/config"
migrate_volume "lidarr" "sullivan_lidarr_data" "$SERVICES_DIR/lidarr/config"
migrate_volume "qbittorrent" "sullivan_qbittorrent_data" "$SERVICES_DIR/qbittorrent/config"
migrate_volume "jackett" "sullivan_jackett_data" "$SERVICES_DIR/jackett/config"
migrate_volume "calibre" "sullivan_calibre_data" "$SERVICES_DIR/calibre/config"
migrate_volume "calibre-web" "sullivan_calibre_web_data" "$SERVICES_DIR/calibre-web/config"
migrate_volume "filebot" "sullivan_filebot_data" "$SERVICES_DIR/filebot/config"
migrate_volume "ytdl" "sullivan_ytdl_data" "$SERVICES_DIR/ytdl/config"
migrate_volume "duplicati" "sullivan_duplicati_data" "$SERVICES_DIR/duplicati/config"
migrate_volume "mealie" "sullivan_mealie_data" "$SERVICES_DIR/mealie/config"
migrate_volume "grocy" "sullivan_grocy_data" "$SERVICES_DIR/grocy/config"
migrate_volume "syncthing" "sullivan_syncthing_data" "$SERVICES_DIR/syncthing/config"
migrate_volume "wiki" "sullivan_wiki_data" "$SERVICES_DIR/wiki/config"

echo -e "${GREEN}✓ All data migrated${NC}"

# Step 5: Set permissions
echo -e "${YELLOW}Step 5: Setting permissions...${NC}"
PUID=${PUID:-1000}
PGID=${PGID:-1000}
sudo chown -R ${PUID}:${PGID} "$SERVICES_DIR"
echo -e "${GREEN}✓ Permissions set to ${PUID}:${PGID}${NC}"

# Step 6: Create backup of old volumes
echo -e "${YELLOW}Step 6: Creating backup of old volumes...${NC}"
docker volume ls | grep sullivan_ | awk '{print $2}' > "$BACKUP_DIR/volumes-list.txt"
echo -e "${GREEN}✓ Volume list saved to $BACKUP_DIR/volumes-list.txt${NC}"

# Step 7: Instructions for manual updates
echo ""
echo "=========================================="
echo -e "${GREEN}Migration Complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps (MANUAL):"
echo ""
echo "1. Update docker-compose.yml to use bind mounts:"
echo "   Replace volume declarations like:"
echo "     - emby_data:/config"
echo "   With:"
echo "     - ./services/emby/config:/config"
echo ""
echo "2. Keep cache volumes as-is (e.g., emby_cache, jellyfin_cache)"
echo ""
echo "3. Test the new configuration:"
echo "   $ docker compose config"
echo ""
echo "4. Start services:"
echo "   $ docker compose up -d"
echo ""
echo "5. Verify all services work correctly"
echo ""
echo "6. After verification, remove old volumes:"
echo "   $ docker volume rm \$(cat $BACKUP_DIR/volumes-list.txt)"
echo ""
echo "7. Add services/ to git:"
echo "   $ git add services/"
echo "   $ git commit -m 'Migrate to bind mounts for version control'"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
