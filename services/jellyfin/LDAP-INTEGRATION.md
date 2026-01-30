# Jellyfin LDAP Integration with Authentik

Guide for integrating Jellyfin with Authentik's LDAP provider for centralized authentication.

## Overview

Jellyfin has native LDAP authentication support through its LDAP plugin, allowing users to log in with their Authentik credentials.

**Architecture:**
- Jellyfin on SULLIVAN connects to Authentik LDAP on FREDDY
- LDAPS connection over port 636 (encrypted)
- Automatic user creation on first login
- User attributes synchronized from LDAP

## Prerequisites

1. **Authentik LDAP provider configured on FREDDY**
   - See: `freddy/services/authentik/LDAP-SETUP.md`
   - LDAP outpost running on freddy:636
   - Base DN: `dc=7gram,dc=xyz`
   - Service account: `cn=ldapservice,ou=users,dc=7gram,dc=xyz`

2. **Network connectivity**
   - SULLIVAN can reach FREDDY via Tailscale or Docker network
   - Port 636 (LDAPS) accessible from SULLIVAN

3. **Test LDAP connection from SULLIVAN**
   ```bash
   # Test LDAPS connectivity
   ldapsearch -x -H ldaps://freddy:636 \
     -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
     -w '<service-account-password>' \
     -b "dc=7gram,dc=xyz" \
     "(objectClass=user)"
   ```

## Installation Steps

### Step 1: Install LDAP Plugin

1. **Access Jellyfin dashboard**:
   - Navigate to: https://jellyfin.7gram.xyz
   - Login as admin

2. **Install LDAP-Auth plugin**:
   - Go to: **Dashboard** → **Plugins** → **Catalog**
   - Search for: **LDAP-Auth Plugin**
   - Click **Install**
   - Restart Jellyfin when prompted:
     ```bash
     docker compose restart jellyfin
     ```

3. **Verify plugin installed**:
   - Go to: **Dashboard** → **Plugins** → **My Plugins**
   - Should see: **LDAP-Auth Plugin** listed

### Step 2: Configure LDAP Authentication

1. **Access LDAP plugin settings**:
   - Go to: **Dashboard** → **Plugins** → **LDAP-Auth Plugin**
   - Or: **Dashboard** → **Advanced** → **Plugins** → **LDAP-Auth Plugin**

2. **Configure LDAP server settings**:

   **General Settings:**
   - **LDAP Server**: `freddy`
   - **LDAP Port**: `636`
   - **Secure LDAP**: ✅ **Enabled** (LDAPS)
   - **Allow SSL certificate errors**: ❌ **Disabled** (use valid cert)
   - **Bind User**: `cn=ldapservice,ou=users,dc=7gram,dc=xyz`
   - **Bind Password**: `<service-account-password>`

   **Search Settings:**
   - **LDAP Base DN for searches**: `dc=7gram,dc=xyz`
   - **LDAP Search Filter**: `(objectClass=user)`
   - **LDAP Search Attributes**: `uid,cn,mail,displayName`
   - **LDAP Admin Base DN**: `ou=groups,dc=7gram,dc=xyz` (optional)
   - **LDAP Admin Filter**: `(cn=jellyfin-admins)` (optional)

   **User Mapping:**
   - **LDAP Username Attribute**: `uid`
   - **LDAP Password Attribute**: Leave empty (uses bind authentication)
   - **Enable case-insensitive username**: ✅ **Enabled**
   - **Create users automatically**: ✅ **Enabled**

3. **Save settings**:
   - Click **Save**
   - Plugin will test connection

### Step 3: Configure User Authentication Order

Jellyfin tries authentication methods in order. Configure LDAP as primary:

1. **Go to**: **Dashboard** → **Users**
2. **For each user**:
   - Edit user
   - **Authentication Provider**: Select **LDAP**
   - Save

**Or** configure globally:
- New users will authenticate via LDAP by default
- Existing local users remain unless changed

### Step 4: Test LDAP Authentication

