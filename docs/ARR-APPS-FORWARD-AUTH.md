# *arr Apps Forward Authentication Integration Guide

Configure Sonarr, Radarr, Lidarr, and Prowlarr to use Authentik forward authentication via Nginx.

## Overview

Forward authentication protects the web UI while allowing API access for inter-app communication. This is ideal for *arr apps since they:
- Don't natively support OIDC/LDAP
- Need unrestricted API access for automation
- Benefit from centralized SSO for web UI access

### How Forward Auth Works

```
1. User visits https://sonarr.7gram.xyz
2. Nginx intercepts request → sends auth check to Authentik
3. If not authenticated → redirect to Authentik login
4. User logs in with Authentik
5. Authentik redirects back → Nginx forwards to Sonarr
6. User sees Sonarr UI (authenticated)

API requests to /api bypass authentication entirely
```

## Prerequisites

- [ ] Authentik deployed on FREDDY with forward auth provider
- [ ] *arr apps running on SULLIVAN (Sonarr, Radarr, Lidarr, Prowlarr)
- [ ] Nginx running on SULLIVAN
- [ ] DNS entries configured for all apps
- [ ] SSL certificates available

## Configuration Files Created

The following nginx configs have been created with forward auth enabled:

```
sullivan/services/nginx/conf.d/
├── authentik-authrequest.conf    # Auth request configuration
├── authentik-location.conf        # Internal auth endpoint
├── authentik-redirect.conf        # Login redirect handler
├── sonarr.conf                    # Sonarr with forward auth
├── radarr.conf                    # Radarr with forward auth
├── lidarr.conf                    # Lidarr with forward auth
└── prowlarr.conf                  # Prowlarr with forward auth
```

## Setup Steps

### Step 1: Set Up Forward Auth Provider in Authentik

#### Via Authentik Web UI (on FREDDY)

1. **Navigate to Providers**
   - Go to: **Applications** → **Providers**
   - Click: **Create**

2. **Create Proxy Provider**
   - Type: **Proxy Provider**
   - Name: `Forward Auth - Arr Apps`
   - Authorization flow: `default-provider-authorization-implicit-consent`

3. **Forward Auth Settings**
   ```
   Type:              Forward auth (single application)
   External host:     https://sonarr.7gram.xyz
   Mode:              Forward auth (single application)
   Token validity:    hours=24
   ```

4. **Additional External Hosts**
   Add all *arr app URLs:
   ```
   https://radarr.7gram.xyz
   https://lidarr.7gram.xyz
   https://prowlarr.7gram.xyz
   ```

5. **Save Provider**

### Step 2: Create Application in Authentik

1. **Navigate to Applications**
   - Go: **Applications** → **Applications** → **Create**

2. **Configure Application**
   ```
   Name:           Arr Apps
   Slug:           arr-apps
   Provider:       Forward Auth - Arr Apps
   Launch URL:     (leave empty)
   ```

3. **Save**

### Step 3: Deploy Nginx Configuration

#### Copy Authentik Snippets to Nginx Container

```bash
# On SULLIVAN server
cd /path/to/sullivan

# Restart nginx to load new configs
docker compose restart nginx

# Verify nginx configuration is valid
docker compose exec nginx nginx -t

# Should output:
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Step 4: Configure DNS

Add DNS entries for all *arr apps:

```
sonarr.7gram.xyz    → SULLIVAN Tailscale IP
radarr.7gram.xyz    → SULLIVAN Tailscale IP
lidarr.7gram.xyz    → SULLIVAN Tailscale IP
prowlarr.7gram.xyz  → SULLIVAN Tailscale IP
```

**Test DNS:**
```bash
# From any machine
nslookup sonarr.7gram.xyz
nslookup radarr.7gram.xyz
nslookup lidarr.7gram.xyz
nslookup prowlarr.7gram.xyz
```

### Step 5: Test Forward Authentication

#### Test Sonarr

1. **Visit Application**
   - Open: https://sonarr.7gram.xyz
   - Should redirect to Authentik login

2. **Login with Authentik**
   - Username: `<your-authentik-username>`
   - Password: `<your-authentik-password>`

3. **Verify Access**
   - Should be redirected back to Sonarr
   - Sonarr UI loads normally
   - Check browser cookies (authentik_session present)

#### Test API Access (No Auth Required)

```bash
# API requests should work without authentication
curl https://sonarr.7gram.xyz/api/v3/system/status \
  -H "X-Api-Key: <sonarr-api-key>"

