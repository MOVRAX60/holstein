#!/bin/bash

# Docker Stack Diagnostic Script
# Comprehensive health check for the monitoring stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="$(pwd)"
DOMAIN="${DOMAIN:-rancher.local}"
STACK_NAME="${STACK_NAME:-holstein}"
LOG_FILE="$PROJECT_ROOT/diagnostic_$(date +%Y%m%d_%H%M%S).log"

# Counters for summary
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Docker Stack Diagnostic Tool${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo -e "${CYAN}Project: $(basename "$PROJECT_ROOT")${NC}"
    echo -e "${CYAN}Domain: $DOMAIN${NC}"
    echo -e "${CYAN}Stack: $STACK_NAME${NC}"
    echo -e "${CYAN}Log File: $LOG_FILE${NC}"
    echo ""
}

# Function to log results
log_result() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to run check with result tracking
run_check() {
    local check_name="$1"
    local check_function="$2"
    local is_critical="${3:-false}"

    echo -e "${YELLOW}Checking: $check_name${NC}"
    ((TOTAL_CHECKS++))

    if $check_function; then
        echo -e "${GREEN}✓ PASS: $check_name${NC}"
        log_result "PASS: $check_name"
        ((PASSED_CHECKS++))
        return 0
    else
        if [ "$is_critical" = "true" ]; then
            echo -e "${RED}✗ FAIL: $check_name (CRITICAL)${NC}"
            log_result "FAIL: $check_name (CRITICAL)"
            ((FAILED_CHECKS++))
        else
            echo -e "${YELLOW}⚠ WARN: $check_name${NC}"
            log_result "WARN: $check_name"
            ((WARNING_CHECKS++))
        fi
        return 1
    fi
}

# Function to confirm action
confirm_action() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Check 1: Docker Installation
check_docker_installation() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "  Docker command not found"
        return 1
    fi

    if ! docker --version >/dev/null 2>&1; then
        echo "  Docker not responding"
        return 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        echo "  Docker Compose not available"
        return 1
    fi

    echo "  Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "  Docker Compose: $(docker compose version --short)"
    return 0
}

# Check 2: Docker Daemon Status
check_docker_daemon() {
    if ! docker info >/dev/null 2>&1; then
        echo "  Docker daemon not running or not accessible"
        echo "  Try: sudo systemctl start docker"
        return 1
    fi

    local containers_running=$(docker ps -q | wc -l)
    local containers_total=$(docker ps -a -q | wc -l)
    echo "  Docker daemon is running"
    echo "  Containers: $containers_running running, $containers_total total"
    return 0
}

# Check 3: Project Files
check_project_files() {
    local missing_files=()

    if [ ! -f "docker-compose.yml" ]; then
        missing_files+=("docker-compose.yml")
    fi

    if [ ! -f ".env" ]; then
        missing_files+=(".env")
    fi

    if [ ! -d "config" ]; then
        missing_files+=("config/ directory")
    fi

    if [ ! -d "webapp" ]; then
        missing_files+=("webapp/ directory")
    fi

    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "  Missing files: ${missing_files[*]}"
        return 1
    fi

    echo "  All required project files present"
    return 0
}

# Check 4: Environment Configuration
check_environment_config() {
    if [ ! -f ".env" ]; then
        echo "  .env file missing"
        return 1
    fi

    # Check for required variables
    local required_vars=("DOMAIN" "KEYCLOAK_ADMIN_PASSWORD" "GRAFANA_ADMIN_PASSWORD")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" .env; then
            missing_vars+=("$var")
        elif grep -q "^$var=.*change-this" .env; then
            missing_vars+=("$var (still has default value)")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "  Missing or default variables: ${missing_vars[*]}"
        return 1
    fi

    echo "  Environment configuration looks good"
    return 0
}

