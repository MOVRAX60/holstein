# External Rancher Integration Setup Guide

This guide configures your monitoring stack to connect to an external Rancher instance via nginx proxy and Keycloak authentication.

## Step 1: Update Environment Variables

Add these variables to your `.env` file:

```bash
# External Rancher Configuration
RANCHER_EXTERNAL_HOST=rancher-k3s.local
RANCHER_ENABLED=true
RANCHER_CLIENT_SECRET=your-rancher-client-secret

# Remove these old Rancher variables (no longer needed)
# RANCHER_VERSION=latest
# RANCHER_BOOTSTRAP_PASSWORD=...
# RANCHER_PASSWORD_MIN_LENGTH=...
# RANCHER_FEATURES=...
# RANCHER_AUDIT_LEVEL=...
# RANCHER_DEFAULT_REGISTRY=...
```

## Step 2: Create Keycloak Client for External Rancher

### 2.1 Access Keycloak Admin Console

1. Navigate to `https://your-domain.com/auth/admin`
2. Login with admin credentials
3. Select your realm (master or custom realm)

### 2.2 Create Rancher Client

1. Go to **Clients** → **Create client**
2. Configure basic settings:

```
Client type: OpenID Connect
Client ID: rancher
Name: External Rancher
Description: External Rancher K3s cluster management
```

3. **Capability config**:
```
Client authentication: ON
Authorization: OFF
Standard flow: ON
Direct access grants: OFF
Implicit flow: OFF
Service accounts roles: OFF
```

4. **Settings** tab:
```
Valid redirect URIs: 
  - https://rancher-k3s.local/verify-auth-azure
  - https://your-domain.com/rancher/verify-auth-azure
  - https://rancher-k3s.local/*
  - https://your-domain.com/rancher/*

Valid post logout redirect URIs:
  - https://rancher-k3s.local/
  - https://your-domain.com/rancher/

Web origins: 
  - https://rancher-k3s.local
  - https://your-domain.com
```

5. **Credentials** tab:
   - Copy the **Client secret** and add to your `.env` file as `RANCHER_CLIENT_SECRET`

### 2.3 Configure Client Scopes

1. Go to **Client scopes** tab
2. Click on **rancher-dedicated**
3. **Mappers** tab → **Add mapper** → **By configuration**

#### Group Membership Mapper
```
Mapper type: Group Membership
Name: groups
Token Claim Name: groups
Full group path: OFF
Add to ID token: ON
Add to access token: ON
Add to userinfo: ON
```

#### User Attribute Mappers
```
Mapper type: User Attribute
Name: username
User Attribute: username
Token Claim Name: preferred_username
Claim JSON Type: String
Add to ID token: ON
Add to access token: ON
Add to userinfo: ON
```

## Step 3: Configure External Rancher Authentication

### 3.1 Access Your External Rancher

1. Navigate to your external Rancher instance: `https://rancher-k3s.local`
2. Login with local admin credentials
3. Go to **Users & Authentication** → **Auth Provider**

### 3.2 Configure Keycloak (OIDC) Authentication

1. Select **Keycloak (OIDC)**
2. Configure the settings:

```
Display Name Field: Keycloak SSO
Client ID: rancher
Client Secret: [your-rancher-client-secret]
Private Key / Certificate: (leave empty)

Endpoints:
Issuer: https://your-domain.com/auth/realms/master
Auth Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/auth
Token Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/token
User Info Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/userinfo

User Mapping:
Username Field: preferred_username
Display Name Field: name
User ID Field: sub
Groups Field: groups

Advanced Options:
Scopes: openid profile email groups
```

3. Click **Enable**
4. Test the configuration by clicking **Authenticate with Keycloak**

### 3.3 Configure User Permissions

After successful authentication test:

1. Go to **Users & Authentication** → **Users**
2. Find your Keycloak users and assign appropriate roles:
   - **Cluster Administrator**: For users in `admin` group
   - **Cluster Member**: For users in `modify` group
   - **Read Only**: For users in `view` group

## Step 4: Update Webapp Configuration

### 4.1 Update Flask App (if needed)

Add this to your webapp's `app.py` if you want to handle Rancher links:

