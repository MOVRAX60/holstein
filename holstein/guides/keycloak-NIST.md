# Keycloak LDAP Integration Guide - NIST 800-171 Compliant

## Overview

This guide provides detailed instructions for configuring Keycloak with LDAP authentication while maintaining compliance with NIST 800-171 requirements for protecting Controlled Unclassified Information (CUI).

## NIST 800-171 Compliance Mapping

| NIST Control | Requirement | Keycloak Implementation |
|--------------|-------------|------------------------|
| AC.1.1 | Limit system access to authorized users | LDAP user synchronization with role mapping |
| AC.1.5 | Employ principle of least privilege | Role-based access control (RBAC) |
| IA.1.1 | Identify system users | LDAP username/email identification |
| IA.1.2 | Authenticate user identities | LDAP authentication with password policies |
| IA.1.3 | Use multifactor authentication | TOTP/SMS 2FA configuration |
| IA.1.6 | Disable inactive identifiers | Account lockout and session timeout |
| IA.1.7 | Enforce password complexity | LDAP password policy enforcement |
| IA.1.10 | Store/transmit protected passwords | LDAPS (LDAP over SSL) |

## Prerequisites

### System Requirements
- Keycloak 23.0+ running
- LDAP/Active Directory server accessible
- SSL certificates for LDAPS
- Administrative access to both systems

### NIST 800-171 Prerequisites
- Documented access control policies
- Password complexity requirements defined
- Audit logging mechanisms in place
- Incident response procedures

## Step 1: LDAP Server Preparation

### 1.1 Verify LDAP Configuration

```bash
# Test LDAP connectivity (replace with your LDAP server details)
ldapsearch -H ldaps://ldap.company.local:636 \
  -D "CN=keycloak-svc,OU=Service Accounts,DC=company,DC=local" \
  -W \
  -b "DC=company,DC=local" \
  "(objectClass=user)"
```

### 1.2 Create Service Account (NIST AC.1.5 - Least Privilege)

Create a dedicated service account with minimal required permissions:

```ldif
# LDAP Service Account
dn: CN=keycloak-svc,OU=Service Accounts,DC=company,DC=local
objectClass: user
cn: keycloak-svc
sAMAccountName: keycloak-svc
userPrincipalName: keycloak-svc@company.local
description: Keycloak LDAP integration service account
userAccountControl: 66048
```

Required permissions for service account:
- Read access to user objects
- Read access to group memberships
- No write permissions (read-only principle)

### 1.3 SSL Certificate Configuration (NIST IA.1.10)

Ensure LDAPS is configured with valid certificates:

```bash
# Test LDAPS connectivity
openssl s_client -connect ldap.company.local:636 -verify_return_error
```

## Step 2: Keycloak LDAP Configuration

### 2.1 Access Keycloak Admin Console

1. Navigate to: `https://your-domain.com/auth/admin`
2. Login with admin credentials
3. Select your realm (or create new realm for NIST compliance)

### 2.2 Create LDAP User Federation

#### Basic Configuration

1. Go to **User Federation** → **Add provider** → **ldap**
2. Configure the following settings:

```
General Settings:
- Console Display Name: Company LDAP
- Priority: 0
- Import Users: ON (for initial sync)
- Edit Mode: READ_ONLY (NIST compliance - prevent unauthorized changes)
- Sync Registrations: OFF
- Vendor: Active Directory (or other)
- Username LDAP attribute: sAMAccountName
- RDN LDAP attribute: cn
- UUID LDAP attribute: objectGUID
- User Object Classes: person, organizationalPerson, user
- Connection URL: ldaps://ldap.company.local:636
- Users DN: OU=Users,DC=company,DC=local
- Authentication Type: simple
- Bind DN: CN=keycloak-svc,OU=Service Accounts,DC=company,DC=local
- Bind Credential: [service_account_password]
```

#### NIST 800-171 Specific Settings

```
Search Scope: Subtree
Connection Pooling: ON
Connection Timeout: 10000
Read Timeout: 30000
Trust Email: ON (IA.1.1 - User Identification)
```

#### Advanced Settings for Compliance

```
Enable StartTLS: OFF (using LDAPS instead)
Use Truststore SPI: Only for LDAPS
Connection Pooling: ON
Connection Pool Authentication: simple
Connection Pool Initial Size: 1
Connection Pool Maximum Size: 20
Connection Pool Preferred Size: 5
Connection Pool Protocol: ssl
```

