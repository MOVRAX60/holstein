#!/bin/bash

# =============================================================================
# MONITORING PORTAL - PERMISSIONS CHECK AND FIX SCRIPT
# =============================================================================
# This script checks and corrects file permissions for the monitoring portal
# ensuring security best practices are followed
#
# Usage: ./fix-permissions.sh [--check-only] [--fix] [--verbose]
# Options:
#   --check-only: Only check permissions, don't fix anything
#   --fix: Automatically fix permission issues
#   --verbose: Show detailed output

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/logs/permissions.log"

# Parse arguments
CHECK_ONLY=false
FIX_ISSUES=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --fix)
            FIX_ISSUES=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            cat << EOF
Monitoring Portal Permissions Check and Fix Script

Usage: $0 [OPTIONS]

Options:
  --check-only      Only check permissions, don't fix anything
  --fix            Automatically fix permission issues
  --verbose, -v     Show detailed output for all files
  --help, -h        Show this help message

Examples:
  $0 --check-only   # Check permissions without fixing
  $0 --fix          # Check and fix permissions automatically
  $0 --verbose      # Show detailed output

Security Standards Applied:
  - Certificate files (.crt): 644 (world readable)
  - Private keys (.key): 600 (owner only)
  - Environment files (.env): 600 (owner only)
  - Scripts (.sh): 755 (executable)
  - Config files (.yml, .yaml, .json): 644 (world readable)
  - Log directories: 755 (writable by owner)
  - Sensitive directories: 750 (group readable)
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

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ISSUES_FOUND=false
FIXES_APPLIED=0

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$TIMESTAMP] VERBOSE: $1" | tee -a "$LOG_FILE"
    fi
}

error() {
    echo "[$TIMESTAMP] ❌ ERROR: $1" | tee -a "$LOG_FILE"
    ISSUES_FOUND=true
}

warn() {
    echo "[$TIMESTAMP] ⚠️  WARNING: $1" | tee -a "$LOG_FILE"
    ISSUES_FOUND=true
}

success() {
    echo "[$TIMESTAMP] ✅ SUCCESS: $1" | tee -a "$LOG_FILE"
}

info() {
    echo "[$TIMESTAMP] ℹ️  INFO: $1" | tee -a "$LOG_FILE"
}

fix_applied() {
    echo "[$TIMESTAMP] 🔧 FIXED: $1" | tee -a "$LOG_FILE"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
}

print_header() {
    echo
    echo "🔒 ========================================"
    echo "   $1"
    echo "========================================"
    echo
}

# -----------------------------------------------------------------------------
# PERMISSION CHECK FUNCTIONS
# -----------------------------------------------------------------------------
check_file_permission() {
    local file="$1"
    local expected_perm="$2"
    local description="$3"

    if [[ ! -e "$file" ]]; then
        verbose "File not found (skipping): $file"
        return 0
    fi

    local current_perm
    current_perm=$(stat -c "%a" "$file" 2>/dev/null || echo "000")

    verbose "Checking $file (expected: $expected_perm, current: $current_perm)"

    if [[ "$current_perm" == "$expected_perm" ]]; then
        verbose "$description: $file ✅"
        return 0
    else
        warn "$description permission incorrect: $file (expected: $expected_perm, found: $current_perm)"

        if [[ "$FIX_ISSUES" == "true" ]]; then
            if chmod "$expected_perm" "$file" 2>/dev/null; then
                fix_applied "$description permission fixed: $file ($current_perm → $expected_perm)"
                return 0
            else
                error "Failed to fix permission for: $file"
                return 1
            fi
        fi
        return 1
    fi
}

check_directory_permission() {
    local dir="$1"
    local expected_perm="$2"
    local description="$3"

    if [[ ! -d "$dir" ]]; then
        verbose "Directory not found (skipping): $dir"
        return 0
    fi

    local current_perm
    current_perm=$(stat -c "%a" "$dir" 2>/dev/null || echo "000")

    verbose "Checking directory $dir (expected: $expected_perm, current: $current_perm)"

    if [[ "$current_perm" == "$expected_perm" ]]; then
        verbose "$description: $dir ✅"
        return 0
    else
        warn "$description permission incorrect: $dir (expected: $expected_perm, found: $current_perm)"

        if [[ "$FIX_ISSUES" == "true" ]]; then
            if chmod "$expected_perm" "$dir" 2>/dev/null; then
                fix_applied "$description permission fixed: $dir ($current_perm → $expected_perm)"
                return 0
            else
                error "Failed to fix permission for: $dir"
                return 1
            fi
        fi
        return 1
    fi
}

