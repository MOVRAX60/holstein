# Basic Keycloak LDAP Integration Guide

## Overview

This guide walks you through setting up Keycloak with LDAP authentication for all services in your monitoring stack: Grafana, Prometheus, Rancher, Wiki.js, and your Flask webapp.

## Prerequisites

- Keycloak running and accessible
- LDAP/Active Directory server accessible
- Admin access to both Keycloak and LDAP
- All services deployed and running

## Step 1: Configure LDAP in Keycloak

### 1.1 Access Keycloak Admin Console

1. Navigate to `https://your-domain.com/auth/admin`
2. Login with admin credentials
3. Select your realm (create new if needed)

### 1.2 Add LDAP User Federation

1. Go to **User Federation** → **Add provider** → **ldap**
2. Configure basic settings:

```
Console Display Name: Company LDAP
Import Users: ON
Edit Mode: READ_ONLY
Vendor: Active Directory (or your LDAP type)
Connection URL: ldaps://your-ldap-server.com:636
Users DN: OU=Users,DC=company,DC=local
Bind DN: CN=service-account,OU=Service Accounts,DC=company,DC=local
Bind Credential: [service-account-password]
```

3. Click **Test connection** and **Test authentication**
4. Click **Save**

### 1.3 Synchronize Users

1. Go to **Synchronization** tab
2. Click **Sync all users**
3. Verify users appear in **Users** section

### 1.4 Configure Group Mapping

1. In LDAP provider, go to **Mappers** tab
2. Create new mapper:

```
Name: groups
Mapper Type: group-ldap-mapper
LDAP Groups DN: OU=Groups,DC=company,DC=local
Group Name LDAP Attribute: cn
Group Object Classes: group
Membership LDAP Attribute: member
Membership Attribute Type: DN
User Groups Retrieve Strategy: LOAD_GROUPS_BY_MEMBER_ATTRIBUTE_RECURSIVELY
```

3. Click **Save**
4. Click **Sync LDAP Groups to Keycloak**

## Step 2: Create Keycloak Clients

### 2.1 Grafana Client

1. Go to **Clients** → **Create client**
2. Configure:

```
Client type: OpenID Connect
Client ID: grafana
Name: Grafana Dashboard
Description: Grafana monitoring dashboard

Capability config:
Client authentication: ON
Authorization: OFF
Standard flow: ON
Direct access grants: OFF
Implicit flow: OFF
Service accounts roles: OFF
```

3. **Settings** tab:
```
Valid redirect URIs: https://your-domain.com/grafana/login/generic_oauth
Valid post logout redirect URIs: https://your-domain.com/grafana/logout
Web origins: https://your-domain.com
```

4. **Credentials** tab - copy the **Client secret**

### 2.2 Rancher Client

1. Create new client:
```
Client ID: rancher
Client authentication: ON
Standard flow: ON
Valid redirect URIs: https://your-domain.com/rancher/verify-auth
```

### 2.3 Wiki.js Client

1. Create new client:
```
Client ID: wikijs
Client authentication: ON
Standard flow: ON
Valid redirect URIs: https://your-domain.com/wiki/login/*
```

### 2.4 WebApp Client

1. Create new client:
```
Client ID: webapp
Client authentication: ON
Standard flow: ON
Direct access grants: ON (for direct login)
Valid redirect URIs: https://your-domain.com/callback
```

## Step 3: Configure Role Mappings

### 3.1 Create Keycloak Roles

1. Go to **Realm roles** → **Create role**
2. Create these roles:

```
admin - Full administrative access
modify - Editor access for dashboards
view - Read-only access
```

### 3.2 Map LDAP Groups to Roles

1. Go to **Groups**
2. For each group, assign appropriate roles:

```
LDAP Group "Domain Admins" → Keycloak role "admin"
LDAP Group "IT Staff" → Keycloak role "modify"  
LDAP Group "All Users" → Keycloak role "view"
```

### 3.3 Configure Client Scope Mappers

For each client, add role mapping:

1. Go to **Clients** → [client-name] → **Client scopes**
2. Click on **[client-name]-dedicated**
3. **Mappers** tab → **Add mapper** → **By configuration** → **User Realm Role**

```
Name: realm-roles
Mapper Type: User Realm Role
Token Claim Name: roles
Claim JSON Type: String
Add to ID token: ON
Add to access token: ON
Add to userinfo: ON
```

