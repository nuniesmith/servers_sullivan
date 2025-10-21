#!/bin/bash
#
# SULLIVAN Backup Script
# Automated backup of critical data: Media server databases, *arr app configs
#
# Usage: ./backup.sh [--full] [--config-only]
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/mnt/backup/sullivan}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE_DIR/$TIMESTAMP"

# Backup components
BACKUP_EMBY="${BACKUP_EMBY:-true}"
BACKUP_JELLYFIN="${BACKUP_JELLYFIN:-true}"
BACKUP_ARR_APPS="${BACKUP_ARR_APPS:-true}"
BACKUP_CONFIGS="${BACKUP_CONFIGS:-true}"
BACKUP_DOCKER_VOLUMES="${BACKUP_DOCKER_VOLUMES:-false}"

# Logging
LOG_FILE="$BACKUP_BASE_DIR/backup.log"
ERROR_LOG="$BACKUP_BASE_DIR/backup_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$ERROR_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! command -v docker &> /dev/null; then
        error "This script requires root privileges or docker access"
        exit 1
    fi
    
    # Check if backup directory exists
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        warn "Backup directory doesn't exist. Creating: $BACKUP_BASE_DIR"
        mkdir -p "$BACKUP_BASE_DIR"
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG "$BACKUP_BASE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 50 ]]; then
        warn "Low disk space: ${AVAILABLE_SPACE}GB available"
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        error "Docker is not running"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

backup_emby_data() {
    log "Backing up Emby data and configuration..."
    
    local backup_file="$BACKUP_DIR/emby_data_$TIMESTAMP.tar.gz"
    
    # Backup Emby config (database, users, metadata)
    # Exclude large cache and transcoding directories
    if [[ -d "$PROJECT_DIR/services/emby/config" ]]; then
        tar czf "$backup_file" \
            -C "$PROJECT_DIR/services/emby" \
            --exclude='config/cache' \
            --exclude='config/transcoding-temp' \
            --exclude='config/logs' \
            config/
        
        if [[ $? -eq 0 ]]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log "✓ Emby data backed up: $size"
        else
            error "Failed to backup Emby data"
            return 1
        fi
    else
        warn "Emby config directory not found"
    fi
}

backup_jellyfin_data() {
    log "Backing up Jellyfin data and configuration..."
    
    local backup_file="$BACKUP_DIR/jellyfin_data_$TIMESTAMP.tar.gz"
    
    # Backup Jellyfin config (database, users, metadata)
    # Exclude large cache and transcoding directories
    if [[ -d "$PROJECT_DIR/services/jellyfin/config" ]]; then
        tar czf "$backup_file" \
            -C "$PROJECT_DIR/services/jellyfin" \
            --exclude='config/cache' \
            --exclude='config/transcodes' \
            --exclude='config/log' \
            config/
        
        if [[ $? -eq 0 ]]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log "✓ Jellyfin data backed up: $size"
        else
            error "Failed to backup Jellyfin data"
            return 1
        fi
    else
        warn "Jellyfin config directory not found"
    fi
}

backup_arr_app() {
    local app_name="$1"
    log "Backing up $app_name configuration..."
    
    local backup_file="$BACKUP_DIR/${app_name}_config_$TIMESTAMP.tar.gz"
    
    if [[ -d "$PROJECT_DIR/services/$app_name/config" ]]; then
        tar czf "$backup_file" \
            -C "$PROJECT_DIR/services/$app_name" \
            --exclude='config/logs' \
            --exclude='config/Backups' \
            config/
        
        if [[ $? -eq 0 ]]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log "✓ $app_name backed up: $size"
        else
            error "Failed to backup $app_name"
            return 1
        fi
    else
        warn "$app_name config directory not found"
    fi
}

backup_arr_apps() {
    log "Backing up *arr applications..."
    
    # Backup all *arr apps
    local arr_apps=("sonarr" "radarr" "lidarr" "prowlarr" "bazarr" "readarr")
    
    for app in "${arr_apps[@]}"; do
        if [[ -d "$PROJECT_DIR/services/$app" ]]; then
            backup_arr_app "$app"
        else
            info "$app not found, skipping"
        fi
    done
}

backup_qbittorrent() {
    log "Backing up qBittorrent configuration..."
    
    local backup_file="$BACKUP_DIR/qbittorrent_config_$TIMESTAMP.tar.gz"
    
    if [[ -d "$PROJECT_DIR/services/qbittorrent/config" ]]; then
        tar czf "$backup_file" \
            -C "$PROJECT_DIR/services/qbittorrent" \
            --exclude='config/logs' \
            config/
        
        if [[ $? -eq 0 ]]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log "✓ qBittorrent backed up: $size"
        else
            error "Failed to backup qBittorrent"
            return 1
        fi
    else
        warn "qBittorrent config directory not found"
    fi
}

