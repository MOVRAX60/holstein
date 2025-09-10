# nginx Reverse Proxy Setup Guide

## Directory Structure

Create this directory structure in your project:

```
rancher-dockerstyle/
├── docker-compose.yml          # New nginx-based compose file
├── .env                        # Environment variables
├── create-certs.sh             # SSL certificate script
├── nginx/
│   ├── nginx.conf              # Main nginx configuration
│   └── conf.d/
│       └── monitoring.conf     # Server configuration
├── certs/                      # SSL certificates (generated)
├── webapp/
│   ├── Dockerfile
│   ├── app.py                  # Updated for nginx auth_request
│   ├── requirements.txt
│   └── templates/
│       ├── base.html
│       ├── login.html
│       ├── monitoring.html
│       ├── admin.html
│       ├── profile.html
│       └── error.html          # New error page
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
│       └── monitoring-rules.yml
└── grafana/
    └── provisioning/
        └── datasources/
            └── prometheus.yml
```

## Setup Steps

### 1. Backup Current Configuration

```bash
# Backup your current setup
cp docker-compose.yml docker-compose.traefik.backup
cp -r traefik traefik.backup
```

### 2. Replace Configuration Files

Replace these files with the nginx versions provided:

- `docker-compose.yml` - New nginx-based configuration
- `.env` - Updated environment file
- `webapp/app.py` - Updated for nginx auth_request
- Add `webapp/templates/error.html` - Error page template

### 3. Create nginx Configuration

```bash
# Create nginx directory structure
mkdir -p nginx/conf.d

# Add nginx.conf to nginx/
# Add monitoring.conf to nginx/conf.d/
```

### 4. Generate SSL Certificates

```bash
# Make script executable
chmod +x create-certs.sh

# Generate certificates for your domain
./create-certs.sh rancher.local

# Verify certificates were created
ls -la certs/
```

### 5. Update Hosts File

```bash
# Add domain to hosts file
echo "127.0.0.1 rancher.local" | sudo tee -a /etc/hosts
```

### 6. Configure Environment Variables

Update your `.env` file with secure passwords:

```bash
# Generate secure passwords
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32)
KEYCLOAK_DB_PASSWORD=$(openssl rand -base64 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
GRAFANA_CLIENT_SECRET=$(openssl rand -base64 32)
WEBAPP_CLIENT_SECRET=$(openssl rand -base64 32)
WEBAPP_SECRET_KEY=$(openssl rand -base64 32)
RANCHER_BOOTSTRAP_PASSWORD=$(openssl rand -base64 32)

# Update .env file with these values
```

## Startup Procedure

### 1. Stop Existing Stack

```bash
# Stop Traefik-based stack
docker compose down

# Clean up (optional)
docker system prune -f
```

### 2. Start Services in Order

```bash
# Start core services first
docker compose up -d keycloak-db nginx

# Wait for database
sleep 10

# Start Keycloak
docker compose up -d keycloak

# Wait for Keycloak to be ready
sleep 30

# Start remaining services
docker compose up -d webapp grafana prometheus rancher

# Check status
docker compose ps
```

### 3. Configure Keycloak

1. **Access Keycloak Admin Console:**
   ```bash
   # Open in browser
   https://rancher.local/auth/admin/
   ```

2. **Create Realm (if not using master):**
   - Create new realm called "monitoring"
   - Update KEYCLOAK_REALM in .env if changed

3. **Create Client Applications:**

   **Webapp Client:**
   - Client ID: `webapp`
   - Client Type: `confidential`
   - Valid Redirect URIs: `https://rancher.local/callback`
   - Web Origins: `https://rancher.local`

   **Grafana Client:**
   - Client ID: `grafana`
   - Client Type: `confidential`
   - Valid Redirect URIs: `https://rancher.local/grafana/login/generic_oauth`
   - Web Origins: `https://rancher.local`

4. **Create User Groups:**
   - Create groups: `admin`, `modify`, `view`
   - Assign users to appropriate groups

5. **Create Test User:**
   - Username: `admin`
   - Password: Set strong password
   - Assign to `admin` group

## Testing

### 1. Basic Connectivity Tests

```bash
# Test nginx is running
curl -k https://rancher.local/nginx-health

# Test webapp health
curl -k https://rancher.local/health

# Test Keycloak
curl -k https://rancher.local/auth/

# Check nginx logs
docker compose logs nginx
```

### 2. Authentication Flow Test

1. **Visit main page:**
   ```
   https://rancher.local/
   ```
   Should redirect to login page

2. **Login with Keycloak:**
   - Click "Login with SSO"
   - Should redirect to Keycloak
   - Login with test user
   - Should return to monitoring dashboard

3. **Test protected pages:**
   - `/monitoring` - Requires authentication
   - `/admin` - Requires admin role
   - `/grafana/` - Requires authentication
   - `/prometheus/` - Requires authentication
   - `/rancher/` - Requires admin role

### 3. Service-Specific Tests

```bash
# Test service availability
curl -k -H "Cookie: session=..." https://rancher.local/grafana/
curl -k -H "Cookie: session=..." https://rancher.local/prometheus/
```

## Troubleshooting

### Common Issues

1. **502 Bad Gateway:**
   ```bash
   # Check if services are running
   docker compose ps
   
   # Check nginx logs
   docker compose logs nginx
   
   # Check service health
   docker compose exec webapp curl localhost:8000/health
   ```

2. **SSL Certificate Issues:**
   ```bash
   # Regenerate certificates
   ./create-certs.sh rancher.local
   
   # Restart nginx
   docker compose restart nginx
   ```

3. **Authentication Not Working:**
   ```bash
   # Check Keycloak connectivity
   docker compose exec webapp curl keycloak:8080/auth/
   
   # Check webapp logs
   docker compose logs webapp
   
   # Verify Keycloak client configuration
   ```

4. **nginx Config Errors:**
   ```bash
   # Test nginx configuration
   docker compose exec nginx nginx -t
   
   # Reload configuration
   docker compose exec nginx nginx -s reload
   ```

### Debug Mode

Enable debug logging:

```bash
# Set debug mode in .env
FLASK_DEBUG=true

# Restart webapp
docker compose restart webapp

# View detailed logs
docker compose logs -f webapp
```

## Migration from Traefik

The nginx setup provides these advantages over Traefik:

- **Simpler configuration:** Standard nginx syntax vs Traefik labels
- **Better debugging:** Clear nginx logs and configuration validation
- **More predictable:** Established nginx behavior vs Traefik discovery
- **Easier SSL:** Standard SSL configuration vs Traefik certificate resolvers

## Security Notes

1. **Change all default passwords** in .env file
2. **Use strong SSL certificates** for production
3. **Review nginx security headers** in configuration
4. **Enable fail2ban** for additional protection
5. **Regular security updates** for all components

## Performance Tuning

For production environments:

1. **Adjust nginx worker processes**
2. **Configure upstream keepalive connections**
3. **Enable gzip compression**
4. **Set appropriate buffer sizes**
5. **Configure rate limiting**

All these settings are included in the nginx configuration but may need tuning based on your specific requirements.