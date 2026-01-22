#!/bin/sh
# Generate Secrets Script for Sullivan Infrastructure
# This script generates SSH keys and credentials for GitHub Actions deployment
#
# Usage:
#   chmod +x generate-secrets.sh
#   sudo ./generate-secrets.sh
#
# This script will:
# - Generate SSH key pair for actions user
# - Add public key to authorized_keys
# - Output all secrets needed for GitHub Actions
# - Create a credentials file for easy copying

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Log functions
log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
log_header() {
    printf "\n"
    printf "${BOLD}${CYAN}================================================================================${NC}\n"
    printf "${BOLD}${CYAN}  %s${NC}\n" "$*"
    printf "${BOLD}${CYAN}================================================================================${NC}\n"
    printf "\n"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

log_header "Sullivan - GitHub Actions Secrets Generator"

# =============================================================================
# Configuration
# =============================================================================
ACTIONS_USER="actions"
ACTIONS_HOME="/home/$ACTIONS_USER"
SSH_DIR="$ACTIONS_HOME/.ssh"
KEY_NAME="sullivan_deploy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CREDENTIALS_FILE="/tmp/sullivan_credentials_${TIMESTAMP}.txt"

# =============================================================================
# Check Prerequisites
# =============================================================================
log_info "Checking prerequisites..."

# Check if actions user exists
if ! id "$ACTIONS_USER" >/dev/null 2>&1; then
    log_error "User '$ACTIONS_USER' does not exist!"
    log_error "Run setup-production-server.sh first to create the user"
    exit 1
fi
log_success "User '$ACTIONS_USER' exists"

# Ensure .ssh directory exists
if [ ! -d "$SSH_DIR" ]; then
    log_info "Creating SSH directory..."
    sudo -u "$ACTIONS_USER" mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# =============================================================================
# Generate SSH Key Pair
# =============================================================================
log_header "Generating SSH Key Pair"

KEY_PATH="$SSH_DIR/$KEY_NAME"
KEY_PATH_PUB="${KEY_PATH}.pub"

if [ -f "$KEY_PATH" ]; then
    log_warn "SSH key already exists at $KEY_PATH"
    printf "Do you want to generate a new key? This will overwrite the existing key. (y/N) "
    read -r reply
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        log_info "Using existing SSH key"
        GENERATE_NEW_KEY=false
    else
        GENERATE_NEW_KEY=true
        # Backup existing key
        mv "$KEY_PATH" "${KEY_PATH}.backup.${TIMESTAMP}"
        mv "$KEY_PATH_PUB" "${KEY_PATH_PUB}.backup.${TIMESTAMP}" 2>/dev/null || true
        log_info "Existing key backed up"
    fi
else
    GENERATE_NEW_KEY=true
fi

if [ "$GENERATE_NEW_KEY" = true ]; then
    log_info "Generating new Ed25519 SSH key pair..."
    
    # Generate key as actions user
    sudo -u "$ACTIONS_USER" ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "sullivan-deploy-${TIMESTAMP}"
    
    chmod 600 "$KEY_PATH"
    chmod 644 "$KEY_PATH_PUB"
    chown "$ACTIONS_USER:$ACTIONS_USER" "$KEY_PATH" "$KEY_PATH_PUB"
    
    log_success "SSH key pair generated"
fi

# =============================================================================
# Add Public Key to authorized_keys
# =============================================================================
log_info "Adding public key to authorized_keys..."

AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
PUB_KEY_CONTENT=$(cat "$KEY_PATH_PUB")

# Check if key already exists in authorized_keys
if [ -f "$AUTHORIZED_KEYS" ] && grep -q "$PUB_KEY_CONTENT" "$AUTHORIZED_KEYS"; then
    log_info "Public key already in authorized_keys"
else
    echo "$PUB_KEY_CONTENT" >> "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    chown "$ACTIONS_USER:$ACTIONS_USER" "$AUTHORIZED_KEYS"
    log_success "Public key added to authorized_keys"
fi

# =============================================================================
# Get Tailscale IP (if available)
# =============================================================================
log_info "Detecting Tailscale IP..."

TAILSCALE_IP=""
if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -n "$TAILSCALE_IP" ]; then
        log_success "Tailscale IP: $TAILSCALE_IP"
    else
        log_warn "Tailscale installed but not connected"
    fi
else
    log_warn "Tailscale not installed"
    log_info "Install Tailscale: curl -fsSL https://tailscale.com/install.sh | sh"
fi

# Get local IP as fallback
LOCAL_IP=$(hostname -I | awk '{print $1}')

# =============================================================================
# Get Machine Name
# =============================================================================
HOSTNAME=$(hostname)

# =============================================================================
# Generate Credentials File
# =============================================================================
log_header "Generating Credentials File"

PRIVATE_KEY_CONTENT=$(cat "$KEY_PATH")

cat > "$CREDENTIALS_FILE" << EOF
================================================================================
SULLIVAN - GITHUB ACTIONS SECRETS
================================================================================
Generated: $(date)
Server: $HOSTNAME
Tailscale IP: ${TAILSCALE_IP:-"Not configured"}
Local IP: $LOCAL_IP

================================================================================
REQUIRED GITHUB SECRETS
================================================================================
Add these secrets to your GitHub repository:
https://github.com/YOUR_USERNAME/sullivan/settings/secrets/actions