check_ownership() {
    local file="$1"
    local expected_owner="$2"
    local description="$3"

    if [[ ! -e "$file" ]]; then
        return 0
    fi

    local current_owner
    current_owner=$(stat -c "%U" "$file" 2>/dev/null || echo "unknown")

    if [[ "$current_owner" == "$expected_owner" ]] || [[ "$expected_owner" == "*" ]]; then
        verbose "$description ownership correct: $file (owner: $current_owner)"
        return 0
    else
        warn "$description ownership incorrect: $file (expected: $expected_owner, found: $current_owner)"

        if [[ "$FIX_ISSUES" == "true" ]]; then
            if chown "$expected_owner" "$file" 2>/dev/null; then
                fix_applied "$description ownership fixed: $file ($current_owner → $expected_owner)"
                return 0
            else
                error "Failed to fix ownership for: $file (may need sudo)"
                return 1
            fi
        fi
        return 1
    fi
}

# -----------------------------------------------------------------------------
# SPECIFIC PERMISSION CHECKS
# -----------------------------------------------------------------------------
check_certificate_files() {
    print_header "CERTIFICATE FILES"

    info "Checking SSL certificate files..."

    # Find all certificate files
    if [[ -d "$PROJECT_DIR/certs" ]]; then
        # Check certificate files (.crt) - should be world readable
        find "$PROJECT_DIR/certs" -name "*.crt" -type f 2>/dev/null | while read -r cert_file; do
            check_file_permission "$cert_file" "644" "Certificate file"
        done

        # Check private key files (.key) - should be owner only
        find "$PROJECT_DIR/certs" -name "*.key" -type f 2>/dev/null | while read -r key_file; do
            check_file_permission "$key_file" "600" "Private key file"
        done

        # Check PEM files - should be readable
        find "$PROJECT_DIR/certs" -name "*.pem" -type f 2>/dev/null | while read -r pem_file; do
            if [[ "$pem_file" == *"key"* ]] || [[ "$pem_file" == *"private"* ]]; then
                check_file_permission "$pem_file" "600" "Private PEM file"
            else
                check_file_permission "$pem_file" "644" "Public PEM file"
            fi
        done

        # Check acme.json (Let's Encrypt) - should be owner only
        check_file_permission "$PROJECT_DIR/certs/acme.json" "600" "ACME configuration file"

        # Check certs directory itself
        check_directory_permission "$PROJECT_DIR/certs" "755" "Certificates directory"

    else
        warn "Certificates directory not found: $PROJECT_DIR/certs"
    fi
}

check_environment_files() {
    print_header "ENVIRONMENT FILES"

    info "Checking environment configuration files..."

    # Environment files - should be owner only (contain secrets)
    for env_file in ".env" ".env.local" ".env.production" ".env.development" ".env.staging"; do
        check_file_permission "$PROJECT_DIR/$env_file" "600" "Environment file"
    done

    # Environment example files - can be world readable
    check_file_permission "$PROJECT_DIR/.env.example" "644" "Environment example file"

    # Backup environment files
    find "$PROJECT_DIR" -name "*.env.backup*" -type f 2>/dev/null | while read -r backup_file; do
        check_file_permission "$backup_file" "600" "Environment backup file"
    done
}

check_script_files() {
    print_header "SCRIPT FILES"

    info "Checking script files..."

    # All shell scripts should be executable
    find "$PROJECT_DIR" -name "*.sh" -type f 2>/dev/null | while read -r script_file; do
        check_file_permission "$script_file" "755" "Script file"
    done

    # Main guides script
    check_file_permission "$PROJECT_DIR/setup.sh" "755" "Setup script"

    # Make sure Makefile is readable
    check_file_permission "$PROJECT_DIR/Makefile" "644" "Makefile"
}

