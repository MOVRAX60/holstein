# 🛠️ Monitoring Portal - Utility Scripts

This directory contains essential utility scripts for managing, monitoring, and maintaining your monitoring portal deployment.

## 📋 Scripts Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| `backup.sh` | Complete system backup | `./backup.sh [backup-name]` |
| `restore.sh` | Restore from backup | `./restore.sh <backup-name> [options]` |
| `health-check.sh` | System health monitoring | `./health-check.sh [options]` |
| `create-certificates.sh` | SSL certificate creation | `./create-certificates.sh [options]` |
| `monitor-cron.sh` | Automated monitoring for cron | `./monitor-cron.sh [--daily]` |

## 🔄 Backup and Restore

### Creating Backups

```bash
# Manual backup with auto-generated name
./backup.sh

# Named backup
./backup.sh weekly-maintenance

# What gets backed up:
# - Environment configuration (.env)
# - SSL certificates (with secure handling of private keys)
# - Docker volumes (Grafana, Prometheus, Keycloak data)
# - Database dumps (PostgreSQL)
# - Configuration files (Traefik, webapp, etc.)
# - Recent application logs
```

### Restoring from Backup

```bash
# List available backups
./restore.sh

# Restore specific backup (with confirmation)
./restore.sh backup_20240315_140530

# Force restore without confirmation
./restore.sh backup_20240315_140530 --force

# Restore without restarting services
./restore.sh backup_20240315_140530 --skip-services
```

**⚠️ Restore Safety:**
- Always confirms before overwriting existing data
- Backs up current configurations before restore
- Validates backup integrity before proceeding
- Can skip service restart for manual control

## 🔍 Health Monitoring

### Manual Health Checks

```bash
# Basic health check
./health-check.sh

# Verbose output with detailed information
./health-check.sh --verbose

# JSON output for automation
./health-check.sh --json

# Nagios-compatible output
./health-check.sh --nagios
```

### Health Check Categories

The health check script validates:
- ✅ **Docker & Compose**: Service availability
- ✅ **Services Status**: All containers running
- ✅ **Volumes**: Docker volume integrity
- ✅ **Network**: Internal connectivity
- ✅ **SSL Certificates**: Expiration and validity
- ✅ **Web Endpoints**: HTTP/HTTPS accessibility
- ✅ **Database**: PostgreSQL connectivity
- ✅ **Keycloak**: Authentication service health
- ✅ **Prometheus**: Target monitoring
- ✅ **Disk Space**: Storage usage

### Exit Codes

| Exit Code | Status | Meaning |
|-----------|--------|---------|
| 0 | OK | All checks passed |
| 1 | WARNING | Non-critical issues detected |
| 2 | CRITICAL | Critical issues require attention |
| 3 | UNKNOWN | Unable to determine status |

## 🔐 SSL Certificate Management

### Creating Internal Certificates

```bash
# Create CA and server certificate
./create-certificates.sh --domain monitor.yourdomain.com

# Create only Certificate Authority
./create-certificates.sh --ca-only

# Create self-signed certificate (development only)
./create-certificates.sh --domain monitor.yourdomain.com --self-signed

# Overwrite existing certificates
./create-certificates.sh --domain monitor.yourdomain.com --force
```

### Certificate Features

- **🔒 Secure Key Generation**: 4096-bit RSA keys
- **📋 Subject Alternative Names**: Wildcard and localhost support
- **⏰ Validity Periods**: 10 years for CA, 1 year for server certs
- **🔐 Proper Permissions**: Automatic secure file permissions
- **📖 Installation Guide**: Auto-generated setup instructions

### Certificate Files Created

```
certs/
├── monitor.domain.com.crt       # Server certificate (public)
├── monitor.domain.com.key       # Server private key (secure)
├── monitor.domain.com-fullchain.crt  # Certificate + CA chain
├── ca/
│   ├── ca-cert.pem             # Certificate Authority cert
│   └── ca-key.pem              # CA private key (secure)
├── acme.json                   # Let's Encrypt placeholder
└── INSTALL_INSTRUCTIONS.md     # Setup guide
```

## ⏰ Automated Monitoring with Cron

### Setup Automated Monitoring

```bash
# Edit crontab
crontab -e

# Add these lines for automated monitoring:
*/5 * * * * /path/to/monitoring-portal/scripts/monitor-cron.sh
0 2 * * * /path/to/monitoring-portal/scripts/monitor-cron.sh --daily
```

