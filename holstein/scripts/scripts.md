# Project Management Scripts

This directory contains three essential scripts for managing your Docker monitoring stack. Each script is interactive and will ask for confirmation before making any changes to your system.

## Scripts Overview

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `install-deps.sh` | Install Docker and dependencies | First-time setup on new systems |
| `holstein-util.sh` | Project maintenance and operations | Regular maintenance and configuration |
| `holstein-diag.sh` | Health checks and troubleshooting | When issues occur or routine monitoring |

## Quick Start

```bash
# Make scripts executable
chmod +x scripts/*.sh

# 1. First-time setup (install dependencies)
./scripts/install-deps.sh

# 2. Configure and maintain project
./scripts/holstein-util.sh

# 3. Check system health
./scripts/holstein-diag.sh
```

---

## 1. install-deps.sh - Dependency Installer

### Purpose
Installs Docker, Docker Compose, and all required system dependencies for the monitoring stack.

### Features
- **OS Detection**: Automatically detects RHEL/CentOS/Fedora vs Ubuntu/Debian
- **Docker Installation**: Uses official Docker installation methods
- **Additional Tools**: Installs jq, dos2unix, zip, curl, git, openssl, wget
- **User Management**: Adds user to docker group
- **Verification**: Tests all installations to ensure they work

### Usage
```bash
./scripts/install-deps.sh
```

### What It Installs

#### Docker Components
- Docker Engine (latest stable)
- Docker Compose Plugin
- Docker Buildx Plugin
- Containerd runtime

#### System Tools
- `jq` - JSON processor for API interactions
- `dos2unix` - Line ending converter
- `zip/unzip` - Archive tools for backups
- `curl` - HTTP client for health checks
- `git` - Version control
- `openssl` - Cryptography tools
- `wget` - File downloader

### Operating System Support
- **RHEL/CentOS/Fedora**: Uses dnf package manager
- **Ubuntu/Debian**: Uses apt package manager
- **Other**: Provides manual installation guidance

### Post-Installation
After running this script:
1. Log out and back in (if added to docker group)
2. Verify installation: `docker --version`
3. Test Docker: `docker run hello-world`

---

## 2. holstein-util.sh - Project Management Tool

### Purpose
Interactive tool for project maintenance, backups, configuration, and automation setup.

### Features
- **Backup System**: Create timestamped ZIP backups
- **Restore System**: Restore from previous backups
- **File Maintenance**: Fix line endings and permissions
- **Automation**: Setup cron jobs for scheduled backups
- **Configuration**: Generate .env files from templates

### Main Menu Options

#### 1. Create Backup
- Creates `backups/backup_YYYYMMDD_HHMMSS.zip`
- Includes: config/, scripts/, webapp/, guides/, .env, docker-compose.yml
- Excludes: data/ directory (container volumes)
- Shows backup size and verification

```bash
# Backup contents
├── docker-compose.yml
├── .env
├── config/
├── scripts/
├── webapp/
├── guides/
└── backup_info.txt
```

#### 2. Restore Backup
- Lists all available backups with dates and sizes
- Allows selection of specific backup to restore
- **Warning**: Overwrites current files
- Stops Docker services before restoring

#### 3. Fix Line Endings
- Converts Windows (CRLF) to Unix (LF) format
- Processes: `.sh`, `.yml`, `.yaml`, `.conf`, `.py`, `.env*` files
- Uses `dos2unix` (installs if needed)
- Essential for cross-platform compatibility

#### 4. Fix File Permissions
- Scripts (`.sh`): 755 (executable)
- Config files: 644 (readable)
- Directories: 755 (accessible)
- `.env` files: 600 (secure)
- Data directory: Proper ownership

#### 5. Setup Automated Backups
- Creates cron jobs for automatic backups
- Schedule options:
  - Daily at 2:00 AM
  - Daily at 6:00 AM
  - Weekly (Sundays at 3:00 AM)
  - Custom schedule
- Manages backup retention (keeps last 10 auto-backups)
- Logs backup results to `backups/backup.log`

#### 6. Generate .env File
- Interactive creation from `.env.example`
- Prompts for each configuration variable
- Masks sensitive inputs (passwords, secrets)
- Backs up existing `.env` before overwriting
- Sets secure permissions (600)

### Usage Examples

```bash
# Interactive menu
./scripts/holstein-util.sh

# Automated backup (for cron)
./scripts/holstein-util.sh --auto-backup
```

### Backup Strategy
- **Manual backups**: Before major changes
- **Automated backups**: Regular schedule via cron
- **Retention policy**: Keeps last 10 automatic backups
- **Restore testing**: Verify backups work before you need them

---

## 3. holstein-diag.sh - System Diagnostic Tool

### Purpose
Comprehensive health monitoring and troubleshooting for the entire Docker monitoring stack.

### Features
- **12 Health Checks**: From Docker installation to service accessibility
- **Scoring System**: Pass/Warning/Fail with overall health percentage
- **Detailed Logging**: Timestamped log files for issue tracking
- **Recommendations**: Actionable advice based on findings
- **Resource Monitoring**: CPU, memory, disk usage analysis

### Health Checks Performed

#### System Level
1. **Docker Installation** - Verifies Docker and Docker Compose
2. **Docker Daemon Status** - Checks service is running
3. **Project Files** - Validates required files exist
4. **Environment Configuration** - Checks .env variables

#### Service Level
5. **Container Status** - All containers running and healthy
6. **Database Connections** - PostgreSQL connectivity tests
7. **Service Endpoints** - Internal API health checks
8. **External Access** - Nginx routing and external URLs