## Step 4: Configure Service Authentication

### 4.1 Update Grafana Configuration

Add to your `config/grafana/grafana.ini`:

```ini
[auth.generic_oauth]
enabled = true
name = Keycloak
allow_sign_up = true
client_id = grafana
client_secret = [grafana-client-secret]
scopes = openid profile email roles
empty_scopes = false
auth_url = https://your-domain.com/auth/realms/master/protocol/openid-connect/auth
token_url = https://your-domain.com/auth/realms/master/protocol/openid-connect/token
api_url = https://your-domain.com/auth/realms/master/protocol/openid-connect/userinfo
signout_redirect_url = https://your-domain.com/auth/realms/master/protocol/openid-connect/logout
role_attribute_path = contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'modify') && 'Editor' || 'Viewer'
allow_assign_grafana_admin = true
skip_org_role_sync = false
```

Or via environment variables in docker-compose.yml:

```yaml
grafana:
  environment:
    - GF_AUTH_GENERIC_OAUTH_ENABLED=true
    - GF_AUTH_GENERIC_OAUTH_NAME=Keycloak
    - GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true
    - GF_AUTH_GENERIC_OAUTH_CLIENT_ID=grafana
    - GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${GRAFANA_CLIENT_SECRET}
    - GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email roles
    - GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://${DOMAIN}/auth/realms/master/protocol/openid-connect/auth
    - GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://${DOMAIN}/auth/realms/master/protocol/openid-connect/token
    - GF_AUTH_GENERIC_OAUTH_API_URL=https://${DOMAIN}/auth/realms/master/protocol/openid-connect/userinfo
    - GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'modify') && 'Editor' || 'Viewer'
```

### 4.2 Configure Wiki.js Authentication

1. Login to Wiki.js admin at `https://your-domain.com/wiki/a`
2. Go to **Authentication** → **OpenID Connect**
3. Configure:

```
Configuration:
Client ID: wikijs
Client Secret: [wikijs-client-secret]
Authorization Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/auth
Token Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/token
User Info Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/userinfo
Issuer: https://your-domain.com/auth/realms/master
Logout URL: https://your-domain.com/auth/realms/master/protocol/openid-connect/logout

User Mapping:
Unique ID Field: sub
Display Name Field: name
Email Field: email

Group Mapping:
Groups Claim: roles
Admin Group: admin
```

### 4.3 Configure Rancher Authentication

1. Login to Rancher at `https://your-domain.com/rancher`
2. Go to **Users & Authentication** → **Auth Provider**
3. Select **Keycloak (OIDC)**
4. Configure:

```
Display Name Field: Keycloak
Client ID: rancher
Client Secret: [rancher-client-secret]
Private Key / Certificate: (leave empty)
Issuer: https://your-domain.com/auth/realms/master
Auth Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/auth
Token Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/token
User Info Endpoint: https://your-domain.com/auth/realms/master/protocol/openid-connect/userinfo
```

### 4.4 Configure Flask WebApp

Your Flask app should already be configured from the docker-compose.yml, but verify these environment variables:

```yaml
webapp:
  environment:
    - KEYCLOAK_URL=http://keycloak:8080/auth
    - KEYCLOAK_REALM=master
    - KEYCLOAK_CLIENT_ID=webapp
    - KEYCLOAK_CLIENT_SECRET=${WEBAPP_CLIENT_SECRET}
```

### 4.5 Configure Prometheus (Basic Auth Proxy)

Since Prometheus doesn't support OIDC natively, we'll use nginx auth_request:

Add to your nginx configuration:

```nginx
location /prometheus/ {
    auth_request /auth/verify?role=view;
    
    proxy_pass http://prometheus:9090/prometheus/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# Auth endpoint for Prometheus
location = /auth/verify {
    internal;
    proxy_pass http://webapp:8000/auth/verify;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URI $request_uri;
}
```

## Step 5: Update Environment Variables

Add these to your `.env` file:

```bash
# Keycloak Client Secrets
GRAFANA_CLIENT_SECRET=your-grafana-client-secret
RANCHER_CLIENT_SECRET=your-rancher-client-secret
WIKIJS_CLIENT_SECRET=your-wikijs-client-secret
WEBAPP_CLIENT_SECRET=your-webapp-client-secret

# LDAP Service Account
LDAP_BIND_DN=CN=service-account,OU=Service Accounts,DC=company,DC=local
LDAP_BIND_PASSWORD=your-service-account-password
```