### 2.3 Test LDAP Connection

1. Click **Test connection** button
2. Click **Test authentication** button
3. Verify both tests pass

### 2.4 Configure User Synchronization

#### Sync Settings (NIST AC.1.1)

```
Periodic Changed Users Sync: ON
Period: 86400 (24 hours)
Periodic Full Sync: ON  
Period: 604800 (7 days)
Cache Policy: DEFAULT
```

#### Custom User LDAP Filter (Optional)

```
# Example: Only sync active users from specific OUs
(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(|(ou=Employees)(ou=Contractors)))
```

## Step 3: LDAP Mappers Configuration

### 3.1 Default Attribute Mappers

Verify and configure these essential mappers:

#### Username Mapper
```
Name: username
Mapper Type: user-attribute-ldap-mapper
User Model Attribute: username
LDAP Attribute: sAMAccountName
Read Only: ON
Always Read Value From LDAP: ON
Is Mandatory in LDAP: ON
```

#### Email Mapper (NIST IA.1.1)
```
Name: email
Mapper Type: user-attribute-ldap-mapper
User Model Attribute: email
LDAP Attribute: mail
Read Only: ON
Always Read Value From LDAP: ON
Is Mandatory in LDAP: OFF
```

#### First Name Mapper
```
Name: first name
Mapper Type: user-attribute-ldap-mapper
User Model Attribute: firstName
LDAP Attribute: givenName
Read Only: ON
Always Read Value From LDAP: ON
```

#### Last Name Mapper
```
Name: last name
Mapper Type: user-attribute-ldap-mapper
User Model Attribute: lastName
LDAP Attribute: sn
Read Only: ON
Always Read Value From LDAP: ON
```

### 3.2 Group Mappers (NIST AC.1.5 - Least Privilege)

#### LDAP Groups to Keycloak Groups
```
Name: group-mapper
Mapper Type: group-ldap-mapper
LDAP Groups DN: OU=Security Groups,DC=company,DC=local
Group Name LDAP Attribute: cn
Group Object Classes: group
Preserve Group Inheritance: ON
Ignore Missing Groups: OFF
Membership LDAP Attribute: member
Membership Attribute Type: DN
Membership User LDAP Attribute: distinguishedName
Groups Retrieval Mode: LOAD_GROUPS_BY_MEMBER_ATTRIBUTE
User Groups Retrieve Strategy: LOAD_GROUPS_BY_MEMBER_ATTRIBUTE_RECURSIVELY
```

#### Role Mappers for RBAC
```
Name: admin-role-mapper
Mapper Type: role-ldap-mapper
LDAP Groups DN: CN=Keycloak-Admins,OU=Security Groups,DC=company,DC=local
Use Realm Roles Mapping: ON
Client ID: (leave empty for realm roles)
```

### 3.3 Custom Attribute Mappers (NIST Compliance)

#### Employee ID Mapper
```
Name: employee-id
Mapper Type: user-attribute-ldap-mapper
User Model Attribute: employeeId
LDAP Attribute: employeeNumber
Read Only: ON
Always Read Value From LDAP: ON
```

#### Department Mapper
```
Name: department
Mapper Type: user-attribute-ldap-mapper
User Model Attribute: department
LDAP Attribute: department
Read Only: ON
Always Read Value From LDAP: ON
```

## Step 4: Authentication Policies (NIST 800-171 Compliance)

### 4.1 Password Policy Configuration (NIST IA.1.7)

Navigate to **Authentication** → **Password Policy**:

```
Password Policy Settings:
- Minimum Length: 12 characters
- Maximum Length: 128 characters
- Minimum Digits: 1
- Minimum Lower Case: 1
- Minimum Upper Case: 1
- Minimum Special Characters: 1
- Not Username: Enabled
- Not Email: Enabled
- Regular Expression: ^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]
- Password History: 12 (NIST IA.1.8)
- Force Expired Password Change: 90 days
```

### 4.2 Account Lockout Policy (NIST IA.1.6)

Navigate to **Realm Settings** → **Security Defenses**:

