#!/bin/bash

# =============================================================================
# MONITORING PORTAL - CRON MONITORING SCRIPT
# =============================================================================
# This script is designed to run from cron for automated monitoring:
# - Runs health checks
# - Sends notifications on issues
# - Performs automatic remediation for common issues
# - Rotates logs
# - Cleans up old backups
#
# Add to crontab:
# */5 * * * * /path/to/monitoring-portal/scripts/monitor-cron.sh
# 0 2 * * * /path/to/monitoring-portal/scripts/monitor-cron.sh --daily

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/logs/monitor-cron.log"
LOCK_FILE="/tmp/monitor-cron.lock"

# Parse arguments
DAILY_MODE=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --daily)
            DAILY_MODE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--daily] [--force]"
            exit 1
            ;;
    esac
done

# Load environment variables if available
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env" 2>/dev/null || true
fi

# Configuration defaults
DOMAIN="${DOMAIN:-monitor.domain.com}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
MAX_LOG_SIZE_MB="${MAX_LOG_SIZE_MB:-100}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
AUTO_RESTART="${AUTO_RESTART:-true}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# -----------------------------------------------------------------------------
# LOCKING AND LOGGING
# -----------------------------------------------------------------------------
acquire_lock() {
    if [[ "$FORCE" != "true" ]] && [[ -f "$LOCK_FILE" ]]; then
        local lock_age
        lock_age=$(($(date +%s) - $(stat -f %Y "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))

        # If lock is older than 30 minutes, assume stale
        if [[ $lock_age -gt 1800 ]]; then
            rm -f "$LOCK_FILE"
        else
            echo "Another instance is already running (lock file exists)"
            exit 1
        fi
    fi

    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT
}

log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

log_rotate() {
    if [[ -f "$LOG_FILE" ]]; then
        local log_size_mb
        log_size_mb=$(du -m "$LOG_FILE" | cut -f1)

        if [[ $log_size_mb -gt $MAX_LOG_SIZE_MB ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
            touch "$LOG_FILE"
            log "Log rotated (was ${log_size_mb}MB)"
        fi
    fi
}

# -----------------------------------------------------------------------------
# NOTIFICATION FUNCTIONS
# -----------------------------------------------------------------------------
send_email_notification() {
    local subject="$1"
    local body="$2"

    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "[Monitoring Portal] $subject" "$NOTIFICATION_EMAIL" || true
        log "Email notification sent: $subject"
    fi
}

send_slack_notification() {
    local message="$1"
    local color="${2:-warning}"

    if [[ -n "$SLACK_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🔍 *Monitoring Portal Alert*\n$message\",\"color\":\"$color\"}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
        log "Slack notification sent: $message"
    fi
}

send_notification() {
    local subject="$1"
    local message="$2"
    local color="${3:-warning}"

    send_email_notification "$subject" "$message"
    send_slack_notification "$message" "$color"
}

# -----------------------------------------------------------------------------
# HEALTH CHECK FUNCTIONS
# -----------------------------------------------------------------------------
run_health_check() {
    log "Running health check..."

    local health_output
    local health_status

    # Run health check script
    if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
        health_output=$("$SCRIPT_DIR/health-check.sh" --json 2>&1 || true)

        if [[ -n "$health_output" ]]; then
            # Parse JSON output to get overall status
            health_status=$(echo "$health_output" | grep -o '"overall_status":"[^"]*"' | cut -d'"' -f4 || echo "UNKNOWN")

            case "$health_status" in
                "OK")
                    log "Health check passed - all systems OK"
                    return 0
                    ;;
                "WARNING")
                    log "Health check warnings detected"
                    send_notification "Health Check Warnings" "Some non-critical issues detected on $DOMAIN:\n\n$health_output" "warning"
                    return 1
                    ;;
                "CRITICAL")
                    log "Health check critical issues detected"
                    send_notification "Health Check CRITICAL" "Critical issues detected on $DOMAIN:\n\n$health_output" "danger"
                    return 2
                    ;;
                *)
                    log "Health check status unknown: $health_status"
                    send_notification "Health Check Unknown" "Unable to determine health status for $DOMAIN:\n\n$health_output" "warning"
                    return 3
                    ;;
            esac
        else
            log "Health check script produced no output"
            send_notification "Health Check Failed" "Health check script failed to run on $DOMAIN" "danger"
            return 4
        fi
    else
        log "Health check script not found"
        return 5
    fi
}

# -----------------------------------------------------------------------------
# REMEDIATION FUNCTIONS
# -----------------------------------------------------------------------------
attempt_service_restart() {
    if [[ "$AUTO_RESTART" != "true" ]]; then
        log "Auto-restart disabled - skipping remediation"
        return 1
    fi

    log "Attempting to restart services..."

    cd "$PROJECT_DIR"

    # Try to restart services
    if docker-compose restart 2>/dev/null; then
        log "Services restarted successfully"
        sleep 30  # Wait for services to start

        # Re-run health check
        if run_health_check >/dev/null 2>&1; then
            send_notification "Auto-Remediation Successful" "Services were automatically restarted and are now healthy on $DOMAIN" "good"
            return 0
        else
            send_notification "Auto-Remediation Failed" "Services were restarted but health check still fails on $DOMAIN" "danger"
            return 1
        fi
    else
        log "Failed to restart services"
        send_notification "Auto-Remediation Failed" "Failed to restart services on $DOMAIN" "danger"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# MAINTENANCE FUNCTIONS
# -----------------------------------------------------------------------------
cleanup_old_logs() {
    log "Cleaning up old log files..."

    # Remove log files older than 30 days
    find "$PROJECT_DIR/logs" -name "*.log.*" -mtime +30 -delete 2>/dev/null || true

    # Clean Docker logs if they get too large
    if command -v docker >/dev/null 2>&1; then
        docker system prune -f --filter "until=72h" >/dev/null 2>&1 || true
    fi

    log "Log cleanup completed"
}

cleanup_old_backups() {
    log "Cleaning up old backups..."

    local backup_dir="$PROJECT_DIR/backups"
    if [[ -d "$backup_dir" ]]; then
        # Remove backups older than retention period
        find "$backup_dir" -name "backup_*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
        find "$backup_dir" -name "backup_*" -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

        log "Backup cleanup completed (retention: ${BACKUP_RETENTION_DAYS} days)"
    fi
}

check_disk_space() {
    log "Checking disk space..."

    local disk_usage
    disk_usage=$(df "$PROJECT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ $disk_usage -gt 90 ]]; then
        send_notification "Disk Space Critical" "Disk usage is at ${disk_usage}% on $DOMAIN. Immediate action required!" "danger"
        return 1
    elif [[ $disk_usage -gt 80 ]]; then
        send_notification "Disk Space Warning" "Disk usage is at ${disk_usage}% on $DOMAIN. Consider cleanup." "warning"
        return 1
    fi

    log "Disk space OK: ${disk_usage}% used"
    return 0
}

check_certificate_expiration() {
    log "Checking certificate expiration..."

    local cert_file="$PROJECT_DIR/certs/${DOMAIN}.crt"

    if [[ -f "$cert_file" ]]; then
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2 || echo "")

        if [[ -n "$expiry_date" ]]; then
            local expiry_timestamp
            expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local current_timestamp
            current_timestamp=$(date +%s)
            local days_until_expiry
            days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))

            if [[ $days_until_expiry -lt 0 ]]; then
                send_notification "SSL Certificate Expired" "SSL certificate for $DOMAIN has expired! Immediate renewal required." "danger"
                return 2
            elif [[ $days_until_expiry -lt 7 ]]; then
                send_notification "SSL Certificate Expiring Soon" "SSL certificate for $DOMAIN expires in $days_until_expiry days. Renewal required!" "danger"
                return 1
            elif [[ $days_until_expiry -lt 30 ]]; then
                send_notification "SSL Certificate Expiring" "SSL certificate for $DOMAIN expires in $days_until_expiry days. Schedule renewal." "warning"
                return 1
            fi

            log "SSL certificate OK: expires in $days_until_expiry days"
        fi
    fi

    return 0
}

perform_daily_maintenance() {
    log "Performing daily maintenance tasks..."

    cleanup_old_logs
    cleanup_old_backups
    check_disk_space
    check_certificate_expiration

    # Optional: Create daily backup
    if [[ "${AUTO_BACKUP:-false}" == "true" ]] && [[ -f "$SCRIPT_DIR/backup.sh" ]]; then
        log "Creating daily backup..."
        "$SCRIPT_DIR/backup.sh" "daily_$(date +%Y%m%d)" >/dev/null 2>&1 || log "Daily backup failed"
    fi

    log "Daily maintenance completed"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    # Setup
    mkdir -p "$(dirname "$LOG_FILE")"
    acquire_lock
    log_rotate

    log "=== CRON MONITORING STARTED ($(if [[ "$DAILY_MODE" == "true" ]]; then echo "DAILY MODE"; else echo "REGULAR MODE"; fi)) ==="

    # Daily maintenance tasks
    if [[ "$DAILY_MODE" == "true" ]]; then
        perform_daily_maintenance
    fi

    # Run health check
    local health_result=0
    run_health_check || health_result=$?

    # Attempt remediation if health check failed
    if [[ $health_result -ne 0 ]] && [[ "$DAILY_MODE" != "true" ]]; then
        log "Health check failed (exit code: $health_result), attempting remediation..."
        attempt_service_restart || log "Remediation failed"
    fi

    log "=== CRON MONITORING COMPLETED ==="

    # Exit with health check result for cron monitoring
    exit $health_result
}

# Run main function (lock cleanup handled by trap)
main "$@"