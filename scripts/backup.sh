#!/bin/bash

# =============================================================================
# MONITORING PORTAL - BACKUP SCRIPT
# =============================================================================
# This script creates a complete backup of the monitoring portal including:
# - Environment configurations
# - SSL certificates
# - Docker volumes (Grafana, Prometheus, Keycloak DB)
# - Database dumps
# - Configuration files
#
# Usage: ./backup.sh [backup-name]
# Example: ./backup.sh weekly-backup

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="$PROJECT_DIR/backups"
LOG_FILE="$PROJECT_DIR/logs/backup.log"

# Load environment variables if .env exists
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Set defaults if not provided in .env
POSTGRES_USER="${POSTGRES_USER:-keycloak}"
POSTGRES_DB="${POSTGRES_DB:-keycloak}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-monitoring-portal}"
DOMAIN="${DOMAIN:-monitor.domain.com}"

# Backup naming
BACKUP_NAME="${1:-backup_$(date +%Y%m%d_%H%M%S)}"
BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_NAME"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

success() {
    echo "[$TIMESTAMP] SUCCESS: $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# VALIDATION FUNCTIONS
# -----------------------------------------------------------------------------
check_requirements() {
    log "Checking requirements..."

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running or accessible"
        exit 1
    fi

    # Check if docker-compose is available
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "docker-compose not found"
        exit 1
    fi

    # Check if project directory exists
    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        error "docker-compose.yml not found in $PROJECT_DIR"
        exit 1
    fi

    success "Requirements check passed"
}

create_backup_structure() {
    log "Creating backup directory structure..."

    mkdir -p "$BACKUP_DIR"/{configs,certs,volumes,database,logs}
    mkdir -p "$(dirname "$LOG_FILE")"

    success "Backup directory created: $BACKUP_DIR"
}

# -----------------------------------------------------------------------------
# BACKUP FUNCTIONS
# -----------------------------------------------------------------------------
backup_configurations() {
    log "Backing up configuration files..."

    # Environment configuration
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        cp "$PROJECT_DIR/.env" "$BACKUP_DIR/configs/env-backup"
        success "Environment configuration backed up"
    else
        log "WARNING: .env file not found"
    fi

    # Docker compose and configs
    cp "$PROJECT_DIR/docker-compose.yml" "$BACKUP_DIR/configs/"

    # Traefik configuration
    if [[ -d "$PROJECT_DIR/traefik" ]]; then
        cp -r "$PROJECT_DIR/traefik" "$BACKUP_DIR/configs/"
        success "Traefik configuration backed up"
    fi

    # Prometheus configuration
    if [[ -d "$PROJECT_DIR/prometheus" ]]; then
        cp -r "$PROJECT_DIR/prometheus" "$BACKUP_DIR/configs/"
        success "Prometheus configuration backed up"
    fi

    # Grafana provisioning
    if [[ -d "$PROJECT_DIR/grafana" ]]; then
        cp -r "$PROJECT_DIR/grafana" "$BACKUP_DIR/configs/"
        success "Grafana configuration backed up"
    fi

    # Web application
    if [[ -d "$PROJECT_DIR/webapp" ]]; then
        cp -r "$PROJECT_DIR/webapp" "$BACKUP_DIR/configs/"
        success "Web application backed up"
    fi
}

backup_certificates() {
    log "Backing up SSL certificates..."

    if [[ -d "$PROJECT_DIR/certs" ]]; then
        # Copy all certificates but preserve permissions
        cp -rp "$PROJECT_DIR/certs" "$BACKUP_DIR/"

        # Create secure archive of private keys
        if ls "$PROJECT_DIR/certs"/*.key >/dev/null 2>&1; then
            tar -czf "$BACKUP_DIR/certs/private-keys-secure.tar.gz" \
                -C "$PROJECT_DIR/certs" \
                --mode=600 \
                *.key 2>/dev/null || true
        fi

        success "SSL certificates backed up"
    else
        log "WARNING: certs directory not found"
    fi
}

backup_database() {
    log "Backing up Keycloak database..."

    # Check if Keycloak database container is running
    if docker-compose -f "$PROJECT_DIR/docker-compose.yml" ps keycloak-db | grep -q "Up"; then
        # Dump PostgreSQL database
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T keycloak-db \
            pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$BACKUP_DIR/database/keycloak.sql"

        if [[ -s "$BACKUP_DIR/database/keycloak.sql" ]]; then
            success "Keycloak database backed up"
        else
            error "Keycloak database backup failed (empty file)"
            return 1
        fi
    else
        log "WARNING: Keycloak database container not running - skipping database backup"
    fi

    # Export Keycloak realm configuration
    if docker-compose -f "$PROJECT_DIR/docker-compose.yml" ps keycloak | grep -q "Up"; then
        log "Exporting Keycloak realm configuration..."

        # Wait a moment for Keycloak to be ready
        sleep 5

        # Export realm (this might fail if realm doesn't exist yet)
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T keycloak \
            /opt/keycloak/bin/kc.sh export --dir /tmp/export --realm "${KEYCLOAK_REALM:-monitoring}" \
            >/dev/null 2>&1 || log "WARNING: Could not export Keycloak realm (may not exist yet)"

        # Copy exported realm if it exists
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T keycloak \
            cat "/tmp/export/${KEYCLOAK_REALM:-monitoring}-realm.json" 2>/dev/null \
            > "$BACKUP_DIR/database/keycloak-realm.json" || true

        if [[ -s "$BACKUP_DIR/database/keycloak-realm.json" ]]; then
            success "Keycloak realm configuration exported"
        else
            log "WARNING: Keycloak realm export not available"
        fi
    fi
}

backup_volumes() {
    log "Backing up Docker volumes..."

    # Grafana data
    if docker volume inspect "${COMPOSE_PROJECT_NAME}_grafana_data" >/dev/null 2>&1; then
        log "Backing up Grafana data..."
        docker run --rm \
            -v "${COMPOSE_PROJECT_NAME}_grafana_data":/data:ro \
            -v "$BACKUP_DIR/volumes":/backup \
            alpine:latest \
            tar czf /backup/grafana_data.tar.gz -C /data .
        success "Grafana data backed up"
    fi

    # Prometheus data
    if docker volume inspect "${COMPOSE_PROJECT_NAME}_prometheus_data" >/dev/null 2>&1; then
        log "Backing up Prometheus data..."
        docker run --rm \
            -v "${COMPOSE_PROJECT_NAME}_prometheus_data":/data:ro \
            -v "$BACKUP_DIR/volumes":/backup \
            alpine:latest \
            tar czf /backup/prometheus_data.tar.gz -C /data .
        success "Prometheus data backed up"
    fi

    # Keycloak data (PostgreSQL)
    if docker volume inspect "${COMPOSE_PROJECT_NAME}_keycloak_data" >/dev/null 2>&1; then
        log "Backing up Keycloak volume data..."
        docker run --rm \
            -v "${COMPOSE_PROJECT_NAME}_keycloak_data":/data:ro \
            -v "$BACKUP_DIR/volumes":/backup \
            alpine:latest \
            tar czf /backup/keycloak_data.tar.gz -C /data .
        success "Keycloak volume data backed up"
    fi
}

backup_logs() {
    log "Backing up application logs..."

    if [[ -d "$PROJECT_DIR/logs" ]]; then
        # Copy recent logs (last 7 days)
        find "$PROJECT_DIR/logs" -type f -mtime -7 -name "*.log" \
            -exec cp {} "$BACKUP_DIR/logs/" \; 2>/dev/null || true

        success "Application logs backed up"
    fi
}

create_backup_archive() {
    log "Creating compressed backup archive..."

    cd "$BACKUP_BASE_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

    if [[ -f "${BACKUP_NAME}.tar.gz" ]]; then
        ARCHIVE_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
        success "Backup archive created: ${BACKUP_NAME}.tar.gz (${ARCHIVE_SIZE})"

        # Remove uncompressed backup directory
        rm -rf "$BACKUP_NAME"
        success "Uncompressed backup directory cleaned up"
    else
        error "Failed to create backup archive"
        return 1
    fi
}

generate_backup_info() {
    log "Generating backup information file..."

    # Extract to get info
    cd "$BACKUP_BASE_DIR"
    mkdir -p "${BACKUP_NAME}_temp"
    tar -xzf "${BACKUP_NAME}.tar.gz" -C "${BACKUP_NAME}_temp"

    INFO_FILE="${BACKUP_NAME}_temp/$BACKUP_NAME/backup-info.txt"

    cat > "$INFO_FILE" << EOF
# =============================================================================
# MONITORING PORTAL BACKUP INFORMATION
# =============================================================================

Backup Name: $BACKUP_NAME
Created: $(date)
Host: $(hostname)
User: $(whoami)
Domain: $DOMAIN
Project: $COMPOSE_PROJECT_NAME

# -----------------------------------------------------------------------------
# BACKUP CONTENTS
# -----------------------------------------------------------------------------

Configuration Files:
$(find "${BACKUP_NAME}_temp/$BACKUP_NAME/configs" -type f 2>/dev/null | sed 's|.*configs/|- |' || echo "- None found")

Certificates:
$(find "${BACKUP_NAME}_temp/$BACKUP_NAME/certs" -type f -name "*.crt" 2>/dev/null | sed 's|.*certs/|- |' || echo "- None found")

Volume Backups:
$(find "${BACKUP_NAME}_temp/$BACKUP_NAME/volumes" -name "*.tar.gz" 2>/dev/null | sed 's|.*volumes/|- |' || echo "- None found")

Database Backups:
$(find "${BACKUP_NAME}_temp/$BACKUP_NAME/database" -type f 2>/dev/null | sed 's|.*database/|- |' || echo "- None found")

# -----------------------------------------------------------------------------
# FILE SIZES
# -----------------------------------------------------------------------------

Total Archive Size: $(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)

Individual Component Sizes:
$(du -h "${BACKUP_NAME}_temp/$BACKUP_NAME"/* 2>/dev/null | sort -hr || echo "Unable to determine sizes")

# -----------------------------------------------------------------------------
# RESTORATION NOTES
# -----------------------------------------------------------------------------

To restore this backup:
1. Extract: tar -xzf ${BACKUP_NAME}.tar.gz
2. Run: ./scripts/restore.sh ${BACKUP_NAME}

Service Status at Backup Time:
$(docker-compose -f "$PROJECT_DIR/docker-compose.yml" ps 2>/dev/null || echo "Unable to get service status")

# -----------------------------------------------------------------------------
# ENVIRONMENT INFO
# -----------------------------------------------------------------------------

Docker Version: $(docker --version 2>/dev/null || echo "Unknown")
Docker Compose Version: $(docker-compose --version 2>/dev/null || echo "Unknown")

EOF

    # Recreate archive with info file
    tar -czf "${BACKUP_NAME}.tar.gz" -C "${BACKUP_NAME}_temp" "$BACKUP_NAME"
    rm -rf "${BACKUP_NAME}_temp"

    success "Backup information file added to archive"
}

cleanup_old_backups() {
    log "Cleaning up old backups..."

    local retention_days="${BACKUP_RETENTION_DAYS:-30}"

    # Remove backups older than retention period
    find "$BACKUP_BASE_DIR" -name "backup_*.tar.gz" -mtime +$retention_days -type f -delete 2>/dev/null || true
    find "$BACKUP_BASE_DIR" -name "backup_*" -mtime +$retention_days -type d -exec rm -rf {} + 2>/dev/null || true

    success "Old backups cleaned up (retention: ${retention_days} days)"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    log "=== MONITORING PORTAL BACKUP STARTED ==="
    log "Backup name: $BACKUP_NAME"
    log "Project directory: $PROJECT_DIR"
    log "Backup directory: $BACKUP_DIR"

    # Pre-flight checks
    check_requirements

    # Create backup structure
    create_backup_structure

    # Perform backups
    backup_configurations
    backup_certificates
    backup_database
    backup_volumes
    backup_logs

    # Finalize backup
    create_backup_archive
    generate_backup_info
    cleanup_old_backups

    success "=== BACKUP COMPLETED SUCCESSFULLY ==="
    log "Backup location: $BACKUP_BASE_DIR/${BACKUP_NAME}.tar.gz"
    log "Backup size: $(du -h "$BACKUP_BASE_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)"

    # Display summary
    echo
    echo "🎉 Backup completed successfully!"
    echo "📦 Archive: ${BACKUP_NAME}.tar.gz"
    echo "📍 Location: $BACKUP_BASE_DIR/"
    echo "📊 Size: $(du -h "$BACKUP_BASE_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)"
    echo
    echo "To restore: ./scripts/restore.sh $BACKUP_NAME"
    echo
}

# Handle script interruption
trap 'error "Backup interrupted"; exit 1' INT TERM

# Run main function
main "$@"