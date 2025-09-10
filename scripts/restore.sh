#!/bin/bash

# =============================================================================
# MONITORING PORTAL - RESTORE SCRIPT
# =============================================================================
# This script restores a complete backup of the monitoring portal including:
# - Environment configurations
# - SSL certificates
# - Docker volumes (Grafana, Prometheus, Keycloak DB)
# - Database imports
# - Configuration files
#
# Usage: ./restore.sh <backup-name> [--force] [--skip-services]
# Example: ./restore.sh backup_20240315_140530
# Options:
#   --force: Skip confirmation prompts
#   --skip-services: Don't restart services after restore

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="$PROJECT_DIR/backups"
LOG_FILE="$PROJECT_DIR/logs/restore.log"

# Parse arguments
BACKUP_NAME=""
FORCE=false
SKIP_SERVICES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --skip-services)
            SKIP_SERVICES=true
            shift
            ;;
        *)
            if [[ -z "$BACKUP_NAME" ]]; then
                BACKUP_NAME="$1"
            else
                echo "Unknown option: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate backup name
if [[ -z "$BACKUP_NAME" ]]; then
    echo "Usage: $0 <backup-name> [--force] [--skip-services]"
    echo
    echo "Available backups:"
    ls -1 "$BACKUP_BASE_DIR"/*.tar.gz 2>/dev/null | xargs -I {} basename {} .tar.gz || echo "  No backups found"
    exit 1
fi

BACKUP_ARCHIVE="$BACKUP_BASE_DIR/${BACKUP_NAME}.tar.gz"
BACKUP_EXTRACT_DIR="$BACKUP_BASE_DIR/${BACKUP_NAME}_restore"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Load current environment variables if available
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Set defaults
POSTGRES_USER="${POSTGRES_USER:-keycloak}"
POSTGRES_DB="${POSTGRES_DB:-keycloak}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-monitoring-portal}"
DOMAIN="${DOMAIN:-monitor.domain.com}"

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

warn() {
    echo "[$TIMESTAMP] WARNING: $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# VALIDATION FUNCTIONS
# -----------------------------------------------------------------------------
check_requirements() {
    log "Checking restore requirements..."

    # Check if backup archive exists
    if [[ ! -f "$BACKUP_ARCHIVE" ]]; then
        error "Backup archive not found: $BACKUP_ARCHIVE"
        exit 1
    fi

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

    success "Requirements check passed"
}

confirm_restore() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo
    echo "⚠️  WARNING: This will restore data from backup and may overwrite existing configurations!"
    echo
    echo "Backup to restore: $BACKUP_NAME"
    echo "Archive location: $BACKUP_ARCHIVE"
    echo "Archive size: $(du -h "$BACKUP_ARCHIVE" | cut -f1)"
    echo "Target project: $PROJECT_DIR"
    echo

    # Show current services status
    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        echo "Current services status:"
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" ps || true
        echo
    fi

    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Restore cancelled by user"
        exit 0
    fi
}

extract_backup() {
    log "Extracting backup archive..."

    # Clean up any previous extraction
    if [[ -d "$BACKUP_EXTRACT_DIR" ]]; then
        rm -rf "$BACKUP_EXTRACT_DIR"
    fi

    mkdir -p "$BACKUP_EXTRACT_DIR"

    # Extract backup archive
    if tar -xzf "$BACKUP_ARCHIVE" -C "$BACKUP_EXTRACT_DIR"; then
        success "Backup archive extracted"
    else
        error "Failed to extract backup archive"
        exit 1
    fi

    # Find the actual backup directory (handle nested structure)
    BACKUP_DATA_DIR=$(find "$BACKUP_EXTRACT_DIR" -maxdepth 2 -name "configs" -type d | head -1)
    if [[ -n "$BACKUP_DATA_DIR" ]]; then
        BACKUP_DATA_DIR=$(dirname "$BACKUP_DATA_DIR")
        success "Backup data directory located: $BACKUP_DATA_DIR"
    else
        error "Invalid backup structure - configs directory not found"
        exit 1
    fi
}

show_backup_info() {
    local info_file="$BACKUP_DATA_DIR/backup-info.txt"

    if [[ -f "$info_file" ]]; then
        echo
        echo "📋 Backup Information:"
        echo "====================="
        grep -E "^(Backup Name|Created|Domain|Project):" "$info_file" || true
        echo
    fi
}

stop_services() {
    log "Stopping services..."

    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        cd "$PROJECT_DIR"
        docker-compose down --remove-orphans || warn "Some services may not have stopped cleanly"
        success "Services stopped"
    else
        warn "No docker-compose.yml found - skipping service stop"
    fi
}

# -----------------------------------------------------------------------------
# RESTORE FUNCTIONS
# -----------------------------------------------------------------------------
restore_configurations() {
    log "Restoring configuration files..."

    local configs_dir="$BACKUP_DATA_DIR/configs"

    if [[ ! -d "$configs_dir" ]]; then
        warn "No configuration backup found - skipping"
        return 0
    fi

    # Backup existing configurations
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        cp "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.backup.$(date +%s)" || true
        log "Existing .env backed up"
    fi

    # Restore environment configuration
    if [[ -f "$configs_dir/env-backup" ]]; then
        cp "$configs_dir/env-backup" "$PROJECT_DIR/.env"
        chmod 600 "$PROJECT_DIR/.env"
        success "Environment configuration restored"

        # Reload environment variables
        source "$PROJECT_DIR/.env" 2>/dev/null || true
    fi

    # Restore docker-compose.yml
    if [[ -f "$configs_dir/docker-compose.yml" ]]; then
        cp "$configs_dir/docker-compose.yml" "$PROJECT_DIR/"
        success "Docker Compose configuration restored"
    fi

    # Restore Traefik configuration
    if [[ -d "$configs_dir/traefik" ]]; then
        rm -rf "$PROJECT_DIR/traefik" 2>/dev/null || true
        cp -r "$configs_dir/traefik" "$PROJECT_DIR/"
        success "Traefik configuration restored"
    fi

    # Restore Prometheus configuration
    if [[ -d "$configs_dir/prometheus" ]]; then
        rm -rf "$PROJECT_DIR/prometheus" 2>/dev/null || true
        cp -r "$configs_dir/prometheus" "$PROJECT_DIR/"
        success "Prometheus configuration restored"
    fi

    # Restore Grafana configuration
    if [[ -d "$configs_dir/grafana" ]]; then
        rm -rf "$PROJECT_DIR/grafana" 2>/dev/null || true
        cp -r "$configs_dir/grafana" "$PROJECT_DIR/"
        success "Grafana configuration restored"
    fi

    # Restore web application
    if [[ -d "$configs_dir/webapp" ]]; then
        rm -rf "$PROJECT_DIR/webapp" 2>/dev/null || true
        cp -r "$configs_dir/webapp" "$PROJECT_DIR/"
        success "Web application restored"
    fi
}

restore_certificates() {
    log "Restoring SSL certificates..."

    local certs_dir="$BACKUP_DATA_DIR/certs"

    if [[ ! -d "$certs_dir" ]]; then
        warn "No certificate backup found - skipping"
        return 0
    fi

    # Backup existing certificates
    if [[ -d "$PROJECT_DIR/certs" ]]; then
        mv "$PROJECT_DIR/certs" "$PROJECT_DIR/certs.backup.$(date +%s)" || true
        log "Existing certificates backed up"
    fi

    # Restore certificates
    cp -r "$certs_dir" "$PROJECT_DIR/"

    # Extract private keys if they were archived separately
    if [[ -f "$PROJECT_DIR/certs/private-keys-secure.tar.gz" ]]; then
        cd "$PROJECT_DIR/certs"
        tar -xzf "private-keys-secure.tar.gz"
        rm -f "private-keys-secure.tar.gz"
        log "Private keys extracted"
    fi

    # Set proper permissions
    find "$PROJECT_DIR/certs" -name "*.key" -exec chmod 600 {} \;
    find "$PROJECT_DIR/certs" -name "*.crt" -exec chmod 644 {} \;
    find "$PROJECT_DIR/certs" -name "*.pem" -exec chmod 644 {} \;
    chmod 600 "$PROJECT_DIR/certs/acme.json" 2>/dev/null || true

    success "SSL certificates restored with proper permissions"
}

restore_volumes() {
    log "Restoring Docker volumes..."

    local volumes_dir="$BACKUP_DATA_DIR/volumes"

    if [[ ! -d "$volumes_dir" ]]; then
        warn "No volume backups found - skipping"
        return 0
    fi

    # Restore Grafana data
    if [[ -f "$volumes_dir/grafana_data.tar.gz" ]]; then
        log "Restoring Grafana data volume..."

        # Remove existing volume if it exists
        docker volume rm "${COMPOSE_PROJECT_NAME}_grafana_data" 2>/dev/null || true

        # Create new volume and restore data
        docker volume create "${COMPOSE_PROJECT_NAME}_grafana_data"
        docker run --rm \
            -v "${COMPOSE_PROJECT_NAME}_grafana_data":/data \
            -v "$volumes_dir":/backup:ro \
            alpine:latest \
            tar xzf /backup/grafana_data.tar.gz -C /data

        success "Grafana data volume restored"
    fi

    # Restore Prometheus data
    if [[ -f "$volumes_dir/prometheus_data.tar.gz" ]]; then
        log "Restoring Prometheus data volume..."

        docker volume rm "${COMPOSE_PROJECT_NAME}_prometheus_data" 2>/dev/null || true
        docker volume create "${COMPOSE_PROJECT_NAME}_prometheus_data"
        docker run --rm \
            -v "${COMPOSE_PROJECT_NAME}_prometheus_data":/data \
            -v "$volumes_dir":/backup:ro \
            alpine:latest \
            tar xzf /backup/prometheus_data.tar.gz -C /data

        success "Prometheus data volume restored"
    fi

    # Restore Keycloak data volume
    if [[ -f "$volumes_dir/keycloak_data.tar.gz" ]]; then
        log "Restoring Keycloak data volume..."

        docker volume rm "${COMPOSE_PROJECT_NAME}_keycloak_data" 2>/dev/null || true
        docker volume create "${COMPOSE_PROJECT_NAME}_keycloak_data"
        docker run --rm \
            -v "${COMPOSE_PROJECT_NAME}_keycloak_data":/data \
            -v "$volumes_dir":/backup:ro \
            alpine:latest \
            tar xzf /backup/keycloak_data.tar.gz -C /data

        success "Keycloak data volume restored"
    fi
}

restore_database() {
    log "Restoring database..."

    local database_dir="$BACKUP_DATA_DIR/database"

    if [[ ! -d "$database_dir" ]]; then
        warn "No database backup found - skipping"
        return 0
    fi

    # Start only the database service first
    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        cd "$PROJECT_DIR"

        # Start database service
        docker-compose up -d keycloak-db

        # Wait for database to be ready
        log "Waiting for database to be ready..."
        sleep 10

        # Check if database is accessible
        local retries=30
        while ! docker-compose exec -T keycloak-db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
            if [[ $retries -eq 0 ]]; then
                error "Database failed to start within timeout"
                return 1
            fi
            retries=$((retries-1))
            sleep 2
        done

        success "Database is ready"

        # Restore database dump
        if [[ -f "$database_dir/keycloak.sql" ]]; then
            log "Restoring Keycloak database from SQL dump..."

            # Drop and recreate database to ensure clean restore
            docker-compose exec -T keycloak-db psql -U "$POSTGRES_USER" -d postgres \
                -c "DROP DATABASE IF EXISTS $POSTGRES_DB;" >/dev/null 2>&1 || true
            docker-compose exec -T keycloak-db psql -U "$POSTGRES_USER" -d postgres \
                -c "CREATE DATABASE $POSTGRES_DB;" >/dev/null 2>&1

            # Import dump
            docker-compose exec -T keycloak-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
                < "$database_dir/keycloak.sql"

            success "Keycloak database restored from SQL dump"
        fi
    fi
}

start_services() {
    if [[ "$SKIP_SERVICES" == "true" ]]; then
        log "Skipping service startup (--skip-services specified)"
        return 0
    fi

    log "Starting all services..."

    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        cd "$PROJECT_DIR"

        # Start all services
        docker-compose up -d

        # Wait for services to be healthy
        log "Waiting for services to start..."
        sleep 15

        # Check service status
        docker-compose ps

        success "Services started"
    fi
}

verify_restore() {
    log "Verifying restore..."

    local verification_failed=false

    # Check if key files exist
    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        error "Environment configuration not found"
        verification_failed=true
    fi

    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        error "Docker compose file not found"
        verification_failed=true
    fi

    # Check volumes
    for volume in grafana_data prometheus_data keycloak_data; do
        if docker volume inspect "${COMPOSE_PROJECT_NAME}_${volume}" >/dev/null 2>&1; then
            success "Volume ${volume} exists"
        else
            warn "Volume ${volume} not found"
        fi
    done

    # Check service health (if services were started)
    if [[ "$SKIP_SERVICES" != "true" && -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        cd "$PROJECT_DIR"
        if docker-compose ps | grep -q "Up"; then
            success "Services are running"
        else
            warn "Some services may not be running properly"
        fi
    fi

    if [[ "$verification_failed" == "true" ]]; then
        error "Restore verification failed"
        return 1
    else
        success "Restore verification passed"
        return 0
    fi
}

cleanup_restore() {
    log "Cleaning up temporary files..."

    if [[ -d "$BACKUP_EXTRACT_DIR" ]]; then
        rm -rf "$BACKUP_EXTRACT_DIR"
        success "Temporary files cleaned up"
    fi
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    log "=== MONITORING PORTAL RESTORE STARTED ==="
    log "Backup name: $BACKUP_NAME"
    log "Archive: $BACKUP_ARCHIVE"
    log "Target directory: $PROJECT_DIR"

    # Pre-flight checks
    check_requirements
    confirm_restore

    # Extract and validate backup
    extract_backup
    show_backup_info

    # Stop services before restore
    stop_services

    # Perform restore
    restore_configurations
    restore_certificates
    restore_volumes
    restore_database

    # Start services and verify
    start_services
    verify_restore

    # Cleanup
    cleanup_restore

    success "=== RESTORE COMPLETED SUCCESSFULLY ==="

    # Display summary
    echo
    echo "🎉 Restore completed successfully!"
    echo "📦 Restored from: ${BACKUP_NAME}.tar.gz"
    echo "🎯 Target: $PROJECT_DIR"
    echo

    if [[ "$SKIP_SERVICES" != "true" ]]; then
        echo "🔗 Services should be accessible at:"
        echo "   https://${DOMAIN}/"
        echo
        echo "📊 Check service status with:"
        echo "   cd $PROJECT_DIR && docker-compose ps"
        echo
    fi

    echo "📋 Next steps:"
    echo "   1. Verify services are working correctly"
    echo "   2. Check logs: docker-compose logs -f"
    echo "   3. Test authentication and access"
    echo
}

# Handle script interruption
trap 'error "Restore interrupted"; cleanup_restore; exit 1' INT TERM

# Run main function
main "$@"