#### Performance Level
9. **Resource Usage** - Disk, memory, Docker resource monitoring
10. **Log Analysis** - Scans for error patterns
11. **Configuration Files** - Syntax validation
12. **Network Connectivity** - Docker networking and DNS

### Output Format

```bash
================================================
    Docker Stack Diagnostic Tool
================================================
Project: monitoring-stack
Domain: rancher.local
Stack: holstein

✓ PASS: Docker Installation
✓ PASS: Container Status
⚠ WARN: Resource Usage
✗ FAIL: External Access (CRITICAL)

================================================
    Diagnostic Summary
================================================
Total Checks: 12
Passed: 8
Warnings: 2
Failed: 2

Overall Health: GOOD (75%)
```

### Health Scoring
- **EXCELLENT (90%+)**: All systems operational
- **GOOD (75-89%)**: Minor issues, mostly functional
- **FAIR (50-74%)**: Several issues need attention
- **POOR (<50%)**: Major problems, immediate action required

### Log Files
- Saved as: `diagnostic_YYYYMMDD_HHMMSS.log`
- Contains: Timestamp, check results, detailed findings
- Useful for: Issue tracking, support requests, change monitoring

### Usage
```bash
# Run full diagnostic
./scripts/holstein-diag.sh

# The script will:
# 1. Run all health checks
# 2. Show summary with health score
# 3. Offer detailed analysis
# 4. Generate recommendations
# 5. Save complete log file
```

### When to Run
- **After installation**: Verify everything is working
- **Before major changes**: Establish baseline
- **When issues occur**: Identify root causes
- **Regular monitoring**: Weekly health checks
- **Before/after updates**: Ensure stability

---

## Best Practices

### Installation Workflow
1. Run `install-deps.sh` on new systems
2. Use `holstein-util.sh` to generate `.env` from example
3. Deploy your stack: `docker-compose up -d`
4. Verify with `holstein-diag.sh`

### Maintenance Routine
1. **Weekly**: Run `holstein-diag.sh` for health monitoring
2. **Before changes**: Create backup with `holstein-util.sh`
3. **After changes**: Run diagnostics to verify
4. **Monthly**: Review and clean old backups

### Troubleshooting Process
1. Run `holstein-diag.sh` to identify issues
2. Check specific container logs: `docker-compose logs <service>`
3. Review diagnostic log file for details
4. Apply recommended fixes
5. Re-run diagnostics to verify resolution

### Backup Strategy
```bash
# Set up automated daily backups
./scripts/holstein-util.sh
# Choose option 5, then option 1 (Daily at 2:00 AM)

# Manual backup before major changes
./scripts/holstein-util.sh
# Choose option 1 (Create Backup)

# Test restore process periodically
./scripts/holstein-util.sh
# Choose option 2 (Restore Backup)
```

## Security Notes

### File Permissions
- Scripts are executable (755)
- Configuration files are readable (644)
- Environment files are secure (600)
- Data directories have proper ownership

### Sensitive Data
- `.env` files contain passwords and secrets
- Backups include `.env` files
- Store backups securely
- Use strong passwords in `.env`

### Docker Security
- User added to docker group for convenience
- Consider rootless Docker for production
- Regularly update container images
- Monitor for security vulnerabilities

## Troubleshooting

### Common Issues

#### Scripts Not Executable
```bash
chmod +x scripts/*.sh
```

#### Docker Permission Denied
```bash
# Add user to docker group (requires logout/login)
sudo usermod -aG docker $USER

# Or run with sudo temporarily
sudo docker --version
```

#### Missing Dependencies
```bash
# Re-run dependency installer
./scripts/install-deps.sh
```

#### Backup/Restore Fails
- Check disk space: `df -h`
- Verify permissions: `ls -la backups/`
- Check backup file integrity: `unzip -t backup_file.zip`

#### Diagnostic Failures
- Review specific error messages
- Check container logs: `docker-compose logs`
- Verify .env configuration
- Ensure all containers are running

### Getting Help

1. **Check diagnostic log**: `diagnostic_*.log`
2. **Review container logs**: `docker-compose logs <service>`
3. **Verify configuration**: Check `.env` and config files
4. **Test individual components**: Use diagnostic script
5. **Consult documentation**: `guides/TROUBLESHOOTING.md`

## Script Requirements

### System Requirements
- Linux (RHEL/CentOS/Fedora or Ubuntu/Debian)
- Bash shell
- Internet connection (for installations)
- Sudo privileges

### Disk Space
- Docker installation: ~500MB
- Container images: ~2-5GB
- Data volumes: Variable
- Backups: ~50-200MB each

### Dependencies
All dependencies are automatically installed by `install-deps.sh`:
- Docker Engine and Compose
- System tools (jq, curl, zip, etc.)
- Development tools (git, openssl)

---

## Contributing

### Adding New Checks to Diagnostic Script
1. Create check function following naming pattern: `check_new_feature()`
2. Add to main() function: `run_check "Feature Name" check_new_feature`
3. Test thoroughly before committing

### Extending Management Script
1. Add new menu option to `show_main_menu()`
2. Create corresponding function
3. Follow confirmation and logging patterns
4. Update this README

### Improving Installation Script
1. Test on different OS distributions
2. Add new dependency detection
3. Enhance error handling
4. Update supported OS list

## License

These scripts are part of the Docker monitoring stack project. Use and modify according to your project's license terms.