backup_docker_configs() {
    log "Backing up Docker configs and compose files..."
    
    local backup_file="$BACKUP_DIR/docker_configs_$TIMESTAMP.tar.gz"
    
    # Backup all service configs and docker-compose files
    tar czf "$backup_file" \
        -C "$PROJECT_DIR" \
        docker-compose.yml \
        .env \
        services/nginx/conf.d/ \
        services/nginx/nginx.conf \
        --exclude='services/*/config/*.log*' \
        --exclude='services/*/config/cache' \
        --exclude='services/*/config/logs'
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Docker configs backed up: $size"
    else
        error "Failed to backup Docker configs"
        return 1
    fi
}

backup_docker_volumes() {
    log "Backing up critical Docker volumes..."
    
    # List of critical named volumes to backup
    local volumes=(
        "sullivan_emby_data"
        "sullivan_jellyfin_data"
        "sullivan_sonarr_data"
        "sullivan_radarr_data"
        "sullivan_lidarr_data"
        "sullivan_prowlarr_data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume inspect "$volume" &> /dev/null; then
            info "Backing up volume: $volume"
            docker run --rm \
                -v "$volume":/volume \
                -v "$BACKUP_DIR":/backup \
                alpine tar czf "/backup/${volume}_$TIMESTAMP.tar.gz" -C /volume ./
        else
            warn "Volume not found: $volume"
        fi
    done
    
    log "✓ Docker volumes backed up"
}

backup_scripts() {
    log "Backing up scripts directory..."
    
    local backup_file="$BACKUP_DIR/scripts_$TIMESTAMP.tar.gz"
    
    tar czf "$backup_file" -C "$PROJECT_DIR" scripts/
    
    if [[ $? -eq 0 ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log "✓ Scripts backed up: $size"
    else
        error "Failed to backup scripts"
        return 1
    fi
}

create_backup_manifest() {
    log "Creating backup manifest..."
    
    local manifest_file="$BACKUP_DIR/MANIFEST.txt"
    
    cat > "$manifest_file" << EOF
SULLIVAN Backup Manifest
========================
Backup Date: $(date)
Backup Directory: $BACKUP_DIR
Server: SULLIVAN
Hostname: $(hostname)

Components Backed Up:
- Emby Configuration: $BACKUP_EMBY
- Jellyfin Configuration: $BACKUP_JELLYFIN
- *arr Applications: $BACKUP_ARR_APPS
- Docker Configs: $BACKUP_CONFIGS
- Docker Volumes: $BACKUP_DOCKER_VOLUMES

Files in this backup:
EOF
    
    # List all files with sizes
    du -h "$BACKUP_DIR"/* | sort -h >> "$manifest_file"
    
    # Total backup size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo "" >> "$manifest_file"
    echo "Total Backup Size: $total_size" >> "$manifest_file"
    
    log "✓ Backup manifest created"
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local deleted_count=0
    
    # Find and delete old backup directories
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" -mtime +"$RETENTION_DAYS" | while read dir; do
        info "Deleting old backup: $(basename "$dir")"
        rm -rf "$dir"
        ((deleted_count++))
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        log "✓ Deleted $deleted_count old backup(s)"
    else
        log "✓ No old backups to delete"
    fi
}

send_notification() {
    local status="$1"
    local message="$2"
    
    # TODO: Implement notification (email, webhook, etc.)
    # Example: curl -X POST webhook_url -d "message=$message"
    
    info "Notification: [$status] $message"
}

# ============================================================================
# Main Backup Process
# ============================================================================

main() {
    local start_time=$(date +%s)
    
    echo ""
    echo "========================================"
    echo "   SULLIVAN Backup Script"
    echo "========================================"
    echo ""
    
    # Parse arguments
    FULL_BACKUP=false
    CONFIG_ONLY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                FULL_BACKUP=true
                BACKUP_DOCKER_VOLUMES=true
                shift
                ;;
            --config-only)
                CONFIG_ONLY=true
                BACKUP_EMBY=false
                BACKUP_JELLYFIN=false
                BACKUP_ARR_APPS=false
                BACKUP_DOCKER_VOLUMES=false
                shift
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Start backup
    log "Starting backup process..."
    log "Backup directory: $BACKUP_DIR"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Run checks
    check_prerequisites
    
    # Backup components
    if [[ "$BACKUP_EMBY" == "true" ]]; then
        backup_emby_data
    fi
    
    if [[ "$BACKUP_JELLYFIN" == "true" ]]; then
        backup_jellyfin_data
    fi
    
    if [[ "$BACKUP_ARR_APPS" == "true" ]]; then
        backup_arr_apps
        backup_qbittorrent
    fi
    
    if [[ "$BACKUP_CONFIGS" == "true" ]]; then
        backup_docker_configs
        backup_scripts
    fi
    
    if [[ "$BACKUP_DOCKER_VOLUMES" == "true" ]]; then
        backup_docker_volumes
    fi
    
    # Create manifest
    create_backup_manifest
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    # Get total size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    
    echo ""
    log "========================================"
    log "Backup completed successfully!"
    log "Duration: ${minutes}m ${seconds}s"
    log "Total size: $total_size"
    log "Location: $BACKUP_DIR"
    log "========================================"
    echo ""
    
    send_notification "SUCCESS" "SULLIVAN backup completed: $total_size in ${minutes}m ${seconds}s"
}

# ============================================================================
# Execute
# ============================================================================

main "$@"