1. **Logout of Jellyfin admin**

2. **Login with LDAP user**:
   - Username: `<authentik-username>` (e.g., `jordan`)
   - Password: `<authentik-password>`

3. **Verify user created**:
   - Login should succeed
   - Go to: **Dashboard** → **Users**
   - New user should appear with username from LDAP

4. **Check user details**:
   - Click on user
   - Should show: **Authentication Provider: LDAP**
   - Email should be populated from LDAP `mail` attribute

## Configuration Examples

### Basic Configuration (Most Common)

```yaml
# LDAP-Auth Plugin Configuration
LDAP Server: freddy
LDAP Port: 636
Secure LDAP: true
Bind User: cn=ldapservice,ou=users,dc=7gram,dc=xyz
Bind Password: <password>
Base DN: dc=7gram,dc=xyz
Search Filter: (objectClass=user)
Username Attribute: uid
Create users automatically: true
```

### Advanced Configuration with Admin Group

```yaml
# LDAP-Auth Plugin Configuration
LDAP Server: freddy
LDAP Port: 636
Secure LDAP: true
Bind User: cn=ldapservice,ou=users,dc=7gram,dc=xyz
Bind Password: <password>

# User Search
Base DN: dc=7gram,dc=xyz
Search Filter: (objectClass=user)
Search Attributes: uid,cn,mail,displayName

# Admin Group (Optional)
Admin Base DN: ou=groups,dc=7gram,dc=xyz
Admin Filter: (cn=jellyfin-admins)

# User Mapping
Username Attribute: uid
Create users automatically: true
Enable case-insensitive username: true
```

To use admin group:
1. Create group in Authentik: `jellyfin-admins`
2. Add users to group
3. Users in this group will have admin privileges in Jellyfin

## User Management

### Automatic User Creation

When LDAP user logs in for the first time:
1. Jellyfin queries LDAP for user details
2. Creates local user with LDAP attributes
3. Sets authentication provider to LDAP
4. User can login with LDAP credentials going forward

### User Attribute Mapping

Jellyfin maps LDAP attributes to local user fields:

| Jellyfin Field | LDAP Attribute | Notes |
|----------------|----------------|-------|
| Username | `uid` | Required, unique identifier |
| Display Name | `cn` or `displayName` | Full name |
| Email | `mail` | Email address |
| Admin Status | Group membership | Via admin filter |

### Managing Existing Users

**Migrate local user to LDAP:**
1. Ensure LDAP user has same username
2. Edit user in Jellyfin dashboard
3. Change **Authentication Provider** to **LDAP**
4. User must login with LDAP password going forward

**Disable LDAP for specific user:**
1. Edit user
2. Change **Authentication Provider** to **Default** (local)
3. Set local password

## Troubleshooting

### LDAP Connection Failed

**Symptom**: Can't connect to LDAP server

**Diagnosis**:
```bash
# Test network connectivity
ping freddy

# Test LDAPS port
nc -zv freddy 636

# Test LDAP bind
ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz"
```

**Solutions**:
- Verify LDAP outpost running on FREDDY: `docker ps | grep ldap`
- Check firewall allows port 636
- Verify Docker network connectivity
- Check Tailscale connection: `tailscale status`

### SSL Certificate Errors

**Symptom**: "SSL certificate validation failed"

**Options**:
1. **Use valid certificate** (recommended):
   - Ensure Authentik LDAP uses valid SSL cert
   - Check cert in Authentik settings

2. **Allow certificate errors** (not recommended):
   - Enable: **Allow SSL certificate errors**
   - Only for testing/internal networks

### Authentication Failed

**Symptom**: User can't login, "Invalid username or password"

**Diagnosis**:
```bash
# Test user authentication manually
ldapsearch -x -H ldaps://freddy:636 \
  -D "uid=<username>,ou=users,dc=7gram,dc=xyz" \
  -w '<user-password>' \
  -b "dc=7gram,dc=xyz"
```