# Check 5: Container Status
check_container_status() {
    if ! docker-compose ps >/dev/null 2>&1; then
        echo "  Cannot get container status - stack not running?"
        return 1
    fi

    local containers=(
        "${STACK_NAME}-nginx-proxy"
        "${STACK_NAME}-keycloak"
        "${STACK_NAME}-keycloak-db"
        "${STACK_NAME}-wikijs"
        "${STACK_NAME}-wikijs-db"
        "${STACK_NAME}-prometheus"
        "${STACK_NAME}-grafana"
        "${STACK_NAME}-rancher"
        "${STACK_NAME}-flask-site"
    )

    local down_containers=()
    local unhealthy_containers=()

    for container in "${containers[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            down_containers+=("$container")
        else
            # Check health status
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-health-check")
            if [ "$health" = "unhealthy" ]; then
                unhealthy_containers+=("$container")
            fi
        fi
    done

    if [ ${#down_containers[@]} -gt 0 ]; then
        echo "  Containers not running: ${down_containers[*]}"
        return 1
    fi

    if [ ${#unhealthy_containers[@]} -gt 0 ]; then
        echo "  Unhealthy containers: ${unhealthy_containers[*]}"
        return 1
    fi

    echo "  All containers are running and healthy"
    return 0
}

# Check 6: Database Connections
check_database_connections() {
    local failed_dbs=()

    # Check Keycloak DB
    if ! docker exec "${STACK_NAME}-keycloak-db" pg_isready -U keycloak -d keycloak >/dev/null 2>&1; then
        failed_dbs+=("keycloak-db")
    fi

    # Check Wiki.js DB
    if ! docker exec "${STACK_NAME}-wikijs-db" pg_isready -U wikijs -d wikijs >/dev/null 2>&1; then
        failed_dbs+=("wikijs-db")
    fi

    if [ ${#failed_dbs[@]} -gt 0 ]; then
        echo "  Database connection failed: ${failed_dbs[*]}"
        return 1
    fi

    echo "  All database connections successful"
    return 0
}

# Check 7: Service Endpoints
check_service_endpoints() {
    local base_url="http://localhost"
    if [ "$DOMAIN" != "rancher.local" ]; then
        base_url="https://$DOMAIN"
    fi

    local failed_endpoints=()

    # Test internal container endpoints
    local endpoints=(
        "webapp:8000/health"
        "keycloak:8080/auth/health"
        "prometheus:9090/-/healthy"
        "grafana:3000/api/health"
    )

    for endpoint in "${endpoints[@]}"; do
        local service=$(echo "$endpoint" | cut -d: -f1)
        local container_name="${STACK_NAME}-${service}"

        if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
            if ! docker exec "$container_name" curl -f -s "http://localhost:$(echo "$endpoint" | cut -d: -f2)" >/dev/null 2>&1; then
                failed_endpoints+=("$endpoint")
            fi
        fi
    done

    if [ ${#failed_endpoints[@]} -gt 0 ]; then
        echo "  Failed endpoints: ${failed_endpoints[*]}"
        return 1
    fi

    echo "  All service endpoints responding"
    return 0
}

# Check 8: External Access
check_external_access() {
    local base_url="http://localhost"
    if [ "$DOMAIN" != "rancher.local" ]; then
        base_url="https://$DOMAIN"
    fi

    local failed_routes=()

    # Test external routes through nginx
    local routes=(
        "/"
        "/auth"
        "/grafana"
        "/prometheus"
        "/wiki"
    )

    for route in "${routes[@]}"; do
        if ! curl -f -s "$base_url$route" >/dev/null 2>&1; then
            failed_routes+=("$route")
        fi
    done

    if [ ${#failed_routes[@]} -gt 0 ]; then
        echo "  Failed external routes: ${failed_routes[*]}"
        return 1
    fi

    echo "  All external routes accessible"
    return 0
}

# Check 9: Resource Usage
check_resource_usage() {
    local warnings=()

    # Check disk space
    local disk_usage=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        warnings+=("Disk usage high: ${disk_usage}%")
    fi

    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 90 ]; then
        warnings+=("Memory usage high: ${mem_usage}%")
    fi

    # Check Docker system usage
    if command -v docker >/dev/null 2>&1; then
        local docker_usage=$(docker system df --format "table {{.Type}}\t{{.Size}}" | grep "Local Volumes" | awk '{print $3}' | sed 's/[^0-9.]//g' 2>/dev/null || echo "0")
    fi

    if [ ${#warnings[@]} -gt 0 ]; then
        echo "  Resource warnings: ${warnings[*]}"
        return 1
    fi

    echo "  Resource usage within normal limits"
    echo "  Disk: ${disk_usage}%, Memory: ${mem_usage}%"
    return 0
}

# Check 10: Log Analysis
check_logs_for_errors() {
    local containers_with_errors=()

    local containers=(
        "${STACK_NAME}-nginx-proxy"
        "${STACK_NAME}-keycloak"
        "${STACK_NAME}-grafana"
        "${STACK_NAME}-prometheus"
        "${STACK_NAME}-flask-site"
    )

    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            # Check for error patterns in recent logs
            local error_count=$(docker logs --tail 100 "$container" 2>&1 | grep -i -E "(error|exception|failed|fatal)" | wc -l)
            if [ "$error_count" -gt 5 ]; then
                containers_with_errors+=("$container:$error_count errors")
            fi
        fi
    done

    if [ ${#containers_with_errors[@]} -gt 0 ]; then
        echo "  Containers with errors: ${containers_with_errors[*]}"
        return 1
    fi

    echo "  No significant errors in recent logs"
    return 0
}

# Check 11: Configuration Files
check_configuration_files() {
    local config_issues=()

    # Check nginx config
    if [ -f "config/nginx/nginx.conf" ]; then
        if ! docker run --rm -v "$(pwd)/config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" nginx:alpine nginx -t >/dev/null 2>&1; then
            config_issues+=("nginx.conf syntax error")
        fi
    else
        config_issues+=("nginx.conf missing")
    fi

    # Check prometheus config
    if [ -f "config/prometheus/prometheus.yml" ]; then
        # Basic YAML syntax check
        if ! python3 -c "import yaml; yaml.safe_load(open('config/prometheus/prometheus.yml'))" >/dev/null 2>&1 && ! python -c "import yaml; yaml.safe_load(open('config/prometheus/prometheus.yml'))" >/dev/null 2>&1; then
            config_issues+=("prometheus.yml syntax error")
        fi
    else
        config_issues+=("prometheus.yml missing")
    fi

    if [ ${#config_issues[@]} -gt 0 ]; then
        echo "  Configuration issues: ${config_issues[*]}"
        return 1
    fi

    echo "  Configuration files are valid"
    return 0
}

# Check 12: Network Connectivity
check_network_connectivity() {
    local network_issues=()

    # Check if monitoring network exists
    if ! docker network ls | grep -q "${NETWORK_NAME:-monitoring}"; then
        network_issues+=("monitoring network missing")
    fi

    # Check container networking
    if docker ps -q >/dev/null 2>&1; then
        local containers=$(docker ps --format "{{.Names}}" | grep "^$STACK_NAME")
        for container in $containers; do
            # Test internal DNS resolution
            if ! docker exec "$container" nslookup keycloak >/dev/null 2>&1; then
                network_issues+=("$container: DNS resolution failed")
            fi
        done
    fi

    if [ ${#network_issues[@]} -gt 0 ]; then
        echo "  Network issues: ${network_issues[*]}"
        return 1
    fi

    echo "  Network connectivity is good"
    return 0
}

# Function to show detailed analysis
show_detailed_analysis() {
    echo ""
    echo -e "${PURPLE}=== DETAILED ANALYSIS ===${NC}"
    echo ""

    if confirm_action "Run detailed container inspection?"; then
        echo ""
        echo "Container resource usage:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "Unable to get container stats"

        echo ""
        echo "Container restart counts:"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$STACK_NAME"

        echo ""
        echo "Volume usage:"
        docker system df -v 2>/dev/null | grep -A 20 "Local Volumes:" || echo "Unable to get volume info"
    fi

    echo ""
    if confirm_action "Show recent error logs from containers?"; then
        echo ""
        local containers=$(docker ps --format "{{.Names}}" | grep "^$STACK_NAME")
        for container in $containers; do
            echo -e "${YELLOW}Recent errors from $container:${NC}"
            docker logs --tail 20 "$container" 2>&1 | grep -i -E "(error|exception|failed|fatal)" | tail -5 || echo "No recent errors"
            echo ""
        done
    fi
}

# Function to generate recommendations
generate_recommendations() {
    echo ""
    echo -e "${PURPLE}=== RECOMMENDATIONS ===${NC}"
    echo ""

    if [ $FAILED_CHECKS -gt 0 ]; then
        echo -e "${RED}Critical Issues Found:${NC}"
        echo "1. Review failed checks above and address critical issues first"
        echo "2. Check container logs: docker-compose logs <service-name>"
        echo "3. Restart failed services: docker-compose restart <service-name>"
        echo ""
    fi

    if [ $WARNING_CHECKS -gt 0 ]; then
        echo -e "${YELLOW}Warnings to Address:${NC}"
        echo "1. Monitor resource usage and clean up if needed"
        echo "2. Review configuration files for optimization"
        echo "3. Check for updates to container images"
        echo ""
    fi

    echo "General Maintenance:"
    echo "1. Regular backups: ./manage.sh (option 1)"
    echo "2. Update containers: docker-compose pull && docker-compose up -d"
    echo "3. Clean up: docker system prune -f"
    echo "4. Monitor logs: docker-compose logs -f"
    echo ""

    echo "Documentation:"
    echo "- Setup guide: guides/SETUP.md"
    echo "- Troubleshooting: guides/TROUBLESHOOTING.md"
    echo "- Full diagnostic log: $LOG_FILE"
}

# Function to show summary
show_summary() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Diagnostic Summary${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""

    echo -e "Total Checks: ${CYAN}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNING_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo ""

    local health_percentage=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

    if [ $health_percentage -ge 90 ]; then
        echo -e "Overall Health: ${GREEN}EXCELLENT ($health_percentage%)${NC}"
    elif [ $health_percentage -ge 75 ]; then
        echo -e "Overall Health: ${YELLOW}GOOD ($health_percentage%)${NC}"
    elif [ $health_percentage -ge 50 ]; then
        echo -e "Overall Health: ${YELLOW}FAIR ($health_percentage%)${NC}"
    else
        echo -e "Overall Health: ${RED}POOR ($health_percentage%)${NC}"
    fi

    echo ""
    echo "Diagnostic completed at: $(date)"
    echo "Log saved to: $LOG_FILE"
}

# Main diagnostic function
main() {
    show_header

    echo -e "${CYAN}This script will perform comprehensive health checks on your Docker monitoring stack.${NC}"
    echo ""

    # Initialize log file
    echo "Diagnostic started at $(date)" > "$LOG_FILE"
    echo "Project: $(basename "$PROJECT_ROOT")" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Run all checks
    echo -e "${YELLOW}Running diagnostic checks...${NC}"
    echo ""

    run_check "Docker Installation" check_docker_installation true
    run_check "Docker Daemon Status" check_docker_daemon true
    run_check "Project Files" check_project_files true
    run_check "Environment Configuration" check_environment_config true
    run_check "Container Status" check_container_status true
    run_check "Database Connections" check_database_connections true
    run_check "Service Endpoints" check_service_endpoints false
    run_check "External Access" check_external_access false
    run_check "Resource Usage" check_resource_usage false
    run_check "Log Analysis" check_logs_for_errors false
    run_check "Configuration Files" check_configuration_files false
    run_check "Network Connectivity" check_network_connectivity false

    # Show results
    show_summary

    # Optional detailed analysis
    show_detailed_analysis

    # Generate recommendations
    generate_recommendations

    echo ""
    echo -e "${BLUE}Diagnostic complete!${NC}"
}

# Check if in correct directory
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Error: docker-compose.yml not found${NC}"
    echo "Please run this script from your project root directory"
    exit 1
fi

# Load environment variables if available
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Run main function
main