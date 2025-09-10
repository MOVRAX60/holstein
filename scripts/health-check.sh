#!/bin/bash

# =============================================================================
# MONITORING PORTAL - HEALTH CHECK SCRIPT
# =============================================================================
# This script performs comprehensive health checks on the monitoring portal:
# - Service availability and status
# - SSL certificate validation
# - Database connectivity
# - Volume integrity
# - Network connectivity
# - Authentication flow
#
# Usage: ./health-check.sh [--verbose] [--json] [--nagios]
# Options:
#   --verbose: Show detailed output
#   --json: Output results in JSON format
#   --nagios: Output in Nagios-compatible format

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/logs/health-check.log"

# Parse arguments
VERBOSE=false
JSON_OUTPUT=false
NAGIOS_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --nagios)
            NAGIOS_OUTPUT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--verbose] [--json] [--nagios]"
            exit 1
            ;;
    esac
done

# Load environment variables if available
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Set defaults
DOMAIN="${DOMAIN:-monitor.domain.com}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-monitoring-portal}"
POSTGRES_USER="${POSTGRES_USER:-keycloak}"
POSTGRES_DB="${POSTGRES_DB:-keycloak}"
TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"

# Health check results
declare -A CHECKS
OVERALL_STATUS="OK"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# -----------------------------------------------------------------------------
# LOGGING AND OUTPUT FUNCTIONS
# -----------------------------------------------------------------------------
log() {
    if [[ "$JSON_OUTPUT" != "true" && "$NAGIOS_OUTPUT" != "true" ]]; then
        echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
    fi
}

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "$1"
    fi
}

check_result() {
    local check_name="$1"
    local status="$2"
    local message="$3"

    CHECKS["$check_name"]="$status:$message"

    if [[ "$status" != "OK" ]]; then
        OVERALL_STATUS="CRITICAL"
    fi

    if [[ "$JSON_OUTPUT" != "true" && "$NAGIOS_OUTPUT" != "true" ]]; then
        local icon="✅"
        if [[ "$status" == "WARNING" ]]; then
            icon="⚠️ "
        elif [[ "$status" == "CRITICAL" ]]; then
            icon="❌"
        fi

        echo "$icon $check_name: $message"
    fi
}

# -----------------------------------------------------------------------------
# HEALTH CHECK FUNCTIONS
# -----------------------------------------------------------------------------
check_docker() {
    verbose "Checking Docker daemon..."

    if docker info >/dev/null 2>&1; then
        check_result "Docker" "OK" "Docker daemon is running"
    else
        check_result "Docker" "CRITICAL" "Docker daemon is not accessible"
        return 1
    fi
}

check_compose_file() {
    verbose "Checking Docker Compose file..."

    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        if docker-compose -f "$PROJECT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
            check_result "Compose File" "OK" "Docker Compose file is valid"
        else
            check_result "Compose File" "CRITICAL" "Docker Compose file has syntax errors"
            return 1
        fi
    else
        check_result "Compose File" "CRITICAL" "Docker Compose file not found"
        return 1
    fi
}

check_services() {
    verbose "Checking service status..."

    cd "$PROJECT_DIR"
    local services_output
    services_output=$(docker-compose ps 2>/dev/null || echo "")

    if [[ -z "$services_output" ]]; then
        check_result "Services" "CRITICAL" "No services found or docker-compose failed"
        return 1
    fi

    local running_count=0
    local total_count=0
    local failed_services=()

    # Check each expected service
    for service in traefik keycloak keycloak-db grafana prometheus webapp; do
        total_count=$((total_count + 1))

        if echo "$services_output" | grep -q "$service.*Up"; then
            running_count=$((running_count + 1))
            verbose "Service $service is running"
        else
            failed_services+=("$service")
            verbose "Service $service is not running"
        fi
    done

    if [[ $running_count -eq $total_count ]]; then
        check_result "Services" "OK" "All $total_count services are running"
    elif [[ $running_count -gt 0 ]]; then
        check_result "Services" "WARNING" "$running_count/$total_count services running (failed: ${failed_services[*]})"
    else
        check_result "Services" "CRITICAL" "No services are running"
    fi
}