## Step 6: Test Authentication

### 6.1 Test Each Service

1. **Grafana**: `https://your-domain.com/grafana`
   - Should redirect to Keycloak login
   - Login with LDAP credentials
   - Verify role assignment (Admin/Editor/Viewer)

2. **Wiki.js**: `https://your-domain.com/wiki`
   - Click login, should show Keycloak option
   - Login with LDAP credentials
   - Verify access based on role

3. **Rancher**: `https://your-domain.com/rancher`
   - Should redirect to Keycloak login
   - Login with LDAP credentials
   - Verify cluster access

4. **WebApp**: `https://your-domain.com`
   - Try both direct login and SSO
   - Verify role-based access to admin portal

5. **Prometheus**: `https://your-domain.com/prometheus`
   - Should require authentication through webapp
   - Access granted based on 'view' role

### 6.2 Test Role-Based Access

Create test users in different LDAP groups:

```
Test User 1: Member of "Domain Admins" → Should get admin access everywhere
Test User 2: Member of "IT Staff" → Should get modify/editor access
Test User 3: Member of "All Users" → Should get view-only access
```

## Step 7: Troubleshooting

### Common Issues

#### LDAP Connection Fails
```bash
# Test LDAP connectivity
ldapsearch -H ldaps://your-ldap-server.com:636 \
  -D "CN=service-account,OU=Service Accounts,DC=company,DC=local" \
  -W \
  -b "DC=company,DC=local" \
  "(objectClass=user)"
```

#### Users Can't Login to Service
1. Check Keycloak logs: `docker logs holstein-keycloak`
2. Verify client redirect URIs are correct
3. Check client secrets match between Keycloak and service
4. Verify user has appropriate roles assigned

#### Roles Not Mapping Correctly
1. Check group mapper configuration in Keycloak
2. Verify LDAP group DNs are correct
3. Test role claim in JWT token at https://jwt.io

#### Service Shows "Access Denied"
1. Check role mapping in service configuration
2. Verify user has required role in Keycloak
3. Check nginx auth_request configuration (for Prometheus)

### Debug Tools

#### Test JWT Token Content
```bash
# Get token from browser developer tools, then decode at https://jwt.io
# Check if roles claim contains expected values
```

#### Test Keycloak Endpoints
```bash
# Test auth endpoint
curl "https://your-domain.com/auth/realms/master/.well-known/openid-configuration"

# Test user info endpoint (with valid token)
curl -H "Authorization: Bearer [token]" \
  "https://your-domain.com/auth/realms/master/protocol/openid-connect/userinfo"
```

## Step 8: Optional Enhancements

### 8.1 Custom Login Theme

Create custom Keycloak theme for branding consistency across services.

### 8.2 Session Management

Configure session timeouts in Keycloak:
- **Realm Settings** → **Tokens**
- Set appropriate session idle and max times

### 8.3 Single Logout

Configure single logout URLs for each client to enable logout from all services simultaneously.

### 8.4 Advanced Role Mapping

Create more granular roles for specific service features:

```
grafana-admin → Full Grafana admin
grafana-editor → Grafana dashboard editor  
prometheus-admin → Prometheus configuration access
rancher-cluster-admin → Rancher cluster management
wiki-editor → Wiki content editing
```

## Quick Reference

### Service URLs
- **Keycloak Admin**: `https://your-domain.com/auth/admin`
- **Grafana**: `https://your-domain.com/grafana`
- **Prometheus**: `https://your-domain.com/prometheus`
- **Rancher**: `https://your-domain.com/rancher`
- **Wiki.js**: `https://your-domain.com/wiki`
- **WebApp**: `https://your-domain.com`

### Default Role Mapping
- **admin** role → Full access to all services
- **modify** role → Editor access (can modify dashboards, content)
- **view** role → Read-only access

### Client IDs
- Grafana: `grafana`
- Rancher: `rancher`
- Wiki.js: `wikijs`
- WebApp: `webapp`

This basic setup provides LDAP authentication across all services with role-based access control. Users login once with their LDAP credentials and get appropriate access to each service based on their group membership.