```
Brute Force Detection:
- Enabled: ON
- Max Login Failures: 5
- Wait Increment Seconds: 60
- Quick Login Check Milli Seconds: 1000
- Minimum Quick Login Wait Seconds: 60
- Max Wait Seconds: 900
- Failure Reset Time Seconds: 43200 (12 hours)
```

### 4.3 Session Management (NIST IA.1.6)

Navigate to **Realm Settings** → **Tokens**:

```
Session Settings:
- SSO Session Idle: 30 minutes
- SSO Session Max: 8 hours
- Offline Session Idle: 720 hours (30 days)
- Offline Session Max Limited: ON
- Offline Session Max: 1440 hours (60 days)
- Client Session Idle: 30 minutes
- Client Session Max: 8 hours
```

## Step 5: Multi-Factor Authentication (NIST IA.1.3)

### 5.1 Configure OTP Authentication

1. Navigate to **Authentication** → **Flows**
2. Copy "Browser" flow to create "Browser with MFA"
3. Add **OTP Form** execution after **Username Password Form**

#### OTP Configuration
```
Name: otp-form
Requirement: REQUIRED
Config:
- OTP Type: totp
- OTP Hash Algorithm: SHA256
- Number of Digits: 6
- Look Ahead Window: 1
- Initial Counter: 0
- Period: 30
```

### 5.2 Required Actions for MFA

Navigate to **Authentication** → **Required Actions**:

```
Configure OTP: Enabled, Default Action
Update Password: Enabled
Update Profile: Enabled
Verify Email: Enabled (if email verification required)
```

### 5.3 Conditional Authentication (Advanced)

Create conditional flows based on risk:

```javascript
// Example: Require MFA for admin users
if (user.getRealmRoleMappings().stream().anyMatch(role -> role.getName().equals("admin"))) {
    context.getTopLevelFlow().setRequirement(Requirement.REQUIRED);
}
```

## Step 6: Audit and Logging (NIST 800-171 Compliance)

### 6.1 Enable Event Logging

Navigate to **Realm Settings** → **Events**:

```
Event Listeners:
- jboss-logging: ON
- email: OFF (configure if needed)

Event Config:
- Save Events: ON
- Event Types to Save: 
  - LOGIN
  - LOGIN_ERROR
  - LOGOUT
  - REGISTER
  - UPDATE_PASSWORD
  - UPDATE_PROFILE
  - FEDERATED_IDENTITY_LINK
  - REMOVE_FEDERATED_IDENTITY
  - CLIENT_LOGIN
  - CLIENT_REGISTER
  - CLIENT_UPDATE

Admin Event Settings:
- Save Admin Events: ON
- Include Representation: ON
```

### 6.2 Configure Log Aggregation

Add to your Docker Compose for centralized logging:

```yaml
services:
  keycloak:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    environment:
      - KC_LOG_LEVEL=INFO
      - KC_LOG_CONSOLE_OUTPUT=json
```

### 6.3 SIEM Integration

Forward logs to Security Information and Event Management (SIEM) system:

```bash
# Example: Forward to Splunk
# Configure log forwarding in your container orchestration
# or use a log aggregation service
```

## Step 7: Security Hardening

### 7.1 SSL/TLS Configuration (NIST IA.1.10)

```yaml
# In docker-compose.yml
keycloak:
  environment:
    - KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/server.crt
    - KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/server.key
    - KC_HTTPS_PROTOCOLS=TLSv1.3,TLSv1.2
    - KC_HTTPS_CIPHER_SUITES=TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256
```

### 7.2 Security Headers

Configure security headers in nginx:

```nginx
# Security headers for NIST compliance
add_header X-Frame-Options "DENY" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

### 7.3 Network Security

```yaml
# Restrict network access
networks:
  keycloak-internal:
    driver: bridge
    internal: true
  keycloak-external:
    driver: bridge
```

## Step 8: Testing and Validation

### 8.1 LDAP Connectivity Test

```bash
# Test LDAP synchronization
curl -X POST "https://your-domain.com/auth/admin/realms/master/user-storage/[federation-id]/sync?action=triggerFullSync" \
  -H "Authorization: Bearer [admin-token]"