**Common causes**:
- Wrong username/password
- User doesn't exist in Authentik
- User not in correct LDAP OU
- Search filter too restrictive

**Solutions**:
- Verify user exists: Check Authentik dashboard → Directory → Users
- Verify search filter: `(objectClass=user)` should match all users
- Check LDAP base DN includes user's OU
- Try different username attribute: `uid`, `cn`, `sAMAccountName`

### User Not Created Automatically

**Symptom**: Login succeeds but user not created in Jellyfin

**Check**:
- **Create users automatically**: Must be enabled
- **Username attribute**: Must match LDAP attribute
- User may already exist with different authentication provider

**Solutions**:
- Enable: **Create users automatically**
- Verify username attribute matches LDAP: `uid`
- Check Jellyfin logs for errors

### Wrong User Attributes

**Symptom**: User created but missing name/email

**Diagnosis**:
```bash
# Check user attributes in LDAP
ldapsearch -x -H ldaps://freddy:636 \
  -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" \
  -w '<password>' \
  -b "dc=7gram,dc=xyz" \
  "(uid=<username>)" \
  uid cn mail displayName
```

**Solutions**:
- Verify attributes exist in Authentik user profile
- Update **LDAP Search Attributes**: `uid,cn,mail,displayName`
- Map correct attributes in Authentik LDAP provider

## Jellyfin Logs

Check Jellyfin logs for LDAP authentication issues:

```bash
# View Jellyfin logs
docker compose logs jellyfin | grep -i ldap

# Follow logs in real-time
docker compose logs -f jellyfin

# Check authentication errors
docker compose logs jellyfin | grep -i "authentication\|failed\|error"
```

**Common log messages:**
- `LDAP search successful` - LDAP query worked
- `LDAP bind failed` - Service account credentials wrong
- `User authenticated successfully` - User login succeeded
- `Creating new user from LDAP` - Auto-user-creation working

## Security Considerations

### Use LDAPS (Port 636)

Always use encrypted LDAPS connection:
- Protects credentials in transit
- Prevents man-in-the-middle attacks
- Required for production use

### Service Account Permissions

LDAP service account should have minimal permissions:
- **Read-only** access to user directory
- **No write** permissions
- **No admin** privileges

Configured in Authentik:
- User: `ldapservice`
- Groups: `ldap-users` (read-only)

### Credential Storage

Bind password stored in Jellyfin database:
- Encrypted at rest
- Protect Jellyfin database backups
- Rotate service account password periodically

### User Access Control

Control Jellyfin access via Authentik:
- Create group: `jellyfin-users`
- Add users to group
- Configure LDAP search filter: `(memberOf=cn=jellyfin-users,ou=groups,dc=7gram,dc=xyz)`

Only users in `jellyfin-users` group can login.

## Testing Checklist

### Pre-Deployment Tests
- [ ] LDAP service account can bind
- [ ] LDAP search returns test user
- [ ] Network connectivity from SULLIVAN to FREDDY port 636
- [ ] LDAPS certificate valid

### Post-Configuration Tests
- [ ] LDAP plugin installed and enabled
- [ ] LDAP settings saved successfully
- [ ] Test user can login with LDAP credentials
- [ ] User created automatically in Jellyfin
- [ ] User attributes populated (name, email)
- [ ] Library access works after LDAP login
- [ ] Playback works normally

### Production Validation
- [ ] Multiple users can login
- [ ] Users can access their libraries
- [ ] Admin users have correct permissions
- [ ] No authentication errors in logs
- [ ] LDAP authentication performant (<2s login time)

## Integration with Authentik

### User Provisioning Flow

```
1. User enters credentials in Jellyfin login
2. Jellyfin queries LDAP: "Does user exist?"
3. Authentik LDAP outpost validates credentials
4. If valid, return user attributes to Jellyfin
5. Jellyfin creates local user (if not exists)
6. Jellyfin grants access to user
```

### User Updates