check_volumes() {
    verbose "Checking Docker volumes..."

    local volume_issues=()

    for volume in grafana_data prometheus_data keycloak_data; do
        local full_volume_name="${COMPOSE_PROJECT_NAME}_${volume}"

        if docker volume inspect "$full_volume_name" >/dev/null 2>&1; then
            verbose "Volume $volume exists"
        else
            volume_issues+=("$volume")
        fi
    done

    if [[ ${#volume_issues[@]} -eq 0 ]]; then
        check_result "Volumes" "OK" "All required volumes exist"
    else
        check_result "Volumes" "WARNING" "Missing volumes: ${volume_issues[*]}"
    fi
}

check_network_connectivity() {
    verbose "Checking network connectivity..."

    # Check if containers can communicate
    if docker-compose -f "$PROJECT_DIR/docker-compose.yml" exec -T webapp ping -c 1 keycloak >/dev/null 2>&1; then
        check_result "Network" "OK" "Internal network connectivity is working"
    else
        check_result "Network" "WARNING" "Internal network connectivity issues detected"
    fi
}

check_ssl_certificates() {
    verbose "Checking SSL certificates..."

    local cert_file="$PROJECT_DIR/certs/${DOMAIN}.crt"

    if [[ ! -f "$cert_file" ]]; then
        # Try alternative naming
        cert_file=$(find "$PROJECT_DIR/certs" -name "*.crt" | head -1)
    fi

    if [[ -f "$cert_file" ]]; then
        # Check certificate expiration
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
                check_result "SSL Certificate" "CRITICAL" "Certificate has expired"
            elif [[ $days_until_expiry -lt 30 ]]; then
                check_result "SSL Certificate" "WARNING" "Certificate expires in $days_until_expiry days"
            else
                check_result "SSL Certificate" "OK" "Certificate is valid (expires in $days_until_expiry days)"
            fi
        else
            check_result "SSL Certificate" "WARNING" "Cannot read certificate expiration date"
        fi
    else
        check_result "SSL Certificate" "WARNING" "SSL certificate not found"
    fi
}

check_web_endpoints() {
    verbose "Checking web endpoints..."

    local endpoints=(
        "https://${DOMAIN}/"
        "https://${DOMAIN}/auth/"
        "https://${DOMAIN}/grafana/"
        "https://${DOMAIN}/prometheus/"
    )

    local failed_endpoints=()
    local success_count=0

    for endpoint in "${endpoints[@]}"; do
        verbose "Testing endpoint: $endpoint"

        if timeout $TIMEOUT curl -k -s -f "$endpoint" >/dev/null 2>&1; then
            success_count=$((success_count + 1))
            verbose "Endpoint $endpoint is accessible"
        else
            failed_endpoints+=("$endpoint")
            verbose "Endpoint $endpoint is not accessible"
        fi
    done

    if [[ $success_count -eq ${#endpoints[@]} ]]; then
        check_result "Web Endpoints" "OK" "All endpoints are accessible"
    elif [[ $success_count -gt 0 ]]; then
        check_result "Web Endpoints" "WARNING" "$success_count/${#endpoints[@]} endpoints accessible"
    else
        check_result "Web Endpoints" "CRITICAL" "No endpoints are accessible"
    fi
}

check_database_connectivity() {
    verbose "Checking database connectivity..."

    cd "$PROJECT_DIR"

    if docker-compose exec -T keycloak-db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
        check_result "Database" "OK" "Database is accessible and ready"
    else
        check_result "Database" "CRITICAL" "Database is not accessible"
    fi
}

check_keycloak_health() {
    verbose "Checking Keycloak health..."

    cd "$PROJECT_DIR"

    # Check if Keycloak health endpoint responds
    if docker-compose exec -T keycloak curl -f http://localhost:8080/auth/health/ready >/dev/null 2>&1; then
        check_result "Keycloak" "OK" "Keycloak is healthy and ready"
    else
        # Fallback: check if Keycloak is responding at all
        if docker-compose exec -T keycloak curl -s http://localhost:8080/auth/ | grep -q "Keycloak" 2>/dev/null; then
            check_result "Keycloak" "WARNING" "Keycloak is running but health check failed"
        else
            check_result "Keycloak" "CRITICAL" "Keycloak is not responding"
        fi
    fi
}

check_prometheus_targets() {
    verbose "Checking Prometheus targets..."

    # Check if we can query Prometheus targets
    local targets_up=0
    local total_targets=0

    if timeout $TIMEOUT curl -k -s "https://${DOMAIN}/prometheus/api/v1/targets" 2>/dev/null | grep -q "activeTargets"; then
        # Try to count up targets (simplified check)
        targets_up=$(timeout $TIMEOUT curl -k -s "https://${DOMAIN}/prometheus/api/v1/targets" 2>/dev/null | grep -o '"health":"up"' | wc -l || echo "0")
        total_targets=$(timeout $TIMEOUT curl -k -s "https://${DOMAIN}/prometheus/api/v1/targets" 2>/dev/null | grep -o '"health":"' | wc -l || echo "1")

        if [[ $targets_up -eq $total_targets ]] && [[ $total_targets -gt 0 ]]; then
            check_result "Prometheus Targets" "OK" "All $total_targets targets are up"
        elif [[ $targets_up -gt 0 ]]; then
            check_result "Prometheus Targets" "WARNING" "$targets_up/$total_targets targets are up"
        else
            check_result "Prometheus Targets" "CRITICAL" "No Prometheus targets are up"
        fi
    else
        check_result "Prometheus Targets" "WARNING" "Cannot query Prometheus targets API"
    fi
}

check_disk_space() {
    verbose "Checking disk space..."

    local disk_usage
    disk_usage=$(df "$PROJECT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ $disk_usage -lt 80 ]]; then
        check_result "Disk Space" "OK" "Disk usage is ${disk_usage}%"
    elif [[ $disk_usage -lt 90 ]]; then
        check_result "Disk Space" "WARNING" "Disk usage is ${disk_usage}%"
    else
        check_result "Disk Space" "CRITICAL" "Disk usage is ${disk_usage}%"
    fi
}

# -----------------------------------------------------------------------------
# OUTPUT FUNCTIONS
# -----------------------------------------------------------------------------
output_json() {
    local json_output="{"
    json_output+='"timestamp":"'$TIMESTAMP'",'
    json_output+='"overall_status":"'$OVERALL_STATUS'",'
    json_output+='"domain":"'$DOMAIN'",'
    json_output+='"checks":{'

    local first=true
    for check_name in "${!CHECKS[@]}"; do
        local check_data="${CHECKS[$check_name]}"
        local status="${check_data%%:*}"
        local message="${check_data#*:}"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_output+=","
        fi

        json_output+='"'$check_name'":{'
        json_output+='"status":"'$status'",'
        json_output+='"message":"'$message'"'
        json_output+='}'
    done

    json_output+='}}'

    echo "$json_output"
}

output_nagios() {
    local nagios_status="OK"
    local critical_count=0
    local warning_count=0
    local ok_count=0

    for check_name in "${!CHECKS[@]}"; do
        local check_data="${CHECKS[$check_name]}"
        local status="${check_data%%:*}"

        case "$status" in
            "OK") ok_count=$((ok_count + 1)) ;;
            "WARNING") warning_count=$((warning_count + 1)) ;;
            "CRITICAL") critical_count=$((critical_count + 1)) ;;
        esac
    done

    if [[ $critical_count -gt 0 ]]; then
        nagios_status="CRITICAL"
    elif [[ $warning_count -gt 0 ]]; then
        nagios_status="WARNING"
    fi

    echo "MONITORING PORTAL $nagios_status - $ok_count OK, $warning_count WARNING, $critical_count CRITICAL | ok=$ok_count;warning=$warning_count;critical=$critical_count"

    # Exit with appropriate code for Nagios
    case "$nagios_status" in
        "OK") exit 0 ;;
        "WARNING") exit 1 ;;
        "CRITICAL") exit 2 ;;
    esac
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    # Create log directory if needed
    mkdir -p "$(dirname "$LOG_FILE")"

    if [[ "$JSON_OUTPUT" != "true" && "$NAGIOS_OUTPUT" != "true" ]]; then
        echo "🔍 Monitoring Portal Health Check"
        echo "=================================="
        echo "Domain: $DOMAIN"
        echo "Timestamp: $TIMESTAMP"
        echo
    fi

    # Perform all health checks
    check_docker || true
    check_compose_file || true
    check_services || true
    check_volumes || true
    check_network_connectivity || true
    check_ssl_certificates || true
    check_web_endpoints || true
    check_database_connectivity || true
    check_keycloak_health || true
    check_prometheus_targets || true
    check_disk_space || true

    # Output results based on format
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
    elif [[ "$NAGIOS_OUTPUT" == "true" ]]; then
        output_nagios
    else
        echo
        echo "📊 Health Check Summary"
        echo "======================"
        echo "Overall Status: $OVERALL_STATUS"
        echo "Checks Completed: ${#CHECKS[@]}"
        echo

        if [[ "$OVERALL_STATUS" == "OK" ]]; then
            echo "🎉 All systems are healthy!"
        else
            echo "⚠️  Some issues detected. Check the details above."
        fi

        echo
        echo "💡 Tips:"
        echo "  - Use --verbose for detailed output"
        echo "  - Use --json for machine-readable output"
        echo "  - Add to cron for automated monitoring"
        echo

        # Set exit code based on overall status
        case "$OVERALL_STATUS" in
            "OK") exit 0 ;;
            "WARNING") exit 1 ;;
            "CRITICAL") exit 2 ;;
        esac
    fi
}

# Handle script interruption
trap 'echo "Health check interrupted"; exit 3' INT TERM

# Run main function
main "$@"