# Should return JSON status (not redirect to login)
```

#### Test Other Apps

Repeat for Radarr, Lidarr, Prowlarr using their respective URLs.

## Configuration Details

### Nginx Server Block Structure

Each *arr app config follows this pattern:

```nginx
server {
    listen 443 ssl http2;
    server_name <app>.7gram.xyz;

    # SSL certificates
    ssl_certificate /opt/ssl/7gram.xyz/fullchain.pem;
    ssl_certificate_key /opt/ssl/7gram.xyz/privkey.pem;

    # Authentik forward auth
    include /etc/nginx/conf.d/authentik-authrequest.conf;
    include /etc/nginx/conf.d/authentik-location.conf;
    error_page 401 = @authentik_proxy_signin;

    # Main location - requires authentication
    location / {
        proxy_pass http://<app>:<port>;
        # ... proxy headers including Authentik user info
    }

    # API location - no authentication
    location ~ ^/api {
        proxy_pass http://<app>:<port>;
        auth_request off;  # Bypass authentication for API
    }

    # RSS feeds - no authentication
    location ~ ^/feed {
        proxy_pass http://<app>:<port>;
        auth_request off;  # Bypass authentication for RSS
    }
}
```

### Application Ports

```
Sonarr:   8989
Radarr:   7878
Lidarr:   8686
Prowlarr: 9696
```

### Authentik User Headers

After authentication, these headers are available to the backend:

```nginx
X-Authentik-Username: <username>
X-Authentik-Email:    <email>
X-Authentik-Name:     <full-name>
X-Authentik-Groups:   <comma-separated-groups>
X-Authentik-UID:      <user-id>
```

While *arr apps don't use these, they're available for logging or future features.

## Advanced Configuration

### Group-Based Access Control

Restrict access to specific groups:

#### In Authentik

1. **Create Group**
   - Go to: **Directory** → **Groups** → **Create**
   - Name: `arr-users`

2. **Add Users**
   - Edit group → Add users who should have access

3. **Create Policy**
   - Go to: **Policies** → **Create** → **Expression Policy**
   - Name: `Arr Apps Access Policy`
   - Expression:
     ```python
     return ak_is_group_member(request.user, name="arr-users")
     ```

4. **Bind Policy**
   - Edit "Arr Apps" application
   - **Policy / Group / User Bindings** → Add policy

### Per-App Access Control

Create separate providers for finer control:

```
Provider: Sonarr Forward Auth  →  Application: Sonarr  →  Policy: sonarr-users group
Provider: Radarr Forward Auth  →  Application: Radarr  →  Policy: radarr-admins group
```

Update nginx configs to use app-specific endpoints.

### Custom Sign-In Page

Customize the Authentik login page for arr apps:

1. Go to: **System** → **Brands**
2. Edit default brand
3. Upload custom logo, set colors
4. Title: "7gram Media Server Login"

## Troubleshooting

### "502 Bad Gateway"

**Check app is running:**
```bash
# On SULLIVAN
docker compose ps | grep -E "sonarr|radarr|lidarr|prowlarr"
```

**Check nginx can reach app:**
```bash
docker compose exec nginx ping sonarr
docker compose exec nginx curl http://sonarr:8989
```

### "Redirect loop" or "Too many redirects"

**Check Authentik is reachable from nginx:**
```bash
# On SULLIVAN
docker compose exec nginx curl http://freddy:9000/outpost.goauthentik.io
```

**Verify Tailscale or network connectivity:**
```bash
ping freddy
```

**Check authentik-location.conf has correct host:**
```nginx
proxy_pass http://freddy:9000/outpost.goauthentik.io;
```

### "Authentication failed" but Authentik login works

**Check provider external hosts:**
- In Authentik: Edit Forward Auth provider
- Ensure all app URLs listed in "External host" field
- Must match exactly (https://sonarr.7gram.xyz)

**Check cookies:**
- Clear browser cookies for 7gram.xyz domain
- Try in incognito/private browsing mode

### API Requests Return Login Page

**Verify auth_request off in API location:**
```nginx
location ~ ^/api {
    auth_request off;  # Must be present
    proxy_pass http://sonarr:8989;
}
```

**Test API directly on Sullivan:**
```bash
docker compose exec nginx curl http://sonarr:8989/api/v3/system/status
```

### Apps Can't Communicate with Each Other

This is expected! *arr apps use API keys, not authentication:

**Solution:**
- Apps communicate via internal Docker network (no nginx)
- Or use API endpoints which bypass authentication
- Configure API URLs in apps: `http://sonarr:8989` (internal)