```python
# Add to environment variables section
RANCHER_URL = os.environ.get('RANCHER_URL', f"https://{os.environ.get('RANCHER_EXTERNAL_HOST', 'rancher-k3s.local')}")
RANCHER_ENABLED = os.environ.get('RANCHER_ENABLED', 'true').lower() == 'true'

# Add to context processor
@app.context_processor
def inject_rancher_config():
    return {
        'rancher_url': RANCHER_URL,
        'rancher_enabled': RANCHER_ENABLED
    }
```

### 4.2 Update Templates

In your webapp templates, update Rancher links:

**admin.html**:
```html
<!-- Replace the Rancher service card -->
<div class="service-card" onclick="window.open('/rancher', '_blank')">
    <div class="service-icon">🐄</div>
    <div class="service-title">Rancher</div>
    <div class="service-description">
        External Kubernetes cluster management platform. Manage containerized applications,
        deployments, and cluster resources via Keycloak SSO.
    </div>
    <a href="/rancher" class="btn" target="_blank">Open Rancher</a>
</div>
```

## Step 5: Network Configuration

### 5.1 DNS Resolution

Ensure both hostnames resolve correctly:

```bash
# Add to /etc/hosts on your client machines
127.0.0.1 your-domain.com
127.0.0.1 rancher-k3s.local

# Or configure proper DNS records
```

### 5.2 SSL Certificates

For production, ensure both domains have valid SSL certificates:

```bash
# Option 1: Use the same certificate for both domains (SAN certificate)
# Option 2: Configure separate certificates
# Option 3: Use a wildcard certificate
```

## Step 6: Test the Integration

### 6.1 Test Direct Rancher Access

1. Navigate to `https://rancher-k3s.local`
2. Click **Login with Keycloak**
3. Should redirect to Keycloak login
4. Login with your demo users
5. Verify access based on group membership

### 6.2 Test Proxied Access

1. Navigate to `https://your-domain.com/rancher`
2. Should require authentication first
3. After webapp login, should proxy to Rancher
4. Verify single sign-on works

### 6.3 Test Role-Based Access

| User Group | Rancher Access Level |
|------------|---------------------|
| admin | Cluster Administrator - Full access |
| modify | Cluster Member - Limited cluster access |
| view | Read Only - View only access |

## Step 7: Troubleshooting

### Common Issues

#### Rancher Not Accessible via Proxy

**Check**:
```bash
# Test direct access to external Rancher
curl -k https://rancher-k3s.local

# Check nginx logs
docker logs holstein-nginx-proxy

# Test auth endpoint
curl https://your-domain.com/auth/verify?role=admin
```

#### Authentication Redirect Loop

**Check**:
1. Keycloak client redirect URIs include both domains
2. Rancher OIDC configuration uses correct issuer URL
3. SSL certificate trust between services

#### Group Permissions Not Working

**Check**:
1. Group mapper in Keycloak client
2. Groups field configuration in Rancher
3. User group membership in Keycloak

### Debug Commands

```bash
# Check if external Rancher is accessible
curl -k https://rancher-k3s.local/ping

# Test nginx proxy configuration
nginx -t

# Check webapp auth endpoint
curl -X GET "https://your-domain.com/auth/verify?role=admin" \
  -H "Cookie: session=your-session-cookie"

# View JWT token content (decode at jwt.io)
# Look for 'groups' claim
```

## Step 8: Security Considerations

### Production Recommendations

1. **SSL Certificates**: Use proper SSL certificates, not self-signed
2. **Network Segmentation**: Ensure external Rancher is properly firewalled
3. **Access Logs**: Monitor access to sensitive Rancher operations
4. **Regular Updates**: Keep Rancher and K3s updated

### Access Control

1. **Principle of Least Privilege**: Only grant necessary Rancher permissions
2. **Regular Audits**: Review user access and permissions
3. **Session Management**: Configure appropriate session timeouts
4. **Multi-Factor Authentication**: Consider enabling MFA for admin users

## Summary

This setup provides:

✅ **External Rancher Integration**: Connects to Rancher running on separate infrastructure
✅ **Single Sign-On**: Users authenticate once via Keycloak
✅ **Role-Based Access**: Different access levels based on user groups
✅ **Proxy Protection**: Rancher access controlled via nginx auth_request
✅ **Unified Interface**: All services accessible from single domain

Your monitoring stack now integrates with external Rancher while maintaining centralized authentication and access control through Keycloak.