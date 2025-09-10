#!/bin/bash

# =============================================================================
# MONITORING PORTAL - ENVIRONMENT CONFIGURATION GENERATOR
# =============================================================================
# This script generates a properly configured .env file for the monitoring portal
# with secure passwords and user-customizable settings.
#
# Usage: ./gen-env.sh [--unattended] [--domain DOMAIN] [--email EMAIL]
#
# Options:
#   --unattended: Run without interactive prompts (use defaults/provided values)
#   --domain: Set domain name (e.g., monitor.example.com)
#   --email: Set email address for notifications and SSL certificates
#   --rancher-url: Set Rancher server URL
#   --help: Show this help message

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

# Default values
DOMAIN=""
EMAIL=""
RANCHER_URL=""
UNATTENDED=false
OVERWRITE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --rancher-url)
            RANCHER_URL="$2"
            shift 2
            ;;
        --unattended)
            UNATTENDED=true
            shift
            ;;
        --force)
            OVERWRITE=true
            shift
            ;;
        --help|-h)
            cat << EOF
Monitoring Portal Environment Configuration Generator

Usage: $0 [OPTIONS]

This script generates a secure .env file for the monitoring portal with:
- Auto-generated secure passwords and secrets
- User-customizable domain and email settings
- Production-ready security defaults
- Rancher integration configuration

Options:
  --domain DOMAIN       Set the domain name (e.g., monitor.example.com)
  --email EMAIL         Set email for notifications and SSL certificates
  --rancher-url URL     Set Rancher server URL
  --unattended          Run without interactive prompts
  --force               Overwrite existing .env file without asking
  --help, -h            Show this help message

Examples:
  $0                                                    # Interactive mode
  $0 --domain monitor.company.com --email admin@company.com
  $0 --unattended --domain monitor.local --force      # Non-interactive

The script will create a .env file with secure, randomly generated passwords
and properly configured settings for production deployment.
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

success() {
    echo "[$(date '+%H:%M:%S')] SUCCESS: $1"
}

warn() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1"
}

print_header() {
    echo
    echo "=========================================="
    echo "   $1"
    echo "=========================================="
    echo
}

ask_user() {
    local question="$1"
    local default="$2"
    local response

    if [[ "$UNATTENDED" == "true" ]]; then
        echo "$default"
        return 0
    fi

    if [[ -n "$default" ]]; then
        read -p "$question [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$question: " response
        echo "$response"
    fi
}

ask_yes_no() {
    local question="$1"
    local default="$2"

    if [[ "$UNATTENDED" == "true" ]]; then
        echo "$default"
        return 0
    fi

    local prompt="$question"
    if [[ "$default" == "yes" ]]; then
        prompt="$prompt [Y/n]"
    else
        prompt="$prompt [y/N]"
    fi

    while true; do
        read -p "$prompt: " response

        # Use default if no response
        if [[ -z "$response" ]]; then
            response="$default"
        fi

        case "$response" in
            [Yy]|[Yy][Ee][Ss]|yes)
                echo "yes"
                return 0
                ;;
            [Nn]|[Nn][Oo]|no)
                echo "no"
                return 0
                ;;
            *)
                echo "Please answer yes or no"
                ;;
        esac
    done
}

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-25
}

generate_secret() {
    local length="${1:-48}"
    openssl rand -base64 "$length" | tr -d "=+/"
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+.*$ ]]; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# MAIN FUNCTIONS
# -----------------------------------------------------------------------------
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if openssl is available for password generation
    if ! command -v openssl >/dev/null 2>&1; then
        error "OpenSSL is required for password generation"
        echo "Please install openssl and try again"
        exit 1
    fi

    # Check if .env file exists
    if [[ -f "$ENV_FILE" ]] && [[ "$OVERWRITE" != "true" ]]; then
        echo
        warn "Environment file already exists: $ENV_FILE"

        if [[ "$UNATTENDED" != "true" ]]; then
            local overwrite
            overwrite=$(ask_yes_no "Do you want to overwrite it?" "no")
            if [[ "$overwrite" != "yes" ]]; then
                echo "Exiting without changes"
                exit 0
            fi
        else
            error "Environment file exists. Use --force to overwrite"
            exit 1
        fi
    fi

    success "Prerequisites check passed"
}

