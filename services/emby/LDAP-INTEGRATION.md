# Emby LDAP Integration Guide

Configure Emby to authenticate users via Authentik's LDAP provider.

## Prerequisites

- [ ] Authentik LDAP provider configured (see `freddy/services/authentik/LDAP-SETUP.md`)
- [ ] LDAP service account created: `ldapservice`
- [ ] Emby server running on SULLIVAN
- [ ] Admin access to Emby web interface

## Step 1: Install LDAP Plugin

Emby requires the LDAP authentication plugin.

### Via Web UI

1. **Open Emby Dashboard**
   - Access: `https://emby.7gram.xyz` (or `http://sullivan:8096`)
   - Log in as administrator

2. **Navigate to Plugins**
   - Click: **☰ Menu** → **Dashboard**
   - Click: **Advanced** → **Plugins**

3. **Install LDAP Plugin**
   - Click: **Catalog** tab
   - Search: `LDAP`
   - Find: **LDAP Authentication**
   - Click: **Install**

4. **Restart Emby**
   - The plugin requires a restart
   - Click: **Restart Server** when prompted
   - Wait for Emby to come back online (~30 seconds)

## Step 2: Configure LDAP Authentication

### Via Web UI

1. **Open Plugin Settings**
   - Go to: **Dashboard** → **Plugins** → **My Plugins**
   - Click: **LDAP Authentication**

2. **LDAP Server Settings**

   **Connection:**
   ```
   LDAP Server:        freddy
   LDAP Port:          636
   Secure LDAP (SSL):  ✓ Checked (recommended)
   ```

   **Bind Settings:**
   ```
   LDAP Bind User:     cn=ldapservice,ou=users,dc=7gram,dc=xyz
   LDAP Bind Password: <service-account-password>
   ```

   **Search Settings:**
   ```
   LDAP Base DN:       dc=7gram,dc=xyz
   LDAP Search Filter: (objectClass=user)
   LDAP Search Attributes: uid,cn,mail
   ```

3. **User Attributes**

   ```
   LDAP Name Attribute:     cn
   LDAP Email Attribute:    mail
   LDAP Username Attribute: uid
   ```

4. **Advanced Settings** (Optional)

   ```
   Enable LDAP User Creation:     ✓ Checked (creates Emby user on first login)
   Enable LDAP User Sync:         ✓ Checked (updates user info from LDAP)
   LDAP Admin Filter:             (memberOf=cn=admins,ou=groups,dc=7gram,dc=xyz)
   ```

5. **Save Configuration**
   - Click: **Save**
   - Restart Emby if prompted

## Step 3: Test LDAP Connection

### Via Web UI

1. **Test Connection**
   - In LDAP plugin settings
   - Click: **Test LDAP Connection**
   - Should show: ✓ Connection successful

2. **Test User Search**
   - Enter a test username in search field
   - Click: **Search**
   - Should return user details from Authentik

## Step 4: Configure User Access

### Option A: Automatic User Creation (Recommended)

With "Enable LDAP User Creation" checked, users are automatically created when they first log in.

**Steps:**
1. User visits Emby login page
2. Enters Authentik username and password
3. LDAP authenticates against Authentik
4. Emby creates local user account automatically
5. User is logged in

### Option B: Manual User Creation

1. **Create Users Manually**
   - Go to: **Dashboard** → **Users**
   - Click: **Add User**
   - Enter username (must match LDAP uid)
   - Leave password blank (will use LDAP)

2. **Link to LDAP**
   - User logs in with LDAP credentials
   - Emby matches username to existing account
   - Password authentication via LDAP

## Step 5: Test Authentication

### Test Login

1. **Logout of Emby**
   - Click user menu → **Sign out**

2. **Login with LDAP User**
   - Username: `<authentik-username>` (not email)
   - Password: `<authentik-password>`
   - Click: **Sign In**

3. **Verify Login**
   - Should successfully authenticate
   - User dashboard loads
   - Check: **Dashboard** → **Users** shows the user

### Troubleshooting Login Issues

**Authentication fails:**
```bash
# On SULLIVAN, test LDAP connection
ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<service-password>' \
  -b "dc=7gram,dc=xyz" \
  "(uid=<username>)"

# Should return user details
```

**Check Emby logs:**
```bash
# On SULLIVAN
docker compose logs emby | grep -i ldap
```

**Common issues:**
- Username is email instead of uid (use uid, not email)
- LDAP server unreachable (check network connectivity)
- Wrong bind credentials (check service account password)
- User doesn't exist in Authentik (create user first)

## Step 6: Configure User Permissions

After users can log in:

1. **Set Library Access**
   - Go to: **Dashboard** → **Users**
   - Click on user
   - **Library Access** tab: Select allowed libraries
   - **Parental Control**: Set ratings if needed