check_configuration_files() {
    print_header "CONFIGURATION FILES"

    info "Checking configuration files..."

    # Docker Compose files
    find "$PROJECT_DIR" -name "docker-compose*.yml" -type f 2>/dev/null | while read -r compose_file; do
        check_file_permission "$compose_file" "644" "Docker Compose file"
    done

    # YAML configuration files
    find "$PROJECT_DIR" -name "*.yml" -o -name "*.yaml" -type f 2>/dev/null | while read -r yaml_file; do
        # Skip backup files
        if [[ "$yaml_file" != *".backup."* ]]; then
            check_file_permission "$yaml_file" "644" "YAML configuration file"
        fi
    done

    # JSON configuration files
    find "$PROJECT_DIR" -name "*.json" -type f 2>/dev/null | while read -r json_file; do
        # Skip acme.json (handled separately)
        if [[ "$json_file" != *"acme.json"* ]]; then
            check_file_permission "$json_file" "644" "JSON configuration file"
        fi
    done

    # Python files
    find "$PROJECT_DIR" -name "*.py" -type f 2>/dev/null | while read -r py_file; do
        check_file_permission "$py_file" "644" "Python file"
    done

    # HTML templates
    find "$PROJECT_DIR" -name "*.html" -type f 2>/dev/null | while read -r html_file; do
        check_file_permission "$html_file" "644" "HTML template"
    done

    # Requirements files
    find "$PROJECT_DIR" -name "requirements*.txt" -type f 2>/dev/null | while read -r req_file; do
        check_file_permission "$req_file" "644" "Requirements file"
    done

    # Dockerfile
    find "$PROJECT_DIR" -name "Dockerfile*" -type f 2>/dev/null | while read -r dockerfile; do
        check_file_permission "$dockerfile" "644" "Dockerfile"
    done
}

check_directories() {
    print_header "DIRECTORIES"

    info "Checking directory permissions..."

    # Main directories
    local directories=(
        "$PROJECT_DIR:755:Project root"
        "$PROJECT_DIR/scripts:755:Scripts directory"
        "$PROJECT_DIR/traefik:755:Traefik configuration"
        "$PROJECT_DIR/prometheus:755:Prometheus configuration"
        "$PROJECT_DIR/grafana:755:Grafana configuration"
        "$PROJECT_DIR/webapp:755:Web application"
        "$PROJECT_DIR/setup:755:Setup guides"
    )

    for dir_info in "${directories[@]}"; do
        IFS=':' read -r dir perm desc <<< "$dir_info"
        check_directory_permission "$dir" "$perm" "$desc"
    done

    # Sensitive directories (logs, backups)
    local sensitive_dirs=(
        "$PROJECT_DIR/logs:755:Logs directory"
        "$PROJECT_DIR/backups:750:Backups directory"
        "$PROJECT_DIR/data:755:Data directory"
    )

    for dir_info in "${sensitive_dirs[@]}"; do
        IFS=':' read -r dir perm desc <<< "$dir_info"
        check_directory_permission "$dir" "$perm" "$desc"
    done

    # Create missing directories with correct permissions
    if [[ "$FIX_ISSUES" == "true" ]]; then
        local required_dirs=(
            "logs:755"
            "backups:750"
            "certs:755"
            "data:755"
        )

        for dir_info in "${required_dirs[@]}"; do
            IFS=':' read -r dir perm <<< "$dir_info"
            local full_path="$PROJECT_DIR/$dir"

            if [[ ! -d "$full_path" ]]; then
                if mkdir -p "$full_path" && chmod "$perm" "$full_path"; then
                    fix_applied "Created missing directory: $full_path (permission: $perm)"
                else
                    error "Failed to create directory: $full_path"
                fi
            fi
        done
    fi
}

check_log_files() {
    print_header "LOG FILES"

    info "Checking log files..."

    # Log files should be writable by owner, readable by group
    find "$PROJECT_DIR/logs" -name "*.log" -type f 2>/dev/null | while read -r log_file; do
        check_file_permission "$log_file" "644" "Log file"
    done

    # Log rotation files
    find "$PROJECT_DIR/logs" -name "*.log.*" -type f 2>/dev/null | while read -r log_file; do
        check_file_permission "$log_file" "644" "Rotated log file"
    done
}

