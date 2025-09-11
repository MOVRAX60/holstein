# Keycloak Demo Users Setup Guide

This guide walks you through creating demo admin and modify users in Keycloak for testing your monitoring stack services.

## Prerequisites

- Keycloak running and accessible
- Admin access to Keycloak console
- Services deployed (webapp, Grafana, etc.)

## Step 1: Access Keycloak Admin Console

1. Navigate to: `https://your-domain.com/auth/admin`
2. Login with your Keycloak admin credentials:
   - Username: `admin`
   - Password: `[your KEYCLOAK_ADMIN_PASSWORD from .env]`

## Step 2: Create Groups (Role-Based Access)

### 2.1 Create Admin Group

1. In the left sidebar, click **Groups**
2. Click **Create group**
3. Fill in the details:
   ```
   Name: admin
   Description: Full administrative access to all services
   ```
4. Click **Create**

### 2.2 Create Modify Group

1. Click **Create group** again
2. Fill in the details:
   ```
   Name: modify
   Description: Editor access - can modify dashboards and configurations
   ```
3. Click **Create**

### 2.3 Create View Group (Optional)

1. Click **Create group** again
2. Fill in the details:
   ```
   Name: view
   Description: Read-only access to services
   ```
3. Click **Create**

## Step 3: Create Demo Admin User

### 3.1 Create the User

1. In the left sidebar, click **Users**
2. Click **Add user**
3. Fill in the user details:
   ```
   Username: demo-admin
   Email: admin@your-domain.com
   First name: Demo
   Last name: Administrator
   User enabled: ON
   Email verified: ON
   ```
4. Click **Create**

### 3.2 Set Password

1. Go to the **Credentials** tab
2. Click **Set password**
3. Enter password details:
   ```
   Password: AdminDemo123!
   Password confirmation: AdminDemo123!
   Temporary: OFF
   ```
4. Click **Set password**
5. Confirm by clicking **Set password** in the dialog

### 3.3 Assign to Admin Group

1. Go to the **Groups** tab
2. In the **Available Groups** section, select `admin`
3. Click **Join**
4. Verify `admin` appears in **Group Membership**

### 3.4 Set User Attributes (Optional)

1. Go to the **Attributes** tab
2. Add custom attributes:
   ```
   Key: department | Value: IT Operations
   Key: role | Value: administrator
   Key: access_level | Value: full
   ```
3. Click **Save**

## Step 4: Create Demo Modify User

### 4.1 Create the User

1. Click **Users** in the left sidebar
2. Click **Add user**
3. Fill in the user details:
   ```
   Username: demo-editor
   Email: editor@your-domain.com
   First name: Demo
   Last name: Editor
   User enabled: ON
   Email verified: ON
   ```
4. Click **Create**

### 4.2 Set Password

1. Go to the **Credentials** tab
2. Click **Set password**
3. Enter password details:
   ```
   Password: EditorDemo123!
   Password confirmation: EditorDemo123!
   Temporary: OFF
   ```
4. Click **Set password**

### 4.3 Assign to Modify Group

1. Go to the **Groups** tab
2. In the **Available Groups** section, select `modify`
3. Click **Join**
4. Verify `modify` appears in **Group Membership**

### 4.4 Set User Attributes (Optional)

1. Go to the **Attributes** tab
2. Add custom attributes:
   ```
   Key: department | Value: Development
   Key: role | Value: editor
   Key: access_level | Value: modify
   ```
3. Click **Save**

## Step 5: Configure Role Mapping in Clients

### 5.1 Update Grafana Client Scopes

1. Go to **Clients** → **grafana**
2. Click **Client scopes** tab
3. Click on **grafana-dedicated**
4. Go to **Mappers** tab
5. Click **Add mapper** → **By configuration** → **Group Membership**
6. Configure the mapper:
   ```
   Name: groups
   Token Claim Name: groups
   Full group path: OFF
   Add to ID token: ON
   Add to access token: ON
   Add to userinfo: ON
   ```
7. Click **Save**

### 5.2 Update WebApp Client Scopes

1. Go to **Clients** → **webapp**
2. Repeat the same group membership mapper configuration
3. This ensures your Flask webapp can read user groups

## Step 6: Test Demo Users

### 6.1 Test Demo Admin User

1. **WebApp Test**:
   - Navigate to `https://your-domain.com`
   - Login with: `demo-admin` / `AdminDemo123!`
   - Should have access to Admin Portal
   - Should see all monitoring services

