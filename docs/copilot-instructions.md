# GitHub Copilot Instructions - SULLIVAN Server

## Server Overview

**SULLIVAN** is the high-performance media processing and AI workload server in the 7gram.xyz homelab infrastructure.

### Primary Functions
- **Media Streaming**: Emby, Jellyfin, Plex
- **Media Management**: Sonarr, Radarr, Lidarr, Prowlarr
- **Downloads**: qBittorrent, yt-dlp
- **AI/LLM**: Ollama for local model inference
- **Wiki**: Wiki.js with PostgreSQL

### Server Specifications
- **Role**: Heavy workloads, media processing, AI inference
- **Domain**: 7gram.xyz (subdomains)
- **Network**: Tailscale VPN overlay
- **Storage**: /mnt/media for media files
- **Authentication**: Authentik SSO on FREDDY server

## Architecture Principles

### Docker Compose Strategy
- **Bind mounts** for configs (git-tracked in ./services/*/config)
- **Named volumes** for databases (protected from pruning)
- **Named volumes** for caches (pruneable - emby_cache, jellyfin_cache, plex_cache)
- **Shared media**: /mnt/media mounted read-only in most services
- **Networks**: frontend (nginx), backend (services), database (postgres/mongodb)

### Authentication Integration
- **SSO Provider**: Authentik on FREDDY (auth.7gram.xyz)
- **Auth Methods**: 
  - LDAP for media servers (Emby, Jellyfin)
  - Forward Auth for *arr apps via Nginx
  - OIDC for Wiki.js, Portainer
- **LDAP Endpoint**: freddy:636 (LDAPS)

### Volume Management
```yaml
# Config (git-tracked bind mounts)
./services/<service>/config:/config

# Cache (pruneable named volumes - safe to remove)
<service>_cache:/cache

# Database (protected named volumes - never remove)
<service>_postgres:/var/lib/postgresql/data
<service>_mongodb:/data/db

# Media (read-only shared storage)
/mnt/media:/media:ro
```

## Code Conventions

### Docker Compose Files
- Use `sullivan_` prefix for named volumes
- Use `sullivan_` prefix for networks
- Mount `/mnt/media` read-only unless service modifies files
- Always specify restart policies (usually `unless-stopped`)
- Group services by function (streaming, downloads, management)

### Environment Variables
- Store secrets in `.env` (git-ignored)
- Provide `.env.example` with dummy values
- Use `${VARIABLE_NAME}` syntax in docker-compose.yml
- Document all required variables (especially API keys)

### Nginx Configuration
- One file per subdomain in `services/nginx/conf.d/`
- Forward auth for *arr apps: include authentik snippets
- SSL certs in `/opt/ssl/7gram.xyz/`
- Use proxy_pass to Docker service names on backend network

### Scripts
- All scripts in `./scripts/` directory
- Use bash with error handling (`set -euo pipefail`)
- Include usage/help text
- Log to `/var/log/` when running via systemd
- Make executable with `chmod +x`

## Service-Specific Guidelines

### Media Servers

#### Emby
- **Auth**: LDAP to Authentik on FREDDY
- **Transcoding**: Hardware acceleration if available
- **Cache**: Pruneable volume (emby_cache)
- **Media**: /mnt/media:ro

#### Jellyfin
- **Auth**: LDAP to Authentik on FREDDY
- **Transcoding**: /dev/dri for hardware acceleration
- **Cache**: Pruneable volume (jellyfin_cache)
- **Media**: /mnt/media:ro

#### Plex
- **Auth**: LDAP to Authentik on FREDDY (via LDAP plugin)
- **Transcoding**: Plex transcoder built-in
- **Cache**: Pruneable volume (plex_cache)
- **Media**: /mnt/media:ro

### Download Stack

#### qBittorrent
- **Web UI Port**: 8080
- **Downloads**: /mnt/media/downloads (read-write)
- **VPN**: Consider VPN container sidecar
- **Auth**: Forward Auth via Nginx

#### yt-dlp
- **Database**: MongoDB for metadata
- **Downloads**: /mnt/media/youtube
- **Scheduling**: Cron or systemd timer for updates
- **Config**: Bind mount for archive.txt and config

### Media Management (*arr apps)

#### Sonarr/Radarr/Lidarr
- **Auth**: Forward Auth via Nginx (Authentik)
- **Media**: /mnt/media with read-write
- **Database**: SQLite in config bind mount
- **API Keys**: Store in .env

#### Prowlarr
- **Purpose**: Indexer management for *arr apps
- **Auth**: Forward Auth via Nginx
- **Config**: Bind mount at ./services/prowlarr/config

### AI/ML

#### Ollama
- **Models**: Store in ./services/ollama/models
- **GPU**: Pass through NVIDIA/AMD GPU if available
- **API**: Port 11434 (internal only)
- **Memory**: Allocate sufficient RAM for models

### Wiki/Documentation

#### Wiki.js
- **Database**: PostgreSQL (protected volume)
- **Auth**: OIDC with Authentik
- **Storage**: ./services/wiki/data for uploads
- **Backup**: Regular postgres dumps

## Common Tasks

### Adding a New Media Service
1. Create `./services/<service>/` directory
2. Add to docker-compose.yml:
   ```yaml
   <service>:
     image: <image>
     container_name: sullivan_<service>
     volumes:
       - ./services/<service>/config:/config
       - <service>_cache:/cache
       - /mnt/media:/media:ro
     networks:
       - backend
     restart: unless-stopped
   ```
3. Add nginx config with forward auth
4. Add DNS entry for `<service>.7gram.xyz`
5. Configure service to use Authentik

### Implementing LDAP Authentication
1. In service UI, configure LDAP:
   - **Server**: freddy (Docker hostname) or Tailscale IP
   - **Port**: 636 (LDAPS)
   - **Base DN**: dc=7gram,dc=xyz
   - **Bind DN**: cn=ldapservice,ou=users,dc=7gram,dc=xyz
   - **Bind Password**: From Authentik LDAP provider
2. Test connection in service settings
3. Map LDAP attributes (uid, mail, cn)
4. Enable LDAP authentication

### Implementing Forward Auth (Nginx)
1. Add to nginx config:
   ```nginx
   include /etc/nginx/conf.d/authentik-authrequest.conf;
   include /etc/nginx/conf.d/authentik-location.conf;
   error_page 401 = @authentik_proxy_signin;
   
   location / {
       proxy_pass http://<service>:port;
       proxy_set_header X-Authentik-Username $authentik_user;
       proxy_set_header X-Authentik-Email $authentik_email;
   }
   ```
2. Reload nginx: `docker compose exec nginx nginx -s reload`
3. Test authentication flow

### Managing Media Files
```bash
# Find large files
find /mnt/media -type f -size +10G

# Fix permissions
sudo chown -R $USER:$USER /mnt/media
sudo chmod -R 755 /mnt/media

# Check disk usage
du -sh /mnt/media/*

# Find duplicates (after setting up Czkawka)
docker compose run --rm czkawka /media
```

### Viewing Logs
```bash
# All services
docker compose logs -f

# Media server logs
docker compose logs -f emby jellyfin plex

# Download stack logs
docker compose logs -f qbittorrent sonarr radarr

# Last 100 lines with timestamps
docker compose logs --tail=100 --timestamps <service>
```

## Maintenance

### Weekly Automated Cleanup
- **Schedule**: Sundays at 3:00 AM (1 hour after FREDDY)
- **Script**: `./scripts/cleanup-docker-cache.sh`
- **Protected volumes**: ytdl_mongodb, wiki_postgres
- **Removed volumes**: emby_cache, jellyfin_cache, plex_cache
- **Systemd**: `docker-cleanup.timer`

### Manual Cleanup
```bash
# Safe cleanup (protects databases)
sudo ./scripts/cleanup-docker-cache.sh

# Remove transcoding cache manually
docker compose down emby jellyfin plex
docker volume rm sullivan_emby_cache sullivan_jellyfin_cache sullivan_plex_cache
docker compose up -d emby jellyfin plex
```

### Backup Strategy
- **Configs**: Git-tracked in ./services/
- **Databases**: Volume backups via duplicati/restic
- **Media**: /mnt/media backed up to offsite storage
- **Metadata**: *arr configs, wiki data

## Media Pipeline

### Download → Process → Stream Flow
1. **Request**: User requests via Sonarr/Radarr
2. **Search**: Prowlarr searches indexers
3. **Download**: qBittorrent downloads to /mnt/media/downloads
4. **Process**: *arr apps move/rename to /mnt/media/tv or /mnt/media/movies
5. **Stream**: Emby/Jellyfin/Plex serve from /mnt/media

### Directory Structure
```
/mnt/media/
├── downloads/      # qBittorrent incomplete
├── complete/       # Finished torrents
├── movies/         # Radarr managed
├── tv/             # Sonarr managed
├── music/          # Lidarr managed
├── youtube/        # yt-dlp managed
└── staging/        # Nextcloud sync target
```

## Security

### Authentication
- **All services** behind Authentik SSO (on FREDDY)
- **LDAP**: TLS required (port 636)
- **Forward Auth**: Nginx validates before proxying
- **API Keys**: Stored in .env, never in configs

### Network Isolation
- Frontend: nginx only
- Backend: nginx + services
- Database: services + postgres/mongodb
- No direct external access to backend/database

### Media Access
- Mount /mnt/media read-only unless service needs write
- qBittorrent, *arr apps get read-write
- Streaming services get read-only

## Troubleshooting

### Service Won't Start
```bash
# Check logs
docker compose logs <service>

# Verify dependencies
docker compose ps

# Check volumes
docker volume ls | grep sullivan
```

### Media Not Appearing
1. Check file permissions: `ls -la /mnt/media/`
2. Verify volume mounts: `docker compose exec <service> ls /media`
3. Trigger library scan in media server UI
4. Check *arr app logs for import errors

### LDAP Authentication Failing
1. Test LDAP from SULLIVAN:
   ```bash
   docker compose run --rm --entrypoint /bin/sh <service>
   nc -zv freddy 636
   ```
2. Check Authentik LDAP provider on FREDDY
3. Verify bind credentials match
4. Check Authentik logs on FREDDY

### Transcoding Issues
1. Check hardware acceleration device: `ls -la /dev/dri`
2. Verify GPU passthrough in docker-compose.yml
3. Check transcoding cache: `docker compose exec <service> df -h /cache`
4. Monitor resource usage: `docker stats`

## Related Infrastructure

### Sister Server: FREDDY
- **Purpose**: Authentication, photos, cloud storage
- **Coordination**: Provides Authentik SSO, receives media from Nextcloud
- **Services**: Authentik, PhotoPrism, Nextcloud, Nginx

### Shared Resources
- **Tailscale**: VPN overlay for server-to-server communication
- **Domain**: 7gram.xyz (shared)
- **SSL**: Wildcard cert from FREDDY (or separate cert)

## Git Workflow

### What to Commit
✅ docker-compose.yml  
✅ .env.example (no secrets)  
✅ ./services/*/config/ (sanitized - no API keys)  
✅ ./scripts/*.sh  
✅ nginx configs (./services/nginx/conf.d/)  
✅ Documentation (*.md)  

### What to Ignore
❌ .env (contains API keys)  
❌ ./services/*/cache/  
❌ ./services/*/logs/  
❌ ./services/*/transcodes/ (Plex/Jellyfin)  
❌ /mnt/media/* (media files)  
❌ ./services/ollama/models/ (large model files)  

## When Generating Code

### Preferences
- **Language**: Bash for scripts, YAML for compose
- **Style**: Performance > convenience for media processing
- **Error handling**: Fail fast, log errors
- **Transcoding**: Always check for hardware acceleration
- **Permissions**: Respect media file permissions (755/644)

### Avoid
- Hardcoded API keys in compose files
- Anonymous volumes
- Running media servers as root
- Exposing database ports to host
- Mounting /mnt/media read-write unnecessarily

## Quick Reference

```bash
# Start all services
docker compose up -d

# Restart media servers
docker compose restart emby jellyfin plex

# View download status
docker compose exec qbittorrent qbittorrent-cli info

# Scan library (Jellyfin)
docker compose exec jellyfin curl -X POST http://localhost:8096/Library/Refresh

# Check Ollama models
docker compose exec ollama ollama list

# Clean cache safely
sudo ./scripts/cleanup-docker-cache.sh

# Migrate to bind mounts
sudo ./scripts/migrate-to-bind-mounts.sh
```

## Performance Optimization

### Transcoding
- Enable hardware acceleration when available
- Use cache volumes for transcoding temp files
- Set transcoding quality presets appropriately
- Monitor transcoding load: `docker stats`

### Downloads
- Configure qBittorrent bandwidth limits
- Use SSD for incomplete downloads (faster I/O)
- Set appropriate connection limits
- Enable UPnP/NAT-PMP if behind NAT

### Database
- Regular vacuuming for PostgreSQL
- Index optimization for Wiki.js
- Backup before major version upgrades

---

**Remember**: SULLIVAN handles heavy workloads. Monitor resource usage regularly and adjust allocation as needed. All authentication flows through FREDDY's Authentik instance.