get_user_inputs() {
    if [[ "$UNATTENDED" == "true" ]] && [[ -z "$DOMAIN" ]]; then
        DOMAIN="monitor.example.com"
        EMAIL="admin@example.com"
        RANCHER_URL="https://rancher.example.com:443"
        return 0
    fi

    print_header "Configuration Input"

    echo "Please provide the following information for your monitoring portal:"
    echo

    # Get domain
    while true; do
        if [[ -z "$DOMAIN" ]]; then
            DOMAIN=$(ask_user "Enter your domain name (e.g., monitor.company.com)" "monitor.example.com")
        fi

        if validate_domain "$DOMAIN"; then
            break
        else
            echo "Invalid domain format. Please enter a valid domain name."
            DOMAIN=""
        fi
    done

    # Get email
    while true; do
        if [[ -z "$EMAIL" ]]; then
            local default_email="admin@${DOMAIN#*.}"
            EMAIL=$(ask_user "Enter your email address for notifications" "$default_email")
        fi

        if validate_email "$EMAIL"; then
            break
        else
            echo "Invalid email format. Please enter a valid email address."
            EMAIL=""
        fi
    done

    # Get Rancher URL
    while true; do
        if [[ -z "$RANCHER_URL" ]]; then
            RANCHER_URL=$(ask_user "Enter your Rancher server URL" "https://rancher.${DOMAIN#*.}:443")
        fi

        if validate_url "$RANCHER_URL"; then
            break
        else
            echo "Invalid URL format. Please enter a valid URL (http:// or https://)"
            RANCHER_URL=""
        fi
    done

    # Show configuration summary
    echo
    echo "Configuration Summary:"
    echo "   Domain: $DOMAIN"
    echo "   Email: $EMAIL"
    echo "   Rancher URL: $RANCHER_URL"
    echo

    if [[ "$UNATTENDED" != "true" ]]; then
        local confirm
        confirm=$(ask_yes_no "Continue with this configuration?" "yes")
        if [[ "$confirm" != "yes" ]]; then
            echo "Configuration cancelled"
            exit 0
        fi
    fi
}

generate_passwords() {
    log "Generating secure passwords and secrets..."

    # Generate all passwords and secrets
    KEYCLOAK_ADMIN_PASSWORD=$(generate_password 32)
    GRAFANA_ADMIN_PASSWORD=$(generate_password 32)
    KEYCLOAK_DB_PASSWORD=$(generate_password 32)
    WEBAPP_SECRET_KEY=$(generate_secret 64)
    GRAFANA_CLIENT_SECRET=$(generate_password 24)
    WEBAPP_CLIENT_SECRET=$(generate_password 24)

    success "Secure passwords generated"
}

create_env_file() {
    log "Creating environment file..."

    cat > "$ENV_FILE" << EOF
# =============================================================================
# MONITORING PORTAL - ENVIRONMENT CONFIGURATION
# =============================================================================
# Generated by gen-env.sh on $(date)
#
# SECURITY NOTICE: This file contains sensitive passwords and secrets.
# Keep it secure and never commit to version control!

# -----------------------------------------------------------------------------
# BASIC CONFIGURATION
# -----------------------------------------------------------------------------
DOMAIN=$DOMAIN
COMPOSE_PROJECT_NAME=monitoring-portal

# -----------------------------------------------------------------------------
# SECURITY CREDENTIALS - AUTO-GENERATED SECURE PASSWORDS
# -----------------------------------------------------------------------------
KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD
KEYCLOAK_DB_PASSWORD=$KEYCLOAK_DB_PASSWORD
WEBAPP_SECRET_KEY=$WEBAPP_SECRET_KEY

# OAuth Client Secrets
GRAFANA_CLIENT_SECRET=$GRAFANA_CLIENT_SECRET
WEBAPP_CLIENT_SECRET=$WEBAPP_CLIENT_SECRET

# -----------------------------------------------------------------------------
# SSL CERTIFICATE CONFIGURATION
# -----------------------------------------------------------------------------
# Options: 'internal' (default) or 'letsencrypt'
CERT_RESOLVER=internal
# Required for Let's Encrypt
ACME_EMAIL=$EMAIL

# -----------------------------------------------------------------------------
# KEYCLOAK CONFIGURATION
# -----------------------------------------------------------------------------
KEYCLOAK_VERSION=23.0
KEYCLOAK_ADMIN=admin
KEYCLOAK_REALM=monitoring
KEYCLOAK_DB_NAME=keycloak
KEYCLOAK_DB_USER=keycloak
GRAFANA_CLIENT_ID=grafana
WEBAPP_CLIENT_ID=webapp

# -----------------------------------------------------------------------------
# MONITORING CONFIGURATION
# -----------------------------------------------------------------------------
GRAFANA_VERSION=latest
GRAFANA_ADMIN_USER=admin
PROMETHEUS_VERSION=latest
PROMETHEUS_RETENTION_TIME=15d
PROMETHEUS_RETENTION_SIZE=10GB
PROMETHEUS_SCRAPE_INTERVAL=15s

# -----------------------------------------------------------------------------
# EXTERNAL SERVICES
# -----------------------------------------------------------------------------
RANCHER_SERVER_URL=$RANCHER_URL

# -----------------------------------------------------------------------------
# ENVIRONMENT-SPECIFIC SETTINGS
# -----------------------------------------------------------------------------
FLASK_ENV=production
FLASK_DEBUG=false
LOG_LEVEL=INFO
TRAEFIK_LOG_LEVEL=INFO

# Session Security
SESSION_COOKIE_SECURE=true
SESSION_COOKIE_HTTPONLY=true
SESSION_COOKIE_SAMESITE=Lax

# Rate Limiting
TRAEFIK_RATE_LIMIT_BURST=100
TRAEFIK_RATE_LIMIT_AVERAGE=50

# -----------------------------------------------------------------------------
# NOTIFICATIONS (Configure as needed)
# -----------------------------------------------------------------------------
NOTIFICATION_EMAIL=$EMAIL
# SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# -----------------------------------------------------------------------------
# MAINTENANCE SETTINGS
# -----------------------------------------------------------------------------
BACKUP_RETENTION_DAYS=30
AUTO_RESTART=true
AUTO_BACKUP=false

# -----------------------------------------------------------------------------
# NETWORK AND PORTS (Usually don't need to change)
# -----------------------------------------------------------------------------
NETWORK_NAME=monitoring
TRAEFIK_VERSION=v3.0
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443
TRAEFIK_DASHBOARD_PORT=8080
WEBAPP_PORT=8000
POSTGRES_VERSION=15-alpine

# -----------------------------------------------------------------------------
# MONITORING LABELS
# -----------------------------------------------------------------------------
PROMETHEUS_EXTERNAL_LABEL_MONITOR=monitoring-portal
PROMETHEUS_EXTERNAL_LABEL_ENV=production
EOF

    # Set secure permissions
    chmod 600 "$ENV_FILE"

    success "Environment file created: $ENV_FILE"
}