2. **Set Playback Settings**
   - **Playback** tab: Configure quality limits, transcoding
   - **Remote Access**: Allow/deny remote streaming

3. **Set Administrator Rights** (Optional)
   - Check: **Allow this user to manage the server**
   - Only for trusted admin users

## Step 7: Disable Local Authentication (Optional)

For better security, disable local password authentication and only allow LDAP:

1. **Go to Settings**
   - **Dashboard** → **Advanced** → **Security**

2. **Authentication Providers**
   - Uncheck: **Default Authentication**
   - Keep: **LDAP Authentication** enabled

3. **Save**

**Warning:** Make sure LDAP is working first! Keep at least one local admin account as backup.

## LDAP Configuration Summary

```yaml
# LDAP Server
Server:              freddy
Port:                636
SSL/TLS:             Enabled

# Bind Settings
Bind DN:             cn=ldapservice,ou=users,dc=7gram,dc=xyz
Bind Password:       <service-account-password>

# Search Settings
Base DN:             dc=7gram,dc=xyz
Search Filter:       (objectClass=user)
Search Attributes:   uid,cn,mail

# User Mapping
Username Attribute:  uid
Name Attribute:      cn
Email Attribute:     mail

# Options
Auto-create Users:   Enabled
User Sync:           Enabled
```

## Security Recommendations

### Use LDAPS (Port 636)
```
✓ Secure:   ldaps://freddy:636
✗ Insecure: ldap://freddy:389 (credentials in clear text)
```

### Rotate Service Account Password
```bash
# Update in Authentik UI
# Directory → Users → ldapservice → Actions → Set Password

# Update in Emby LDAP plugin
# Dashboard → Plugins → LDAP Authentication → LDAP Bind Password
```

### Limit LDAP Access
- Create LDAP search group in Authentik
- Only include media users in this group
- Set search group in Authentik LDAP provider

### Monitor Authentication
```bash
# Check Emby logs for failed attempts
docker compose logs emby | grep -i "authentication failed"

# Check Authentik logs
# On FREDDY: Applications → Events
```

## Troubleshooting

### "LDAP connection failed"

**Check network connectivity:**
```bash
# From SULLIVAN
ping freddy
nc -zv freddy 636
```

**Check LDAP service on FREDDY:**
```bash
# On FREDDY
docker ps | grep ldap
netstat -tuln | grep 636
```

**Test LDAP manually:**
```bash
# From SULLIVAN
ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz"
```

### "User not found"

**Verify user exists in Authentik:**
- On FREDDY: https://auth.7gram.xyz
- Go to: **Directory** → **Users**
- Check user is **Active**

**Test LDAP search:**
```bash
ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(uid=<username>)"
```

**Check search filter:**
- In Emby LDAP settings
- Ensure `(objectClass=user)` is correct
- Try broader filter: `(objectClass=*)`

### "Authentication failed" (wrong password)

**Verify password in Authentik:**
- User might need to reset password
- Test login at: https://auth.7gram.xyz

**Check bind credentials:**
- Service account password might be wrong
- Re-enter in Emby LDAP settings

### SSL/TLS Certificate Errors

**If using self-signed cert:**
- Emby might reject the certificate
- Option 1: Use proper Let's Encrypt cert in Authentik
- Option 2: Use non-SSL (port 389) for internal network only

**Check certificate:**
```bash
openssl s_client -connect freddy:636 -showcerts
```

## Maintenance

### Sync LDAP Users

Emby can periodically sync user information from LDAP:

1. **Enable Auto-Sync**
   - **Dashboard** → **Plugins** → **LDAP Authentication**
   - Check: **Enable LDAP User Sync**

2. **Manual Sync**
   - Same settings page
   - Click: **Sync Users Now**

### Update LDAP Settings

After changing LDAP configuration:

1. Update settings in Emby LDAP plugin
2. Save configuration
3. Restart Emby: `docker compose restart emby`
4. Test authentication

## Next Steps

After Emby LDAP is configured:

- **Task 7**: Configure Jellyfin LDAP authentication
- **Task 8**: Configure Nextcloud LDAP authentication
- **Verify**: Test login with multiple users
- **Document**: Save service account password in password manager

## Quick Reference

```bash
# Test LDAP from SULLIVAN
ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(uid=<username>)"

# View Emby logs
docker compose logs -f emby

# Restart Emby
docker compose restart emby

# Test authentication with curl
curl -X POST 'http://sullivan:8096/Users/AuthenticateByName' \
  -H 'Content-Type: application/json' \
  -d '{"Username":"<username>","Pw":"<password>"}'
```

---

**Status**: Ready to configure  
**Prerequisites**: LDAP provider configured on FREDDY  
**Next**: Configure Jellyfin LDAP (Task 7)