check_backup_files() {
    print_header "BACKUP FILES"

    info "Checking backup files..."

    # Backup archives should be readable only by owner (may contain sensitive data)
    find "$PROJECT_DIR/backups" -name "*.tar.gz" -type f 2>/dev/null | while read -r backup_file; do
        check_file_permission "$backup_file" "600" "Backup archive"
    done

    # SQL dumps should be owner only
    find "$PROJECT_DIR/backups" -name "*.sql" -type f 2>/dev/null | while read -r sql_file; do
        check_file_permission "$sql_file" "600" "Database dump"
    done

    # Configuration backups
    find "$PROJECT_DIR" -name "*.backup.*" -type f 2>/dev/null | while read -r backup_file; do
        if [[ "$backup_file" == *".env"* ]]; then
            check_file_permission "$backup_file" "600" "Environment backup"
        else
            check_file_permission "$backup_file" "644" "Configuration backup"
        fi
    done
}

check_git_files() {
    print_header "GIT FILES"

    info "Checking Git-related files..."

    # Git files
    check_file_permission "$PROJECT_DIR/.gitignore" "644" "Git ignore file"
    check_file_permission "$PROJECT_DIR/.gitattributes" "644" "Git attributes file"

    # Git hooks (if any)
    if [[ -d "$PROJECT_DIR/.git/hooks" ]]; then
        find "$PROJECT_DIR/.git/hooks" -type f -executable 2>/dev/null | while read -r hook_file; do
            check_file_permission "$hook_file" "755" "Git hook"
        done
    fi
}

check_documentation_files() {
    print_header "DOCUMENTATION FILES"

    info "Checking documentation files..."

    # Markdown files should be world readable
    find "$PROJECT_DIR" -name "*.md" -type f 2>/dev/null | while read -r md_file; do
        check_file_permission "$md_file" "644" "Documentation file"
    done

    # Text files
    find "$PROJECT_DIR" -name "*.txt" -type f 2>/dev/null | while read -r txt_file; do
        check_file_permission "$txt_file" "644" "Text file"
    done
}

# -----------------------------------------------------------------------------
# OWNERSHIP CHECKS
# -----------------------------------------------------------------------------
check_ownership_consistency() {
    print_header "OWNERSHIP CONSISTENCY"

    if [[ "$EUID" -eq 0 ]]; then
        warn "Running as root - ownership checks may not be meaningful"
        return 0
    fi

    info "Checking file ownership consistency..."

    local current_user
    current_user=$(whoami)

    # Key files should be owned by current user
    local important_files=(
        "$PROJECT_DIR/.env"
        "$PROJECT_DIR/docker-compose.yml"
        "$PROJECT_DIR/Makefile"
    )

    for file in "${important_files[@]}"; do
        if [[ -f "$file" ]]; then
            check_ownership "$file" "$current_user" "Important file"
        fi
    done

    # Certificates should be owned by current user or root
    if [[ -d "$PROJECT_DIR/certs" ]]; then
        find "$PROJECT_DIR/certs" -type f 2>/dev/null | while read -r cert_file; do
            local owner
            owner=$(stat -c "%U" "$cert_file" 2>/dev/null || echo "unknown")
            if [[ "$owner" != "$current_user" ]] && [[ "$owner" != "root" ]]; then
                warn "Certificate file has unexpected owner: $cert_file (owner: $owner)"
            fi
        done
    fi
}

# -----------------------------------------------------------------------------
# SPECIAL SECURITY CHECKS
# -----------------------------------------------------------------------------
check_security_issues() {
    print_header "SECURITY ISSUES"

    info "Checking for common security issues..."

    # Check for world-writable files
    local world_writable
    world_writable=$(find "$PROJECT_DIR" -type f -perm -002 2>/dev/null | head -10)

    if [[ -n "$world_writable" ]]; then
        warn "Found world-writable files (potential security risk):"
        echo "$world_writable" | while read -r file; do
            warn "  $file"
            if [[ "$FIX_ISSUES" == "true" ]]; then
                chmod o-w "$file"
                fix_applied "Removed world-write permission: $file"
            fi
        done
    else
        success "No world-writable files found"
    fi

    # Check for files with SUID/SGID bits (suspicious in this context)
    local suid_files
    suid_files=$(find "$PROJECT_DIR" -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null)

    if [[ -n "$suid_files" ]]; then
        warn "Found files with SUID/SGID bits (unusual for this project):"
        echo "$suid_files" | while read -r file; do
            warn "  $file"
        done
    else
        success "No SUID/SGID files found"
    fi

    # Check for overly permissive directories
    local permissive_dirs
    permissive_dirs=$(find "$PROJECT_DIR" -type d -perm -777 2>/dev/null)

    if [[ -n "$permissive_dirs" ]]; then
        warn "Found overly permissive directories (777):"
        echo "$permissive_dirs" | while read -r dir; do
            warn "  $dir"
            if [[ "$FIX_ISSUES" == "true" ]]; then
                chmod 755 "$dir"
                fix_applied "Fixed overly permissive directory: $dir"
            fi
        done
    else
        success "No overly permissive directories found"
    fi
}