**Updating user attributes:**
1. Update user in Authentik (name, email, etc.)
2. Next Jellyfin login will sync updated attributes
3. Or: Delete user in Jellyfin to force recreation with new attributes

**Disabling user:**
1. Disable user in Authentik or remove from group
2. User can no longer login to Jellyfin
3. Or: Delete user in Jellyfin dashboard

## Migration from Local Users

### Strategy 1: Gradual Migration

1. Deploy LDAP, keep local authentication
2. Create LDAP users in Authentik matching local usernames
3. Users login with LDAP credentials
4. Disable local authentication after all users migrated

### Strategy 2: Force Migration

1. Export user list from Jellyfin
2. Create matching users in Authentik
3. Configure LDAP authentication
4. Change all users to LDAP authentication provider
5. Notify users to login with LDAP credentials

### Preserve User Data

User libraries, watch history, and preferences are preserved:
- Based on username (must match LDAP `uid`)
- Change authentication provider without deleting user
- User data remains intact

## Advanced Configuration

### Multiple LDAP Servers (Fallback)

Not natively supported in Jellyfin. Workaround:
- Use Authentik LDAP provider as single entry point
- Authentik can aggregate multiple identity sources
- Configure redundancy at Authentik level

### Custom Attribute Mapping

Limited customization in Jellyfin plugin:
- Username attribute: configurable (`uid`, `cn`, `sAMAccountName`)
- Display name: from `cn` or `displayName`
- Email: from `mail`

For custom attributes, modify Authentik LDAP property mappings.

### Group-Based Library Access

Jellyfin doesn't directly support LDAP group-based library access. Workaround:

1. Create Authentik groups: `jellyfin-movies`, `jellyfin-tv`, etc.
2. Use LDAP search filter: `(memberOf=cn=jellyfin-movies,ou=groups,dc=7gram,dc=xyz)`
3. Create separate Jellyfin user for each group
4. Assign libraries per user

**Better approach**: Use Jellyfin's built-in library access control after LDAP login.

## Comparison: Jellyfin vs Emby LDAP

| Feature | Jellyfin | Emby |
|---------|----------|------|
| LDAP Plugin | Built-in via plugin | Built-in via plugin |
| LDAPS Support | ✅ Yes | ✅ Yes |
| Auto-user creation | ✅ Yes | ✅ Yes |
| Admin group mapping | ✅ Yes | ✅ Yes |
| Custom attributes | Limited | Limited |
| Configuration | Plugin settings | Plugin settings |
| Performance | Fast | Fast |

Both have similar LDAP capabilities. Choose based on media server preference.

## Quick Reference

### LDAP Configuration Summary

```
Server: freddy
Port: 636
Secure: Yes (LDAPS)
Bind DN: cn=ldapservice,ou=users,dc=7gram,dc=xyz
Base DN: dc=7gram,dc=xyz
Search Filter: (objectClass=user)
Username Attribute: uid
Auto-create: Yes
```

### Common ldapsearch Commands

```bash
# Test connection
ldapsearch -x -H ldaps://freddy:636 -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" -w '<password>' -b "dc=7gram,dc=xyz"

# Search for specific user
ldapsearch -x -H ldaps://freddy:636 -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" -w '<password>' -b "dc=7gram,dc=xyz" "(uid=jordan)"

# Test user authentication
ldapsearch -x -H ldaps://freddy:636 -D "uid=jordan,ou=users,dc=7gram,dc=xyz" -w '<user-password>' -b "dc=7gram,dc=xyz"

# List all users
ldapsearch -x -H ldaps://freddy:636 -D "cn=ldapservice,ou=users,dc=7gram,dc=xyz" -w '<password>' -b "ou=users,dc=7gram,dc=xyz" "(objectClass=user)" uid cn mail
```

---

**Document Version**: 1.0  
**Last Updated**: October 20, 2025  
**Status**: Ready for deployment  
**Related**: `freddy/services/authentik/LDAP-SETUP.md`, `sullivan/services/emby/LDAP-INTEGRATION.md`
