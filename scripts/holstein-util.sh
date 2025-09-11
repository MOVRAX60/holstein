#!/bin/bash

# Interactive Project Management Script
# Provides backup, restore, maintenance, and setup functions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="$(pwd)"
BACKUP_DIR="$PROJECT_ROOT/backups"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"
ENV_FILE="$PROJECT_ROOT/.env"

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Docker Project Management Script${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo -e "${CYAN}Project: $(basename "$PROJECT_ROOT")${NC}"
    echo -e "${CYAN}Path: $PROJECT_ROOT${NC}"
    echo ""
}

# Function to confirm action
confirm_action() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Function to pause for user to read output
pause_for_user() {
    echo ""
    read -p "Press Enter to continue..." -r
}

# Function to create backup
create_backup() {
    show_header
    echo -e "${YELLOW}=== BACKUP PROJECT ===${NC}"
    echo ""

    # Check if project root exists
    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        echo -e "${RED}Error: Not in a valid Docker project directory${NC}"
        pause_for_user
        return 1
    fi

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Generate backup filename with timestamp
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="backup_${timestamp}"
    local backup_file="${BACKUP_DIR}/${backup_name}.zip"

    echo "Backup will be created as: $backup_file"
    echo ""
    echo "Items to backup:"
    echo "  - docker-compose.yml"
    echo "  - .env (if exists)"
    echo "  - config/ directory"
    echo "  - scripts/ directory"
    echo "  - webapp/ directory"
    echo "  - guides/ directory"
    echo ""
    echo -e "${RED}Note: data/ directory will be excluded (contains container volumes)${NC}"
    echo ""

    if confirm_action "Create backup now?"; then
        echo ""
        echo "Creating backup..."

        # Create temporary directory for backup staging
        local temp_dir=$(mktemp -d)
        local staging_dir="$temp_dir/$backup_name"
        mkdir -p "$staging_dir"

        # Copy files to staging directory
        echo "Copying files..."
        cp docker-compose.yml "$staging_dir/" 2>/dev/null || true
        cp .env "$staging_dir/" 2>/dev/null || true
        cp .env.example "$staging_dir/" 2>/dev/null || true
        cp -r config "$staging_dir/" 2>/dev/null || true
        cp -r scripts "$staging_dir/" 2>/dev/null || true
        cp -r webapp "$staging_dir/" 2>/dev/null || true
        cp -r guides "$staging_dir/" 2>/dev/null || true

        # Create backup info file
        cat > "$staging_dir/backup_info.txt" << EOF
Backup created: $(date)
Project: $(basename "$PROJECT_ROOT")
Docker Compose version: $(docker-compose --version 2>/dev/null || echo "Not available")
Git commit: $(git rev-parse HEAD 2>/dev/null || echo "Not a git repository")
Git branch: $(git branch --show-current 2>/dev/null || echo "Not a git repository")
EOF

        # Create ZIP file
        echo "Creating ZIP archive..."
        cd "$temp_dir"
        zip -r "$backup_file" "$backup_name" >/dev/null

        # Cleanup
        rm -rf "$temp_dir"

        # Verify backup
        if [ -f "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            echo -e "${GREEN}✓ Backup created successfully${NC}"
            echo "  File: $backup_file"
            echo "  Size: $size"
        else
            echo -e "${RED}✗ Backup failed${NC}"
        fi
    else
        echo "Backup cancelled."
    fi

    pause_for_user
}

# Function to restore backup
restore_backup() {
    show_header
    echo -e "${YELLOW}=== RESTORE BACKUP ===${NC}"
    echo ""

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${RED}No backups found in $BACKUP_DIR${NC}"
        pause_for_user
        return 1
    fi

    echo "Available backups:"
    echo ""
    local backups=($(ls -1 "$BACKUP_DIR"/*.zip 2>/dev/null | sort -r))

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}No backup files found${NC}"
        pause_for_user
        return 1
    fi

    for i in "${!backups[@]}"; do
        local backup_file="${backups[$i]}"
        local filename=$(basename "$backup_file")
        local size=$(du -h "$backup_file" | cut -f1)
        local date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  $((i+1)). $filename ($size) - $date"
    done

    echo ""
    read -p "Select backup to restore (1-${#backups[@]}) or 0 to cancel: " choice

    if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#backups[@]}" ]; then
        local selected_backup="${backups[$((choice-1))]}"
        echo ""
        echo "Selected backup: $(basename "$selected_backup")"
        echo ""
        echo -e "${RED}WARNING: This will overwrite current project files!${NC}"
        echo "Files that will be replaced:"
        echo "  - docker-compose.yml"
        echo "  - .env"
        echo "  - config/ directory"
        echo "  - scripts/ directory"
        echo "  - webapp/ directory"
        echo "  - guides/ directory"
        echo ""

        if confirm_action "Restore this backup? THIS CANNOT BE UNDONE!"; then
            echo ""
            echo "Stopping Docker services..."
            docker-compose down 2>/dev/null || true

            echo "Extracting backup..."
            local temp_dir=$(mktemp -d)
            cd "$temp_dir"
            unzip -q "$selected_backup"

            # Find the backup directory (should be the only directory)
            local backup_content_dir=$(find . -maxdepth 1 -type d ! -name '.' | head -n1)

            if [ -n "$backup_content_dir" ]; then
                cd "$backup_content_dir"

                echo "Restoring files..."
                cp -f docker-compose.yml "$PROJECT_ROOT/" 2>/dev/null || true
                cp -f .env "$PROJECT_ROOT/" 2>/dev/null || true
                cp -f .env.example "$PROJECT_ROOT/" 2>/dev/null || true

                # Remove and restore directories
                rm -rf "$PROJECT_ROOT/config" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/webapp" "$PROJECT_ROOT/guides" 2>/dev/null || true
                cp -r config "$PROJECT_ROOT/" 2>/dev/null || true
                cp -r scripts "$PROJECT_ROOT/" 2>/dev/null || true
                cp -r webapp "$PROJECT_ROOT/" 2>/dev/null || true
                cp -r guides "$PROJECT_ROOT/" 2>/dev/null || true

                echo -e "${GREEN}✓ Backup restored successfully${NC}"

                # Show backup info if available
                if [ -f "backup_info.txt" ]; then
                    echo ""
                    echo "Backup information:"
                    cat backup_info.txt
                fi
            else
                echo -e "${RED}✗ Invalid backup format${NC}"
            fi

            # Cleanup
            rm -rf "$temp_dir"
        else
            echo "Restore cancelled."
        fi
    else
        echo "Restore cancelled."
    fi

    pause_for_user
}

# Function to fix line endings
fix_line_endings() {
    show_header
    echo -e "${YELLOW}=== FIX LINE ENDINGS ===${NC}"
    echo ""

    echo "This will convert Windows (CRLF) line endings to Unix (LF) format."
    echo "Files to process:"
    echo "  - All .sh files"
    echo "  - All .yml and .yaml files"
    echo "  - All .conf files"
    echo "  - All .py files"
    echo "  - .env and .env.example"
    echo ""

    if confirm_action "Fix line endings?"; then
        echo ""

        # Check if dos2unix is available
        if ! command -v dos2unix >/dev/null 2>&1; then
            echo "dos2unix not found. Attempting to install..."
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y dos2unix
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y dos2unix
            else
                echo -e "${RED}Cannot install dos2unix automatically. Please install it manually.${NC}"
                pause_for_user
                return 1
            fi
        fi

        echo "Processing files..."

        # Find and fix files
        local count=0
        while IFS= read -r -d '' file; do
            echo "  Processing: $file"
            dos2unix "$file" 2>/dev/null || true
            ((count++))
        done < <(find . -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.conf" -o -name "*.py" -o -name ".env*" \) -print0)

        echo -e "${GREEN}✓ Processed $count files${NC}"
    else
        echo "Line ending fix cancelled."
    fi

    pause_for_user
}

# Function to fix permissions
fix_permissions() {
    show_header
    echo -e "${YELLOW}=== FIX FILE PERMISSIONS ===${NC}"
    echo ""

    echo "This will set proper permissions and ownership:"
    echo "  - Scripts (.sh files): 755 (executable)"
    echo "  - Configuration files: 644 (readable)"
    echo "  - Directories: 755 (accessible)"
    echo "  - .env files: 640 (secure, readable by docker group)"
    echo "  - Fix ownership to current user and docker group"
    echo "  - Container data directories with proper service user IDs"
    echo ""

    echo "Current ownership issues detected:"
    if [ "$(stat -c %U .)" = "root" ]; then
        echo -e "  ${RED}⚠ Project directory owned by root${NC}"
    fi
    if [ -f ".env" ] && [ "$(stat -c %U .env)" = "root" ]; then
        echo -e "  ${RED}⚠ .env file owned by root${NC}"
    fi
    echo ""

    if confirm_action "Fix file permissions and ownership?"; then
        echo ""
        echo "Setting permissions and ownership..."

        # Check if user is in docker group
        if ! groups | grep -q docker; then
            echo -e "${YELLOW}Warning: You're not in the docker group. Adding you now...${NC}"
            sudo usermod -aG docker $(whoami)
            echo "  ✓ Added $(whoami) to docker group (logout/login required)"
        fi

        # Fix ownership of entire project to current user and docker group
        echo "Fixing project ownership..."
        sudo chown -R $(id -u):docker . 2>/dev/null || {
            echo -e "${YELLOW}Falling back to user ownership...${NC}"
            sudo chown -R $(id -u):$(id -g) .
        }
        echo "  ✓ Project ownership fixed"

        # Fix script permissions
        find . -name "*.sh" -type f -exec chmod 755 {} \; 2>/dev/null || true
        echo "  ✓ Scripts set to executable (755)"

        # Fix config file permissions
        find ./config -type f -exec chmod 644 {} \; 2>/dev/null || true
        echo "  ✓ Config files set to readable (644)"

        # Fix directory permissions
        find . -type d -exec chmod 755 {} \; 2>/dev/null || true
        echo "  ✓ Directories set to accessible (755)"

        # Set .env files permissions (readable by owner and group for Docker)
        if [ -f ".env" ]; then
            chmod 640 .env 2>/dev/null || true
            echo "  ✓ .env file secured (640)"
        fi
        if [ -f ".env.example" ]; then
            chmod 644 .env.example 2>/dev/null || true
            echo "  ✓ .env.example set to readable (644)"
        fi

        # Fix data directory ownership for container services
        if [ -d "./data" ]; then
            echo "Fixing data directory permissions for container services..."

            # Stop containers first to avoid permission conflicts
            echo "  Stopping containers to fix permissions..."
            docker-compose down 2>/dev/null || true

            # Remove any existing Docker volumes that might have wrong permissions
            echo "  Cleaning up any conflicting Docker volumes..."
            docker volume ls -q | grep -E "(grafana|prometheus)" | xargs -r docker volume rm 2>/dev/null || true

            # Create data subdirectories if they don't exist
            mkdir -p ./data/{prometheus,grafana,keycloak,postgres,wikijs,wikijs-postgres,rancher,webapp,nginx}

            # Prometheus runs as user 65534 (nobody)
            if [ -d "./data/prometheus" ]; then
                sudo chown -R 65534:65534 ./data/prometheus
                sudo chmod -R 777 ./data/prometheus
                echo "  ✓ Prometheus data directory (65534:65534, 777)"
            fi

            # Grafana - more comprehensive fix
            if [ -d "./data/grafana" ]; then
                # Remove existing grafana data and recreate
                sudo rm -rf ./data/grafana/*
                sudo mkdir -p ./data/grafana/{dashboards,datasources,plugins,provisioning,alerting}

                # Set ownership and permissions for Grafana
                sudo chown -R 472:0 ./data/grafana
                sudo chmod -R 755 ./data/grafana

                # Make sure all subdirectories are writable by grafana user
                sudo find ./data/grafana -type d -exec chmod 755 {} \;
                sudo find ./data/grafana -type f -exec chmod 644 {} \; 2>/dev/null || true

                # Create a test file to verify permissions
                sudo -u \#472 touch ./data/grafana/test_write 2>/dev/null && sudo rm ./data/grafana/test_write
                if [ $? -eq 0 ]; then
                    echo "  ✓ Grafana data directory (472:0, 755) - Write test passed"
                else
                    echo "  ⚠ Grafana data directory (472:0, 755) - Write test failed, using 777"
                    sudo chmod -R 777 ./data/grafana
                fi
            fi

            # PostgreSQL runs as user 999 (postgres) - both Keycloak and Wiki.js DBs
            for dbdir in postgres wikijs-postgres; do
                if [ -d "./data/$dbdir" ]; then
                    sudo chown -R 999:999 ./data/$dbdir
                    sudo chmod -R 700 ./data/$dbdir
                    echo "  ✓ $dbdir data directory (999:999, 700)"
                fi
            done

            # Keycloak runs as user 1000 (keycloak)
            if [ -d "./data/keycloak" ]; then
                sudo chown -R 1000:1000 ./data/keycloak
                sudo chmod -R 755 ./data/keycloak
                echo "  ✓ Keycloak data directory (1000:1000, 755)"
            fi

            # Wiki.js runs as user 1000
            if [ -d "./data/wikijs" ]; then
                sudo chown -R 1000:1000 ./data/wikijs
                sudo chmod -R 755 ./data/wikijs
                echo "  ✓ Wiki.js data directory (1000:1000, 755)"
            fi

            # Rancher runs as root
            if [ -d "./data/rancher" ]; then
                sudo chown -R 0:0 ./data/rancher
                sudo chmod -R 755 ./data/rancher
                echo "  ✓ Rancher data directory (0:0, 755)"
            fi

            # WebApp and Nginx use current user
            for dir in webapp nginx; do
                if [ -d "./data/$dir" ]; then
                    sudo chown -R $(id -u):$(id -g) ./data/$dir
                    sudo chmod -R 755 ./data/$dir
                    echo "  ✓ $dir data directory ($(id -u):$(id -g), 755)"
                fi
            done

            # Set SELinux context if on RHEL/CentOS
            if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
                echo "  Setting SELinux context for container volumes..."
                sudo setsebool -P container_manage_cgroup true 2>/dev/null || true
                sudo semanage fcontext -a -t container_file_t "./data(/.*)?" 2>/dev/null || true
                sudo restorecon -R ./data 2>/dev/null || true
                echo "  ✓ SELinux context set for data directories"
            fi

            echo "  ✓ All data directory permissions fixed for containers"
        fi

        # Special handling for mounted directories
        if [ "$PROJECT_ROOT" != "$(pwd)" ] || [[ "$PROJECT_ROOT" == /mnt/* ]]; then
            echo "Detected mounted filesystem, applying additional fixes..."
            # Ensure the mount point has correct ownership
            sudo chown -R $(id -u):docker "$PROJECT_ROOT" 2>/dev/null || {
                sudo chown -R $(id -u):$(id -g) "$PROJECT_ROOT" 2>/dev/null || true
            }
            echo "  ✓ Mount point ownership fixed"
        fi

        echo -e "${GREEN}✓ Permissions and ownership fixed successfully${NC}"
        echo ""
        echo "Verification:"
        echo "Project owner: $(stat -c %U:%G .)"
        if [ -f ".env" ]; then
            echo ".env owner: $(stat -c %U:%G .env)"
            echo ".env permissions: $(stat -c %a .env)"
        fi
        if [ -d "./data/grafana" ]; then
            echo "Grafana data owner: $(stat -c %U:%G ./data/grafana)"
            echo "Grafana data permissions: $(stat -c %a ./data/grafana)"
        fi
        echo ""
        echo -e "${CYAN}Container-specific data directories configured:${NC}"
        echo "  Prometheus (65534:65534) - /prometheus volume"
        echo "  Grafana (472:0) - /var/lib/grafana volume"
        echo "  PostgreSQL (999:999) - /var/lib/postgresql/data volume"
        echo "  Keycloak (1000:1000) - /opt/keycloak/data volume"
        echo "  Wiki.js (1000:1000) - /wiki/* volumes"
        echo "  Rancher (0:0) - /var/lib/rancher volume"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. If you were added to docker group, logout and login"
        echo "2. Start containers: docker-compose up -d"
        echo "3. Check Grafana logs: docker-compose logs grafana"
        echo "4. If Grafana still fails, try: docker-compose exec grafana ls -la /var/lib/grafana"
        echo ""
        echo -e "${YELLOW}Note: Containers and volumes were cleaned during permission fix${NC}"
    else
        echo "Permission fix cancelled."
    fi

    pause_for_user
}

# Function to setup cron backup
setup_cron_backup() {
    show_header
    echo -e "${YELLOW}=== SETUP AUTOMATED BACKUPS ===${NC}"
    echo ""

    local script_path="$(realpath "$0")"
    local cron_command="$script_path --auto-backup"

    echo "This will create a cron job to automatically backup your project."
    echo ""
    echo "Backup options:"
    echo "  1. Daily at 2:00 AM"
    echo "  2. Daily at 6:00 AM"
    echo "  3. Weekly (Sundays at 3:00 AM)"
    echo "  4. Custom schedule"
    echo "  5. View current cron jobs"
    echo "  6. Remove backup cron job"
    echo ""

    read -p "Select option (1-6): " cron_choice

    case $cron_choice in
        1)
            local cron_schedule="0 2 * * *"
            local description="Daily at 2:00 AM"
            ;;
        2)
            local cron_schedule="0 6 * * *"
            local description="Daily at 6:00 AM"
            ;;
        3)
            local cron_schedule="0 3 * * 0"
            local description="Weekly on Sundays at 3:00 AM"
            ;;
        4)
            echo ""
            echo "Enter custom cron schedule (5 fields: minute hour day month weekday)"
            echo "Examples:"
            echo "  0 1 * * * = Every day at 1:00 AM"
            echo "  30 */6 * * * = Every 6 hours at 30 minutes past"
            echo "  0 0 1 * * = First day of every month at midnight"
            echo ""
            read -p "Enter schedule: " cron_schedule
            local description="Custom: $cron_schedule"
            ;;
        5)
            echo ""
            echo "Current cron jobs:"
            crontab -l 2>/dev/null | grep -E "(backup|$script_path)" || echo "No backup-related cron jobs found"
            pause_for_user
            return 0
            ;;
        6)
            echo ""
            if confirm_action "Remove backup cron job?"; then
                crontab -l 2>/dev/null | grep -v "$script_path" | crontab -
                echo -e "${GREEN}✓ Backup cron job removed${NC}"
            fi
            pause_for_user
            return 0
            ;;
        *)
            echo "Invalid option"
            pause_for_user
            return 1
            ;;
    esac

    echo ""
    echo "Schedule: $description"
    echo "Command: $cron_command"
    echo ""

    if confirm_action "Create this cron job?"; then
        # Remove existing backup cron job for this script
        (crontab -l 2>/dev/null | grep -v "$script_path"; echo "$cron_schedule $cron_command") | crontab -

        echo -e "${GREEN}✓ Cron job created successfully${NC}"
        echo ""
        echo "To verify, run: crontab -l"
    else
        echo "Cron job creation cancelled."
    fi

    pause_for_user
}