2. **Grafana Test**:
   - Navigate to `https://your-domain.com/grafana`
   - Login via Keycloak SSO
   - Should have Admin role in Grafana
   - Can create/modify dashboards

3. **Other Services**:
   - Test Rancher, Wiki.js access
   - Should have full administrative privileges

### 6.2 Test Demo Modify User

1. **WebApp Test**:
   - Navigate to `https://your-domain.com`
   - Login with: `demo-editor` / `EditorDemo123!`
   - Should have access to Monitoring Portal (not Admin Portal)
   - Should see monitoring services

2. **Grafana Test**:
   - Navigate to `https://your-domain.com/grafana`
   - Login via Keycloak SSO
   - Should have Editor role in Grafana
   - Can modify dashboards but limited admin functions

## Step 7: Verify Role-Based Access

### 7.1 Check WebApp Access Levels

| User | Admin Portal | Monitoring Portal | Grafana Role | Rancher Access |
|------|-------------|------------------|--------------|----------------|
| demo-admin | ✅ Full Access | ✅ Full Access | Admin | ✅ Full Access |
| demo-editor | ❌ No Access | ✅ Full Access | Editor | ❌ Limited/No Access |

### 7.2 Test Specific Features

**Demo Admin Should Have**:
- Access to `/admin` route in webapp
- Grafana admin functions (user management, plugins)
- Rancher cluster management
- Wiki.js admin functions

**Demo Editor Should Have**:
- Access to `/monitoring` route only
- Grafana dashboard editing
- Wiki.js content editing
- Read access to Prometheus

**Demo Editor Should NOT Have**:
- Access to `/admin` route
- Grafana user management
- Rancher administrative functions
- System configuration changes

## Step 8: Troubleshooting

### 8.1 User Can't Login

**Check**:
1. User is enabled in Keycloak
2. Password is set and not temporary
3. Client redirect URIs are correct
4. Network connectivity to Keycloak

**Debug Commands**:
```bash
# Check Keycloak logs
docker-compose logs keycloak

# Test Keycloak connectivity
curl https://your-domain.com/auth/realms/master/.well-known/openid-configuration
```

### 8.2 Wrong Role Assignment

**Check**:
1. User group membership in Keycloak
2. Group mapper configuration in clients
3. Role mapping logic in applications

**Verify Group Membership**:
1. Go to **Users** → **demo-admin** → **Groups**
2. Ensure correct groups are assigned
3. Check **Effective Roles** tab

### 8.3 Services Not Recognizing Roles

**Check**:
1. Client scope mappers include group claims
2. Service configuration reads correct claim names
3. JWT token contains expected groups

**Debug JWT Token**:
1. Login to webapp
2. Open browser developer tools
3. Check JWT token content at https://jwt.io
4. Verify `groups` claim contains expected values

## Step 9: Additional Demo Users (Optional)

### 9.1 Create View-Only User

```
Username: demo-viewer
Password: ViewerDemo123!
Groups: view
Access: Read-only to all services
```

### 9.2 Create Department-Specific Users

```
Username: demo-it-admin
Groups: admin
Department: IT

Username: demo-dev-editor  
Groups: modify
Department: Development
```

## Security Notes

### Production Considerations

1. **Change default passwords** before production use
2. **Enable password policies** in Keycloak
3. **Set session timeouts** appropriately
4. **Enable account lockout** after failed attempts
5. **Use strong passwords** and consider MFA

### Demo Environment

1. **Clearly label** as demo accounts
2. **Limit access** to demo/test environments only
3. **Regular cleanup** of demo accounts
4. **Monitor usage** for security purposes

## Quick Reference

### Demo User Credentials

| Username | Password | Role | Access Level |
|----------|----------|------|--------------|
| demo-admin | AdminDemo123! | admin | Full administrative access |
| demo-editor | EditorDemo123! | modify | Editor access to dashboards |
| demo-viewer | ViewerDemo123! | view | Read-only access |

### Service URLs

- **WebApp**: `https://your-domain.com`
- **Grafana**: `https://your-domain.com/grafana`
- **Prometheus**: `https://your-domain.com/prometheus`
- **Rancher**: `https://your-domain.com/rancher`
- **Wiki.js**: `https://your-domain.com/wiki`
- **Keycloak Admin**: `https://your-domain.com/auth/admin`

### Test Scenarios

1. **Login to each service** with both demo accounts
2. **Verify role-based access** restrictions work
3. **Test single sign-on** between services
4. **Check logout** functionality
5. **Validate session timeouts**

This setup provides a complete demo environment for testing role-based access across your monitoring stack.