--------------------------------------------------------------------------------
SECRET: SSH_PRIVATE_KEY
--------------------------------------------------------------------------------
$PRIVATE_KEY_CONTENT

--------------------------------------------------------------------------------
SECRET: TAILSCALE_IP
--------------------------------------------------------------------------------
${TAILSCALE_IP:-$LOCAL_IP}

--------------------------------------------------------------------------------
SECRET: SULLIVAN_DIR (Optional - defaults to /home/actions/sullivan)
--------------------------------------------------------------------------------
$ACTIONS_HOME/sullivan

================================================================================
TAILSCALE OAUTH SECRETS (Create at https://login.tailscale.com/admin/settings/oauth)
================================================================================
You need to create OAuth credentials in Tailscale Admin Console:
1. Go to https://login.tailscale.com/admin/settings/oauth
2. Create a new OAuth client
3. Grant it the "tag:ci" tag (create the tag in ACLs first)
4. Copy the Client ID and Secret below

--------------------------------------------------------------------------------
SECRET: TS_OAUTH_CLIENT_ID
--------------------------------------------------------------------------------
<Create at Tailscale Admin Console>

--------------------------------------------------------------------------------
SECRET: TS_OAUTH_SECRET
--------------------------------------------------------------------------------
<Create at Tailscale Admin Console>

================================================================================
OPTIONAL SECRETS
================================================================================

--------------------------------------------------------------------------------
SECRET: DISCORD_WEBHOOK (Optional - for deployment notifications)
--------------------------------------------------------------------------------
<Your Discord webhook URL>

================================================================================
TAILSCALE ACL CONFIGURATION
================================================================================
Add this to your Tailscale ACL (https://login.tailscale.com/admin/acls):

{
    "tagOwners": {
        "tag:ci": ["autogroup:admin"]
    },
    "acls": [
        {
            "action": "accept",
            "src": ["tag:ci"],
            "dst": ["*:22"]
        }
    ]
}

================================================================================
TEST SSH CONNECTION (from your local machine)
================================================================================
# Save the private key locally first:
cat > ~/.ssh/sullivan_deploy << 'KEYEOF'
$PRIVATE_KEY_CONTENT
KEYEOF
chmod 600 ~/.ssh/sullivan_deploy

# Test connection:
ssh -i ~/.ssh/sullivan_deploy $ACTIONS_USER@${TAILSCALE_IP:-$LOCAL_IP}

================================================================================
EOF

chmod 600 "$CREDENTIALS_FILE"

log_success "Credentials file created: $CREDENTIALS_FILE"

# =============================================================================
# Display Summary
# =============================================================================
log_header "Setup Complete!"

printf "${BOLD}${GREEN}SSH Key Information:${NC}\n"
printf "  Private Key: %s\n" "$KEY_PATH"
printf "  Public Key:  %s\n" "$KEY_PATH_PUB"
printf "  Fingerprint: %s\n" "$(ssh-keygen -lf "$KEY_PATH_PUB")"
printf "\n"

printf "${BOLD}${GREEN}Server Information:${NC}\n"
printf "  Hostname:     %s\n" "$HOSTNAME"
printf "  Tailscale IP: %s\n" "${TAILSCALE_IP:-"Not configured"}"
printf "  Local IP:     %s\n" "$LOCAL_IP"
printf "  SSH User:     %s\n" "$ACTIONS_USER"
printf "\n"

log_header "Next Steps"

printf "${BOLD}${CYAN}1. View the credentials file:${NC}\n"
printf "   ${GREEN}sudo cat %s${NC}\n\n" "$CREDENTIALS_FILE"

printf "${BOLD}${CYAN}2. Add secrets to GitHub:${NC}\n"
printf "   Go to: ${GREEN}https://github.com/YOUR_USERNAME/sullivan/settings/secrets/actions${NC}\n"
printf "   Add the following secrets:\n"
printf "     - SSH_PRIVATE_KEY (copy entire private key including BEGIN/END lines)\n"
printf "     - TAILSCALE_IP (%s)\n" "${TAILSCALE_IP:-$LOCAL_IP}"
printf "     - TS_OAUTH_CLIENT_ID (from Tailscale Admin)\n"
printf "     - TS_OAUTH_SECRET (from Tailscale Admin)\n"
printf "     - DISCORD_WEBHOOK (optional)\n\n"

printf "${BOLD}${CYAN}3. Setup Tailscale OAuth:${NC}\n"
printf "   Go to: ${GREEN}https://login.tailscale.com/admin/settings/oauth${NC}\n"
printf "   Create OAuth client with 'tag:ci' access\n\n"

printf "${BOLD}${CYAN}4. Clone repository on server:${NC}\n"
printf "   ${GREEN}sudo -u %s git clone https://github.com/YOUR_USERNAME/sullivan.git %s/sullivan${NC}\n\n" "$ACTIONS_USER" "$ACTIONS_HOME"

printf "${BOLD}${CYAN}5. Test the deployment:${NC}\n"
printf "   Push a commit or manually trigger the workflow in GitHub Actions\n\n"

log_warn "SECURITY REMINDER:"
printf "  - Delete the credentials file after copying to GitHub:\n"
printf "    ${RED}sudo rm %s${NC}\n" "$CREDENTIALS_FILE"
printf "  - Never commit private keys to the repository\n"
printf "  - Keep the credentials secure\n"
printf "\n"

log_success "Secrets generation complete!"

exit 0