# -----------------------------------------------------------------------------
# SUMMARY AND RECOMMENDATIONS
# -----------------------------------------------------------------------------
generate_summary() {
    print_header "SUMMARY AND RECOMMENDATIONS"

    if [[ "$ISSUES_FOUND" == "false" ]]; then
        success "All permissions are correctly configured! 🎉"
        echo
        echo "✅ Your monitoring portal has proper security permissions"
        echo "✅ Certificate files are properly secured"
        echo "✅ Environment files are protected"
        echo "✅ No security issues detected"
    else
        if [[ "$FIX_ISSUES" == "true" ]]; then
            if [[ $FIXES_APPLIED -gt 0 ]]; then
                success "$FIXES_APPLIED permission issues were automatically fixed"
                echo
                echo "🔧 Applied fixes:"
                echo "   - Corrected file permissions"
                echo "   - Fixed directory permissions"
                echo "   - Secured sensitive files"
                echo "   - Created missing directories"
                echo
                echo "🔍 Run the script again to verify all fixes were applied correctly:"
                echo "   $0 --check-only"
            else
                warn "No fixes could be applied automatically"
                echo
                echo "🔧 Manual intervention may be required:"
                echo "   - Some files may need sudo to fix"
                echo "   - Check file ownership issues"
                echo "   - Verify disk permissions"
            fi
        else
            warn "Permission issues were found but not fixed"
            echo
            echo "🔧 To fix issues automatically:"
            echo "   $0 --fix"
            echo
            echo "🔧 To fix with detailed output:"
            echo "   $0 --fix --verbose"
        fi
    fi

    echo
    echo "📋 Security Recommendations:"
    echo "   - Run this script regularly to maintain security"
    echo "   - Always use --check-only before --fix in production"
    echo "   - Monitor the logs/permissions.log file for changes"
    echo "   - Backup your .env file securely (contains passwords)"
    echo "   - Ensure only authorized users have access to this directory"
    echo
    echo "📁 Log file: $LOG_FILE"
    echo "🕒 Check completed at: $(date)"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    # Create log directory if needed
    mkdir -p "$(dirname "$LOG_FILE")"

    echo "🔒 Monitoring Portal - Permissions Check and Fix"
    echo "================================================"
    echo

    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo "🔍 Mode: Check Only (no fixes will be applied)"
    elif [[ "$FIX_ISSUES" == "true" ]]; then
        echo "🔧 Mode: Check and Fix"
    else
        echo "🔍 Mode: Check Only (use --fix to apply fixes)"
    fi

    echo "📁 Project: $PROJECT_DIR"
    echo "📊 Verbose: $VERBOSE"
    echo

    log "=== PERMISSIONS CHECK STARTED ==="
    log "Mode: $(if [[ "$FIX_ISSUES" == "true" ]]; then echo "Fix"; else echo "Check Only"; fi)"
    log "Verbose: $VERBOSE"

    # Run all checks
    check_certificate_files
    check_environment_files
    check_script_files
    check_configuration_files
    check_directories
    check_log_files
    check_backup_files
    check_git_files
    check_documentation_files
    check_ownership_consistency
    check_security_issues

    # Generate summary
    generate_summary

    log "=== PERMISSIONS CHECK COMPLETED ==="
    log "Issues found: $ISSUES_FOUND"
    log "Fixes applied: $FIXES_APPLIED"

    # Exit with appropriate code
    if [[ "$ISSUES_FOUND" == "true" ]] && [[ "$FIX_ISSUES" == "false" ]]; then
        exit 1  # Issues found but not fixed
    elif [[ "$ISSUES_FOUND" == "true" ]] && [[ "$FIXES_APPLIED" -eq 0 ]]; then
        exit 2  # Issues found but couldn't fix them
    else
        exit 0  # All good or issues were fixed
    fi
}

# Handle script interruption
trap 'error "Permission check interrupted"; exit 1' INT TERM

# Run main function
main "$@"