# Function to generate .env from example
generate_env_file() {
    show_header
    echo -e "${YELLOW}=== GENERATE ENVIRONMENT FILE ===${NC}"
    echo ""

    if [ ! -f "$ENV_EXAMPLE" ]; then
        echo -e "${RED}Error: .env.example file not found${NC}"
        echo "Expected location: $ENV_EXAMPLE"
        pause_for_user
        return 1
    fi

    if [ -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}Warning: .env file already exists${NC}"
        echo "Current .env file will be backed up as .env.backup"
        echo ""

        if ! confirm_action "Continue and overwrite existing .env file?"; then
            echo ".env generation cancelled."
            pause_for_user
            return 0
        fi

        # Backup existing .env
        cp "$ENV_FILE" "${ENV_FILE}.backup"
        echo "Existing .env backed up to .env.backup"
    fi

    echo ""
    echo "Generating .env file from .env.example..."
    echo ""
    echo "You'll be prompted to enter values for each configuration item."
    echo "Press Enter to keep the default value shown in [brackets]."
    echo ""

    # Read .env.example and prompt for values
    local temp_env=$(mktemp)

    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ $line =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            echo "$line" >> "$temp_env"
            continue
        fi

        # Process variable lines
        if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local default_value="${BASH_REMATCH[2]}"

            # Remove quotes from default value for display
            local display_default="${default_value//\"/}"

            echo -e "${CYAN}$var_name${NC}"
            if [[ $var_name == *"PASSWORD"* ]] || [[ $var_name == *"SECRET"* ]] || [[ $var_name == *"KEY"* ]]; then
                echo -e "${RED}(Security: This is a sensitive value)${NC}"
                read -s -p "Enter value [${display_default}]: " user_value
                echo ""
            else
                read -p "Enter value [${display_default}]: " user_value
            fi

            if [ -z "$user_value" ]; then
                echo "$line" >> "$temp_env"
            else
                echo "${var_name}=${user_value}" >> "$temp_env"
            fi
            echo ""
        else
            echo "$line" >> "$temp_env"
        fi
    done < "$ENV_EXAMPLE"

    # Move temp file to .env
    mv "$temp_env" "$ENV_FILE"
    chmod 644 "$ENV_FILE"

    echo -e "${GREEN}✓ .env file generated successfully${NC}"
    echo "File location: $ENV_FILE"
    echo "File permissions: 644 (secure)"

    pause_for_user
}