**Example: Prowlarr → Sonarr connection**
```
In Prowlarr settings:
Sonarr URL: http://sonarr:8989
API Key: <sonarr-api-key>
```

### SSL Certificate Errors

**Check certificates exist:**
```bash
# On SULLIVAN
ls -la /opt/ssl/7gram.xyz/
# Should show: fullchain.pem, privkey.pem
```

**Test SSL:**
```bash
openssl s_client -connect sonarr.7gram.xyz:443 -servername sonarr.7gram.xyz
```

## Security Recommendations

### Always Use HTTPS

```
✓ Good:  https://sonarr.7gram.xyz (protected by forward auth)
✗ Bad:   http://sonarr.7gram.xyz  (insecure)
```

### Protect API Keys

API endpoints bypass auth but require API keys:
- Store API keys in password manager
- Rotate API keys if compromised
- Use different API keys per integration

### Monitor Access

**Check Authentik logs:**
- On FREDDY: **Events** → **Logs**
- Filter by: Arr Apps application
- Look for: Failed auth attempts, suspicious IPs

**Check nginx access logs:**
```bash
# On SULLIVAN
docker compose logs nginx | grep -E "sonarr|radarr"
```

### Limit Forward Auth Token Validity

In Authentik provider settings:
```
Token validity: hours=8 (forces re-auth daily)
```

### Use Strong Session Cookies

Authentik sets secure session cookies by default:
- HttpOnly (not accessible to JavaScript)
- Secure (HTTPS only)
- SameSite (CSRF protection)

## Maintenance

### Update Nginx Configs

After modifying nginx configs:

```bash
# Test configuration
docker compose exec nginx nginx -t

# Reload nginx (no downtime)
docker compose exec nginx nginx -s reload

# Or restart container
docker compose restart nginx
```

### Add New *arr App

1. Create nginx config (copy existing one, change ports/name)
2. Add to Authentik forward auth provider external hosts
3. Reload nginx
4. Test authentication

### Remove Forward Auth (Emergency)

To temporarily disable auth:

```nginx
# Comment out these lines in app conf:
# include /etc/nginx/conf.d/authentik-authrequest.conf;
# include /etc/nginx/conf.d/authentik-location.conf;
# error_page 401 = @authentik_proxy_signin;

# Reload nginx
docker compose exec nginx nginx -s reload
```

## Testing Checklist

After configuration:

- [ ] Can access https://sonarr.7gram.xyz (redirects to Authentik)
- [ ] Can login with Authentik credentials
- [ ] Redirected back to Sonarr after login
- [ ] Sonarr UI loads normally
- [ ] API requests work: `curl https://sonarr.7gram.xyz/api/...`
- [ ] Repeat test for Radarr, Lidarr, Prowlarr
- [ ] Inter-app communication works (Prowlarr ↔ Sonarr)
- [ ] Logout redirects properly
- [ ] Re-login works without issues

## Next Steps

1. Test all *arr apps with forward auth
2. Configure group-based access control in Authentik
3. Set up monitoring for authentication failures
4. Document API keys securely
5. Configure inter-app connections (Prowlarr → *arr apps)

## Quick Reference

```bash
# Reload nginx after config changes
docker compose exec nginx nginx -s reload

# Test nginx configuration
docker compose exec nginx nginx -t

# View nginx logs
docker compose logs -f nginx

# View Authentik logs (on FREDDY)
docker compose logs -f authentik-server

# Test API access
curl https://sonarr.7gram.xyz/api/v3/system/status \
  -H "X-Api-Key: <api-key>"

# Test auth endpoint from SULLIVAN
docker compose exec nginx curl http://freddy:9000/outpost.goauthentik.io

# Clear browser cookies
# Chrome: Settings → Privacy → Cookies → See all cookies → 7gram.xyz → Remove all
```

---

**Status**: Ready to deploy  
**Prerequisites**: Authentik forward auth provider configured  
**Next**: Test authentication on all *arr apps