```

### 8.2 Authentication Flow Test

Test each authentication scenario:

1. **Standard user login**
2. **Admin user login with MFA**
3. **Failed login attempts (lockout testing)**
4. **Password complexity validation**
5. **Session timeout testing**

### 8.3 NIST 800-171 Compliance Validation

#### Access Control Testing
```bash
# Test user access restrictions
# Verify users can only access authorized resources
# Test role-based access control
```

#### Authentication Testing
```bash
# Test password complexity enforcement
# Verify MFA requirements
# Test session management
```

## Step 9: Monitoring and Maintenance

### 9.1 Health Monitoring

Create monitoring scripts:

```bash
#!/bin/bash
# keycloak-health-check.sh

# Check Keycloak health
curl -f https://your-domain.com/auth/health

# Check LDAP connectivity
ldapsearch -H ldaps://ldap.company.local:636 -D [bind-dn] -w [password] -s base
```

### 9.2 Regular Maintenance Tasks

#### Daily Tasks
- Review authentication logs
- Monitor failed login attempts
- Check system resource usage

#### Weekly Tasks
- Review user access reports
- Update security group mappings
- Verify LDAP synchronization

#### Monthly Tasks
- Review and update password policies
- Audit user accounts and permissions
- Update security documentation

### 9.3 Backup and Recovery

```bash
# Backup Keycloak realm configuration
/opt/keycloak/bin/kc.sh export --dir /backup --realm company --users realm_file

# Backup LDAP integration settings
# Export realm configuration including user federation settings
```

## Step 10: Documentation and Compliance

### 10.1 Required Documentation (NIST 800-171)

Create and maintain these documents:

1. **Access Control Policy**
   - User access procedures
   - Role definitions and responsibilities
   - Account provisioning/deprovisioning

2. **Authentication Procedures**
   - Password requirements
   - MFA implementation
   - Account lockout procedures

3. **Audit and Monitoring Plan**
   - Log retention policies
   - Event monitoring procedures
   - Incident response plans

4. **System Security Plan**
   - LDAP integration architecture
   - Security controls implementation
   - Risk assessment and mitigation

### 10.2 Compliance Checklist

#### Access Control (AC)
- [ ] AC.1.1: System access limited to authorized users
- [ ] AC.1.5: Principle of least privilege implemented
- [ ] AC.3.1: Audit logs created and retained
- [ ] AC.3.2: User actions are traceable

#### Identification and Authentication (IA)
- [ ] IA.1.1: Users are identified before access
- [ ] IA.1.2: User identities are authenticated
- [ ] IA.1.3: MFA implemented for privileged accounts
- [ ] IA.1.6: Inactive accounts are disabled
- [ ] IA.1.7: Password complexity enforced
- [ ] IA.1.10: Passwords cryptographically protected

## Troubleshooting

### Common LDAP Issues

#### Connection Problems
```bash
# Test LDAP connectivity
telnet ldap.company.local 636

# Verify SSL certificate
openssl s_client -connect ldap.company.local:636 -servername ldap.company.local
```

#### Authentication Failures
```bash
# Check bind credentials
ldapsearch -H ldaps://ldap.company.local:636 \
  -D "CN=keycloak-svc,OU=Service Accounts,DC=company,DC=local" \
  -W -s base
```

#### Synchronization Issues
- Check user DN configuration
- Verify LDAP filters
- Review group mapping configuration
- Check service account permissions

### Performance Optimization

#### Connection Pooling
```
Initial Pool Size: 1
Max Pool Size: 20
Preferred Pool Size: 5
Pool Timeout: 300000
```

#### Caching Configuration
```
# Enable LDAP caching
Cache Policy: DEFAULT
Max Lifespan: 86400000 (24 hours)
```

## Security Best Practices Summary

1. **Use LDAPS only** - Never use unencrypted LDAP
2. **Implement least privilege** - Service accounts with minimal permissions
3. **Enable comprehensive logging** - All authentication events
4. **Regular security reviews** - Monthly access audits
5. **Keep systems updated** - Regular Keycloak and LDAP updates
6. **Monitor for anomalies** - Automated alerting for suspicious activity
7. **Test disaster recovery** - Regular backup and restore testing
8. **Document everything** - Maintain current security documentation

## Conclusion

This configuration provides a robust, NIST 800-171 compliant LDAP integration with Keycloak. Regular monitoring, maintenance, and security reviews are essential for maintaining compliance and security posture.

Remember to adapt specific settings to your organization's security policies and requirements while maintaining the core NIST 800-171 compliance controls outlined in this guide.