# Function for auto-backup (called by cron)
auto_backup() {
    # Silent backup for cron jobs
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="auto_backup_${timestamp}"
    local backup_file="${BACKUP_DIR}/${backup_name}.zip"

    # Create temporary directory for backup staging
    local temp_dir=$(mktemp -d)
    local staging_dir="$temp_dir/$backup_name"
    mkdir -p "$staging_dir"

    # Copy files to staging directory
    cp docker-compose.yml "$staging_dir/" 2>/dev/null || true
    cp .env "$staging_dir/" 2>/dev/null || true
    cp .env.example "$staging_dir/" 2>/dev/null || true
    cp -r config "$staging_dir/" 2>/dev/null || true
    cp -r scripts "$staging_dir/" 2>/dev/null || true
    cp -r webapp "$staging_dir/" 2>/dev/null || true
    cp -r guides "$staging_dir/" 2>/dev/null || true

    # Create backup info file
    cat > "$staging_dir/backup_info.txt" << EOF
Automatic backup created: $(date)
Project: $(basename "$PROJECT_ROOT")
Type: Automated backup via cron
EOF

    # Create ZIP file
    cd "$temp_dir"
    zip -r "$backup_file" "$backup_name" >/dev/null 2>&1

    # Cleanup
    rm -rf "$temp_dir"

    # Clean old backups (keep last 10 auto backups)
    ls -1t "$BACKUP_DIR"/auto_backup_*.zip 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true

    # Log result
    if [ -f "$backup_file" ]; then
        echo "$(date): Automatic backup completed successfully: $backup_file" >> "$BACKUP_DIR/backup.log"
    else
        echo "$(date): Automatic backup failed" >> "$BACKUP_DIR/backup.log"
    fi
}

# Main menu
show_main_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}=== MAIN MENU ===${NC}"
        echo ""
        echo "Project Management Options:"
        echo ""
        echo "  1. Create Backup"
        echo "  2. Restore Backup"
        echo "  3. Fix Line Endings"
        echo "  4. Fix File Permissions"
        echo "  5. Setup Automated Backups (Cron)"
        echo "  6. Generate .env from Example"
        echo ""
        echo "  9. Exit"
        echo ""

        read -p "Select option (1-9): " choice

        case $choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) fix_line_endings ;;
            4) fix_permissions ;;
            5) setup_cron_backup ;;
            6) generate_env_file ;;
            9) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid option. Please try again."; sleep 1 ;;
        esac
    done
}

# Main execution
if [ "$1" = "--auto-backup" ]; then
    auto_backup
else
    show_main_menu
fi