display_credentials() {
    print_header "GENERATED CREDENTIALS"

    cat << EOF
Important: Save these credentials securely!

Admin Credentials:
   Keycloak Admin: admin / $KEYCLOAK_ADMIN_PASSWORD
   Grafana Admin: admin / $GRAFANA_ADMIN_PASSWORD

Access URLs (after deployment):
   Main Portal: https://$DOMAIN
   Keycloak Admin: https://$DOMAIN/auth/admin
   Grafana: https://$DOMAIN/grafana
   Prometheus: https://$DOMAIN/prometheus

Configuration:
   Domain: $DOMAIN
   Email: $EMAIL
   Rancher: $RANCHER_URL

Security Notes:
   - All passwords are randomly generated and secure
   - Environment file has restricted permissions (600)
   - Never commit .env files to version control
   - Change default passwords after first login

Next Steps:
   1. Review the generated .env file
   2. Deploy with: docker compose up -d
   3. Configure SSL certificates if needed
   4. Set up monitoring targets in Prometheus
   5. Configure alerting rules in Grafana
EOF
}

create_password_backup() {
    local backup_file="$SCRIPT_DIR/credentials-$(date +%Y%m%d-%H%M%S).txt"

    cat > "$backup_file" << EOF
# Monitoring Portal Credentials
# Generated: $(date)
# Domain: $DOMAIN

Keycloak Admin: admin / $KEYCLOAK_ADMIN_PASSWORD
Grafana Admin: admin / $GRAFANA_ADMIN_PASSWORD

Access URLs:
- Main Portal: https://$DOMAIN
- Keycloak Admin: https://$DOMAIN/auth/admin
- Grafana: https://$DOMAIN/grafana
- Prometheus: https://$DOMAIN/prometheus

IMPORTANT: Delete this file after saving credentials securely!
EOF

    chmod 600 "$backup_file"
    echo
    echo "Credentials backup saved to: $backup_file"
    echo "Delete this file after saving credentials securely!"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    print_header "MONITORING PORTAL ENVIRONMENT GENERATOR"

    log "Starting environment configuration generation..."

    # Run setup steps
    check_prerequisites
    get_user_inputs
    generate_passwords
    create_env_file

    # Show results
    display_credentials

    # Offer to create backup
    if [[ "$UNATTENDED" != "true" ]]; then
        local create_backup
        create_backup=$(ask_yes_no "Create a credentials backup file?" "yes")
        if [[ "$create_backup" == "yes" ]]; then
            create_password_backup
        fi
    fi

    echo
    success "Environment configuration completed successfully!"
    echo
    echo "Your monitoring portal is ready to deploy:"
    echo "   docker compose up -d"
    echo
}

# Handle script interruption
trap 'error "Environment generation interrupted"; exit 1' INT TERM

# Run main function
main "$@"