### Cron Monitoring Features

**Every 5 minutes:**
- Health check execution
- Automatic service restart on failures
- Email/Slack notifications on issues
- Log rotation when needed

**Daily (2 AM):**
- Old log cleanup
- Backup cleanup based on retention policy
- Disk space monitoring
- SSL certificate expiration checks
- Optional automated backups

### Notification Configuration

Add to your `.env` file:

```bash
# Email notifications
NOTIFICATION_EMAIL=admin@yourdomain.com

# Slack notifications
SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Auto-restart on failures
AUTO_RESTART=true

# Automatic daily backups
AUTO_BACKUP=true

# Backup retention (days)
BACKUP_RETENTION_DAYS=30
```

## 🔧 Script Configuration

### Environment Variables

All scripts respect these environment variables from `.env`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `DOMAIN` | Your domain name | `monitor.domain.com` |
| `COMPOSE_PROJECT_NAME` | Docker project name | `monitoring-portal` |
| `BACKUP_RETENTION_DAYS` | Backup retention period | `30` |
| `NOTIFICATION_EMAIL` | Email for alerts | none |
| `SLACK_WEBHOOK` | Slack webhook URL | none |
| `AUTO_RESTART` | Auto-restart on failures | `true` |
| `AUTO_BACKUP` | Daily automated backups | `false` |

### Logging

All scripts log to `../logs/` directory:
- `backup.log` - Backup operations
- `restore.log` - Restore operations  
- `health-check.log` - Health monitoring
- `cert-creation.log` - Certificate creation
- `monitor-cron.log` - Automated monitoring

## 📊 Usage Examples

### Weekly Maintenance Routine

```bash
#!/bin/bash
# weekly-maintenance.sh

cd /path/to/monitoring-portal/scripts

# Create weekly backup
./backup.sh "weekly_$(date +%Y_week_%U)"

# Run comprehensive health check
./health-check.sh --verbose

# Check certificate status
./create-certificates.sh --domain monitor.yourdomain.com --force

echo "Weekly maintenance completed!"
```

### Emergency Response

```bash
# Quick system check
./health-check.sh

# If issues detected, try service restart
cd ..
docker-compose restart

# Wait and re-check
sleep 30
./scripts/health-check.sh

# If still issues, restore from recent backup
./scripts/restore.sh $(ls -1t backups/*.tar.gz | head -1 | xargs basename -s .tar.gz)
```

### Certificate Renewal

```bash
# Check current certificate
openssl x509 -enddate -noout -in ../certs/monitor.yourdomain.com.crt

# Create new certificate
./create-certificates.sh --domain monitor.yourdomain.com --force

# Restart services to load new certificate
cd .. && docker-compose restart traefik
```

## 🚨 Troubleshooting

### Common Issues

**Script Permission Denied**
```bash
chmod +x scripts/*.sh
```

**Docker Not Accessible**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**Backup/Restore Failures**
```bash
# Check disk space
df -h

# Check Docker volumes
docker volume ls
docker-compose ps
```

**Certificate Issues**
```bash
# Verify OpenSSL
openssl version

# Check certificate permissions
ls -la certs/

# Test certificate
openssl verify -CAfile certs/ca/ca-cert.pem certs/monitor.yourdomain.com.crt
```

### Script Dependencies

**Required for all scripts:**
- Docker and Docker Compose
- Bash 4.0+
- Basic Unix tools (grep, awk, sed, find)

**Optional for enhanced features:**
- `mail` command for email notifications
- `curl` for Slack notifications and web checks
- `openssl` for certificate operations

## 🔐 Security Considerations

### File Permissions

Scripts automatically set secure permissions:
- Private keys: `600` (owner read/write only)
- Certificates: `644` (world readable)
- Scripts: `755` (executable by owner, readable by all)

### Backup Security

- Private keys are archived with secure permissions
- Backup files should be stored in secure locations
- Consider encrypting backups for offsite storage

### Access Control

- Limit script execution to authorized users
- Use dedicated service accounts for cron jobs
- Regularly audit script access and usage

---

## 📞 Support

For issues with scripts:
1. Check log files in `../logs/`
2. Run with `--verbose` for detailed output
3. Verify environment configuration in `../.env`
4. Test Docker and network connectivity

**🚀 These scripts provide complete operational control over your monitoring portal!**