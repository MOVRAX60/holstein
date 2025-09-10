# Keycloak 23.0 LDAP/AD Configuration Guide - NIST 800-171 Compliant

## Table of Contents
1. [NIST 800-171 Compliance Overview](#nist-800-171-compliance-overview)
2. [Initial Setup and Security Hardening](#initial-setup-and-security-hardening)
3. [LDAP/Active Directory Integration](#ldapactive-directory-integration)
4. [Access Control Implementation](#access-control-implementation)
5. [Authentication and Authorization](#authentication-and-authorization)
6. [Session Management and Security](#session-management-and-security)
7. [Audit and Event Logging](#audit-and-event-logging)
8. [Multi-Factor Authentication](#multi-factor-authentication)
9. [Certificate and Encryption Management](#certificate-and-encryption-management)
10. [Compliance Verification](#compliance-verification)

## NIST 800-171 Compliance Overview

### Relevant NIST 800-171 Controls for Identity Management

**3.1.1 - Access Control**: Limit system access to authorized users, processes, and devices
**3.1.2 - Account Management**: Manage information system accounts
**3.1.3 - Access Enforcement**: Control access between users and objects
**3.5.1 - Authentication**: Identify and authenticate users
**3.5.2 - Multi-factor Authentication**: Use multi-factor authentication for privileged accounts
**3.5.3 - Session Timeout**: Automatically timeout sessions
**3.3.1 - Event Logging**: Create and maintain audit logs
**3.13.1 - Boundary Protection**: Monitor and control communications at system boundaries

## Initial Setup and Security Hardening

### 1.1 Keycloak Production Configuration

Update your docker-compose.yml for NIST compliance:

```yaml
keycloak:
  image: quay.io/keycloak/keycloak:${KEYCLOAK_VERSION:-23.0}
  container_name: keycloak
  restart: unless-stopped
  environment:
    - KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
    - KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
    # Production mode for NIST compliance
    - KC_HOSTNAME=${DOMAIN}
    - KC_HOSTNAME_STRICT=true
    - KC_HOSTNAME_STRICT_HTTPS=true
    - KC_HTTP_ENABLED=false
    - KC_HTTPS_PORT=8443
    - KC_HTTP_RELATIVE_PATH=/auth
    - KC_PROXY=edge
    - KC_FRONTEND_URL=https://${DOMAIN}/auth
    # Security hardening
    - KC_LOG_LEVEL=INFO
    - KC_METRICS_ENABLED=true
    - KC_HEALTH_ENABLED=true
    # Database configuration for audit persistence
    - KC_DB=postgres
    - KC_DB_URL=jdbc:postgresql://keycloak-db:5432/${KEYCLOAK_DB_NAME:-keycloak}
    - KC_DB_USERNAME=${KEYCLOAK_DB_USER:-keycloak}
    - KC_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD}
  command:
    - start
    - --optimized
    - --hostname=${DOMAIN}
    - --hostname-strict=true
    - --hostname-strict-https=true
    - --proxy=edge
    - --frontend-url=https://${DOMAIN}/auth
  volumes:
    - ./keycloak/conf:/opt/keycloak/conf:ro
    - ./keycloak/providers:/opt/keycloak/providers:ro
  networks:
    - ${NETWORK_NAME:-monitoring}
```

### 1.2 Realm Security Configuration

Navigate to **Realm Settings** > **Security Defenses**:

```
Security Headers (NIST 3.13.1 - Boundary Protection):
- X-Frame-Options: DENY
- Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; object-src 'none';
- X-Content-Type-Options: nosniff
- X-Robots-Tag: none
- X-XSS-Protection: 1; mode=block
- Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
- Referrer-Policy: strict-origin-when-cross-origin

Brute Force Detection (NIST 3.1.8 - Session Lock):
- Enabled: True
- Permanent Lockout: False
- Max Login Failures: 3
- Wait Increment: 60 seconds
- Quick Login Check: 1000 milliseconds
- Minimum Quick Login Wait: 60 seconds
- Max Wait: 15 minutes
- Failure Factor: 30
```

## LDAP/Active Directory Integration

### 2.1 LDAP User Federation Setup

Navigate to **User Federation** > **Add Provider** > **ldap**:

#### 2.1.1 Connection Settings

```
Console Display Name: Corporate Active Directory
Priority: 0
Import Mode: READ_ONLY (NIST 3.1.2 - Account Management)

Connection URL: ldaps://dc.company.com:636
Enable StartTLS: false (using LDAPS)
Use Truststore SPI: Only for LDAPS
Connection Pooling: true
Connection Timeout: 10000
Read Timeout: 30000

Bind Type: simple
Bind DN: CN=keycloak-service,OU=Service Accounts,DC=company,DC=com
Bind Credential: [Service Account Password]

Test Connection: [Test before saving]
Test Authentication: [Test before saving]
```

#### 2.1.2 LDAP Search Settings

```
User DN: OU=Users,DC=company,DC=com
Username LDAP Attribute: sAMAccountName
RDN LDAP Attribute: cn
UUID LDAP Attribute: objectGUID
User Object Classes: person, organizationalPerson, user

Custom User Search Filter: (&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))
Search Scope: Subtree

Pagination: true
```

#### 2.1.3 LDAP Attribute Mappings

Create these attribute mappers:

**Email Mapper:**
```
Name: email
LDAP Attribute: mail
User Model Attribute: email
Read Only: true
Always Read Value From LDAP: true
```

**First Name Mapper:**
```
Name: first name
LDAP Attribute: givenName
User Model Attribute: firstName
Read Only: true
Always Read Value From LDAP: true
```

**Last Name Mapper:**
```
Name: last name
LDAP Attribute: sn
User Model Attribute: lastName
Read Only: true
Always Read Value From LDAP: true
```

**Display Name Mapper:**
```
Name: display name
LDAP Attribute: displayName
User Model Attribute: displayName
Read Only: true
Always Read Value From LDAP: true
```

### 2.2 LDAP Group Mapping

Navigate to **User Federation** > **[Your LDAP]** > **Mappers** > **Create**:

#### 2.2.1 Group LDAP Mapper

```
Name: group-ldap-mapper
Mapper Type: group-ldap-mapper
LDAP Groups DN: OU=Security Groups,DC=company,DC=com
Group Name LDAP Attribute: cn
Group Object Classes: group
Preserve Group Inheritance: true
Ignore Missing Groups: false
Membership LDAP Attribute: member
Membership Attribute Type: DN
Membership User LDAP Attribute: distinguishedName
Groups Retrieve Strategy: LOAD_GROUPS_BY_MEMBER_ATTRIBUTE
Member-Of LDAP Attribute: memberOf
Mapped Group Attributes: 
User Groups Retrieve Strategy: LOAD_GROUPS_BY_MEMBER_ATTRIBUTE
```

#### 2.2.2 Security Group Mappings

Map Active Directory security groups to Keycloak roles:

```
AD Group: "Domain Admins" → Keycloak Role: "admin"
AD Group: "Monitoring Admins" → Keycloak Role: "admin"
AD Group: "Monitoring Editors" → Keycloak Role: "modify"
AD Group: "Monitoring Viewers" → Keycloak Role: "view"
AD Group: "Privileged Users" → Keycloak Role: "privileged"
```

## Access Control Implementation

### 3.1 Role-Based Access Control (NIST 3.1.1, 3.1.3)

#### 3.1.1 Realm Roles Configuration

Navigate to **Realm Roles** > **Create Role**:

```
admin:
- Role Name: admin
- Description: Full administrative access - CUI authorized personnel
- Composite: false
- Client Roles: Include all monitoring client roles

modify:
- Role Name: modify
- Description: Monitoring data modification access - CUI authorized personnel
- Composite: false

view:
- Role Name: view
- Description: Read-only monitoring access - CUI authorized personnel
- Composite: false

privileged:
- Role Name: privileged
- Description: Privileged account requiring MFA - CUI authorized personnel
- Composite: false
```

#### 3.1.2 Client-Specific Roles

For each client (webapp, grafana), create specific roles:

**Webapp Client Roles:**
```
webapp-admin: Full webapp administrative access
webapp-user: Standard webapp user access
webapp-readonly: Read-only webapp access
```

**Grafana Client Roles:**
```
grafana-admin: Grafana administrator
grafana-editor: Dashboard editor
grafana-viewer: Dashboard viewer
```

### 3.2 Conditional Access Policies

Navigate to **Authentication** > **Required Actions**:

Enable and configure:
```
Configure OTP: ENABLED (Required for privileged accounts - NIST 3.5.2)
Terms and Conditions: ENABLED
Update Password: ENABLED
Update Profile: DISABLED (LDAP-managed)
Verify Email: DISABLED (LDAP-managed)
```

## Authentication and Authorization

### 4.1 Password Policy (NIST 3.5.7 - Password Management)

Navigate to **Authentication** > **Password Policy**:

```
NIST 800-171 Compliant Password Policy:
- Minimum Length: 14
- Maximum Length: 128
- Not Recently Used: 24
- Not Username: ON
- Not Email: ON
- Blacklist: ON (use common password blacklist)
- Special Characters: 1
- Uppercase Characters: 1
- Lowercase Characters: 1
- Digits: 1
- Regular Expression: ^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]
- Password History: 24
- Force Expired Password Change: ON
```

### 4.2 Authentication Flows (NIST 3.5.1, 3.5.2)

#### 4.2.1 Browser Flow with MFA

Navigate to **Authentication** > **Flows** > **Create Flow**:

```
Flow Name: NIST-Compliant-Browser-Flow
Flow Type: basic-flow

Steps:
1. Cookie (ALTERNATIVE)
2. Identity Provider Redirector (ALTERNATIVE)
3. LDAP-MFA-Forms (ALTERNATIVE - SUBFLOW):
   a. Username Password Form (REQUIRED)
   b. Conditional OTP (CONDITIONAL):
      - Condition: User Role - privileged, admin
      - OTP Form (REQUIRED)
4. Reset Credentials (DISABLED)
```

#### 4.2.2 Conditional MFA Configuration

Navigate to **Authentication** > **Flows** > **NIST-Compliant-Browser-Flow** > **Conditional OTP**:

```
Condition Configuration:
- User Role: privileged, admin
- Force OTP for Role: ON
- Default OTP Outcome: SKIP
- OTP Control User Attribute: 
```

### 4.3 Session Management (NIST 3.1.11 - Session Timeout)

Navigate to **Realm Settings** > **Sessions**:

```
NIST 800-171 Session Settings:
- SSO Session Idle: 15 minutes (NIST requirement for CUI systems)
- SSO Session Max: 8 hours (Maximum work day)
- Client Session Idle: 15 minutes
- Client Session Max: 8 hours
- Offline Session Idle: 30 days
- Offline Session Max: 90 days
- Login Timeout: 5 minutes
- Action Token Lifetime: 5 minutes

Remember Me:
- Enabled: false (NIST compliance requirement)
```

## Multi-Factor Authentication

### 5.1 OTP Configuration (NIST 3.5.2)

Navigate to **Authentication** > **OTP Policy**:

```
OTP Settings:
- OTP Type: Time-Based (TOTP)
- OTP Hash Algorithm: SHA256
- Number of Digits: 6
- Look Ahead Window: 1
- Initial Counter: 0
- Period: 30 seconds
- Supported Applications: Google Authenticator, Microsoft Authenticator, Authy
```

### 5.2 WebAuthn Configuration (NIST 3.5.2)

Navigate to **Authentication** > **WebAuthn Policy**:

```
WebAuthn Settings:
- Relying Party Entity Name: Monitoring Portal
- Relying Party ID: rancher.local
- Attestation Conveyance Preference: not specified
- Authenticator Attachment: not specified
- Require Resident Key: not specified
- User Verification Requirement: preferred
- Timeout: 60000
- Avoid Same Authenticator Registration: false
- Acceptable AAGUIDs: (leave empty for all)
```

## Audit and Event Logging

### 6.1 Event Configuration (NIST 3.3.1 - Audit Events)

Navigate to **Realm Settings** > **Events**:

```
Login Events Settings:
- Save Events: ON
- Expiration: 365 days (minimum for NIST compliance)
- Event Listeners: jboss-logging, email

Events to Log:
- LOGIN
- LOGIN_ERROR
- LOGOUT
- REGISTER
- UPDATE_PROFILE
- UPDATE_PASSWORD
- UPDATE_EMAIL
- VERIFY_EMAIL
- REMOVE_TOTP
- UPDATE_TOTP
- CODE_TO_TOKEN
- CLIENT_LOGIN
- PERMISSION_TOKEN
- IMPERSONATE
- CUSTOM_REQUIRED_ACTION
```

```
Admin Events Settings:
- Save Admin Events: ON
- Include Representation: ON
- Event Listeners: jboss-logging

Admin Events to Log:
- All administrative actions (automatic)
```

### 6.2 External Audit Integration

Configure external SIEM integration for NIST compliance:

#### 6.2.1 Syslog Configuration

Create `/opt/keycloak/conf/keycloak.conf`:

```
# Audit logging configuration for NIST 800-171
log-level=INFO
log-console-format=%d{HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n
log-file=/var/log/keycloak/keycloak.log
log-file-format=%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n

# Audit events
spi-events-listener-jboss-logging-success-level=INFO
spi-events-listener-jboss-logging-error-level=WARN
```

#### 6.2.2 Custom Event Listener

For SIEM integration, configure custom event listener to send audit logs to external systems.

## Certificate and Encryption Management

### 7.1 TLS Configuration (NIST 3.13.8 - Transmission Confidentiality)

Ensure all communication is encrypted:

```
nginx TLS Configuration:
- TLS 1.2 minimum (TLS 1.3 preferred)
- Strong cipher suites only
- Perfect Forward Secrecy
- HSTS headers
- Certificate pinning where possible
```

### 7.2 Token Encryption

Navigate to **Realm Settings** > **Tokens**:

```
Token Settings:
- Access Token Lifespan: 5 minutes
- Access Token Lifespan For Implicit Flow: 5 minutes
- Client login timeout: 5 minutes
- Login timeout: 5 minutes
- Login action timeout: 5 minutes
- User-Initiated Action Lifespan: 5 minutes
- Default Signature Algorithm: RS256
- Revoke Refresh Token: ON
- Refresh Token Max Reuse: 0
```

## Compliance Verification

### 8.1 NIST 800-171 Control Verification

#### 8.1.1 Access Control Verification (3.1.x)

```bash
# Verify user authentication against LDAP
curl -X POST https://rancher.local/auth/realms/monitoring/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=webapp&client_secret=${WEBAPP_CLIENT_SECRET}&username=testuser&password=password"

# Verify session timeout enforcement
# Monitor session expiration in Keycloak admin console

# Verify account lockout after failed attempts
# Attempt login with wrong password 3 times
```

#### 8.1.2 Audit Event Verification (3.3.1)

```bash
# Check audit log format and content
docker compose exec keycloak cat /var/log/keycloak/keycloak.log | grep LOGIN

# Verify admin events are logged
# Check Keycloak admin console > Events > Admin Events

# Test audit log integrity and retention
```

#### 8.1.3 Multi-Factor Authentication Verification (3.5.2)

```bash
# Verify MFA requirement for privileged accounts
# Login as admin user - should require OTP
# Login as regular user - should not require OTP

# Test WebAuthn if configured
# Verify FIDO2 key registration and authentication
```

### 8.2 Security Assessment Checklist

```
NIST 800-171 Compliance Checklist:

Access Control (3.1):
[ ] 3.1.1 - User access limited to authorized personnel only
[ ] 3.1.2 - Account management through LDAP integration
[ ] 3.1.3 - Role-based access control implemented
[ ] 3.1.5 - Privilege separation implemented (admin vs user roles)
[ ] 3.1.11 - Session lock after 15 minutes of inactivity
[ ] 3.1.12 - Session termination after max session time

Audit and Accountability (3.3):
[ ] 3.3.1 - Audit records created and maintained
[ ] 3.3.2 - Audit events reviewed regularly
[ ] 3.3.4 - Audit log protected from unauthorized access
[ ] 3.3.8 - Time stamps on audit records
[ ] 3.3.9 - Audit record protection from alteration

Identification and Authentication (3.5):
[ ] 3.5.1 - Users identified and authenticated
[ ] 3.5.2 - MFA implemented for privileged accounts
[ ] 3.5.3 - Session authentication maintained
[ ] 3.5.7 - Password complexity requirements enforced
[ ] 3.5.8 - Password reuse prevention (24 passwords)
[ ] 3.5.9 - Password encryption in storage and transmission
[ ] 3.5.10 - Session timeout configuration

System and Communications Protection (3.13):
[ ] 3.13.1 - Boundary protection implemented
[ ] 3.13.8 - Cryptographic protection for CUI transmission
[ ] 3.13.10 - Cryptographic key management
[ ] 3.13.11 - Cryptographic protection for CUI at rest
```

### 8.3 Ongoing Compliance Monitoring

#### 8.3.1 Regular Security Reviews

```
Weekly Tasks:
- Review failed login attempts
- Check for locked accounts
- Monitor privileged account activity
- Verify audit log integrity

Monthly Tasks:
- Review user access permissions
- Audit role assignments
- Check for dormant accounts
- Verify MFA enrollment for privileged accounts
- Update security group mappings

Quarterly Tasks:
- Full security assessment
- Password policy review
- Certificate renewal planning
- Disaster recovery testing
- NIST control re-verification
```

#### 8.3.2 Automated Compliance Monitoring

Create monitoring scripts for continuous compliance:

```bash
#!/bin/bash
# nist-compliance-check.sh

# Check session timeout configuration
echo "Checking session timeout settings..."
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://rancher.local/auth/admin/realms/monitoring | \
  jq '.ssoSessionIdleTimeout, .ssoSessionMaxLifespan'

# Check password policy compliance
echo "Checking password policy..."
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://rancher.local/auth/admin/realms/monitoring | \
  jq '.passwordPolicy'

# Check MFA enrollment for privileged users
echo "Checking MFA enrollment..."
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://rancher.local/auth/admin/realms/monitoring/users | \
  jq '.[] | select(.realmRoles | contains(["admin", "privileged"])) | {username, totpConfigured: .totp}'

# Verify audit logging is active
echo "Checking audit configuration..."
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://rancher.local/auth/admin/realms/monitoring/events/config | \
  jq '{eventsEnabled, adminEventsEnabled, eventsExpiration}'
```

This configuration ensures your Keycloak setup meets NIST 800-171 requirements while integrating with your existing LDAP/Active Directory infrastructure. The setup provides comprehensive audit trails, strong authentication controls, and proper session management required for CUI (Controlled Unclassified Information) systems.

Remember to regularly review and update these configurations as NIST guidance evolves and your organizational security requirements change.