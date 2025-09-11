#!/bin/bash

# Docker Environment Dependencies Installer
# Installs Docker, Docker Compose, and all required tools for the monitoring stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Docker Environment Dependencies Installer${NC}"
    echo -e "${BLUE}================================================${NC}"
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

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        OS_ID=$ID
        VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="Red Hat Enterprise Linux"
        VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+')
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi

    echo -e "${CYAN}Detected OS: $OS $VERSION${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Docker on RHEL/CentOS/Fedora
install_docker_rhel() {
    echo -e "${YELLOW}Installing Docker on RHEL/CentOS/Fedora...${NC}"
    echo ""
    echo "Commands to be executed:"
    echo "  sudo dnf -y install dnf-plugins-core"
    echo "  sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo"
    echo "  sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    echo "  sudo systemctl enable --now docker"
    echo ""

    if confirm_action "Install Docker using these commands?"; then
        echo "Installing dnf-plugins-core..."
        sudo dnf -y install dnf-plugins-core

        echo "Adding Docker repository..."
        sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

        echo "Installing Docker packages..."
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        echo "Enabling and starting Docker service..."
        sudo systemctl enable --now docker

        echo -e "${GREEN}✓ Docker installed successfully${NC}"
        return 0
    else
        echo "Docker installation skipped."
        return 1
    fi
}

# Function to install Docker on Ubuntu/Debian
install_docker_debian() {
    echo -e "${YELLOW}Installing Docker on Ubuntu/Debian...${NC}"
    echo ""
    echo "Commands to be executed:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install ca-certificates curl gnupg lsb-release"
    echo "  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
    echo "  echo deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable | sudo tee /etc/apt/sources.list.d/docker.list"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    echo "  sudo systemctl enable --now docker"
    echo ""

    if confirm_action "Install Docker using these commands?"; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg lsb-release

        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # Set up the repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        sudo systemctl enable --now docker

        echo -e "${GREEN}✓ Docker installed successfully${NC}"
        return 0
    else
        echo "Docker installation skipped."
        return 1
    fi
}

# Function to install additional tools on RHEL/CentOS/Fedora
install_tools_rhel() {
    echo -e "${YELLOW}Installing additional tools on RHEL/CentOS/Fedora...${NC}"
    echo ""
    echo "Tools to install:"
    echo "  - jq (JSON processor)"
    echo "  - dos2unix (line ending converter)"
    echo "  - zip/unzip (archive tools)"
    echo "  - curl (HTTP client)"
    echo "  - git (version control)"
    echo "  - openssl (cryptography tools)"
    echo "  - wget (file downloader)"
    echo ""

    if confirm_action "Install these tools?"; then
        echo "Installing tools..."
        sudo dnf install -y jq dos2unix zip unzip curl git openssl wget
        echo -e "${GREEN}✓ Additional tools installed${NC}"
        return 0
    else
        echo "Additional tools installation skipped."
        return 1
    fi
}

# Function to install additional tools on Ubuntu/Debian
install_tools_debian() {
    echo -e "${YELLOW}Installing additional tools on Ubuntu/Debian...${NC}"
    echo ""
    echo "Tools to install:"
    echo "  - jq (JSON processor)"
    echo "  - dos2unix (line ending converter)"
    echo "  - zip/unzip (archive tools)"
    echo "  - curl (HTTP client)"
    echo "  - git (version control)"
    echo "  - openssl (cryptography tools)"
    echo "  - wget (file downloader)"
    echo ""

    if confirm_action "Install these tools?"; then
        echo "Updating package list..."
        sudo apt-get update

        echo "Installing tools..."
        sudo apt-get install -y jq dos2unix zip unzip curl git openssl wget
        echo -e "${GREEN}✓ Additional tools installed${NC}"
        return 0
    else
        echo "Additional tools installation skipped."
        return 1
    fi
}

# Function to add user to docker group
add_user_to_docker_group() {
    echo -e "${YELLOW}Adding user to Docker group...${NC}"
    echo ""
    echo "Current user: $(whoami)"
    echo "This will allow you to run Docker commands without sudo."
    echo ""
    echo "Command to be executed:"
    echo "  sudo usermod -aG docker $(whoami)"
    echo ""
    echo -e "${RED}Note: You'll need to log out and back in for this to take effect.${NC}"
    echo ""

    if confirm_action "Add $(whoami) to the docker group?"; then
        sudo usermod -aG docker $(whoami)
        echo -e "${GREEN}✓ User $(whoami) added to docker group${NC}"
        echo -e "${YELLOW}Please log out and back in for the changes to take effect.${NC}"
        return 0
    else
        echo "User not added to docker group."
        return 1
    fi
}

# Function to test Docker installation
test_docker_installation() {
    echo -e "${YELLOW}Testing Docker installation...${NC}"
    echo ""

    if confirm_action "Run Docker test commands?"; then
        echo "Testing Docker daemon..."
        if sudo docker --version; then
            echo -e "${GREEN}✓ Docker daemon is working${NC}"
        else
            echo -e "${RED}✗ Docker daemon test failed${NC}"
            return 1
        fi

        echo ""
        echo "Testing Docker Compose..."
        if sudo docker compose version; then
            echo -e "${GREEN}✓ Docker Compose is working${NC}"
        else
            echo -e "${RED}✗ Docker Compose test failed${NC}"
            return 1
        fi

        echo ""
        echo "Testing Docker with hello-world container..."
        if sudo docker run --rm hello-world >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker container test successful${NC}"
        else
            echo -e "${RED}✗ Docker container test failed${NC}"
            return 1
        fi

        echo ""
        echo -e "${GREEN}✓ All Docker tests passed${NC}"
        return 0
    else
        echo "Docker testing skipped."
        return 0
    fi
}

# Function to test additional tools
test_additional_tools() {
    echo -e "${YELLOW}Testing additional tools...${NC}"
    echo ""

    local tools=("jq" "dos2unix" "zip" "unzip" "curl" "git" "openssl" "wget")
    local failed_tools=()

    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            echo -e "  ${GREEN}✓ $tool${NC} - $(${tool} --version 2>/dev/null | head -n1 || echo 'Available')"
        else
            echo -e "  ${RED}✗ $tool${NC} - Not found"
            failed_tools+=("$tool")
        fi
    done

    if [ ${#failed_tools[@]} -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ All additional tools are available${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}✗ Missing tools: ${failed_tools[*]}${NC}"
        return 1
    fi
}

# Function to show installation summary
show_summary() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Installation Summary${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""

    echo "Installed components:"
    echo ""

    if command_exists docker; then
        echo -e "${GREEN}✓ Docker: $(docker --version 2>/dev/null || echo 'Installed')${NC}"
    else
        echo -e "${RED}✗ Docker: Not installed${NC}"
    fi

    if command_exists docker && docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker Compose: $(docker compose version --short 2>/dev/null || echo 'Installed')${NC}"
    else
        echo -e "${RED}✗ Docker Compose: Not installed${NC}"
    fi

    local tools=("jq" "dos2unix" "zip" "curl" "git" "openssl" "wget")
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            echo -e "${GREEN}✓ $tool: Available${NC}"
        else
            echo -e "${RED}✗ $tool: Not available${NC}"
        fi
    done

    echo ""
    echo "Next steps:"
    echo "1. Log out and back in if you were added to the docker group"
    echo "2. Test Docker without sudo: docker --version"
    echo "3. Navigate to your project directory"
    echo "4. Run the project management script: ./manage.sh"
    echo ""
}

# Main installation function
main() {
    show_header

    echo -e "${CYAN}This script will install Docker and required dependencies for your monitoring stack.${NC}"
    echo ""

    # Detect OS
    detect_os
    echo ""

    # Check what's already installed
    echo "Checking current installation status..."
    echo ""

    if command_exists docker; then
        echo -e "${GREEN}✓ Docker is already installed: $(docker --version)${NC}"
        DOCKER_INSTALLED=true
    else
        echo -e "${YELLOW}! Docker is not installed${NC}"
        DOCKER_INSTALLED=false
    fi

    if command_exists jq; then
        echo -e "${GREEN}✓ jq is already installed${NC}"
        TOOLS_INSTALLED=true
    else
        echo -e "${YELLOW}! Additional tools need to be installed${NC}"
        TOOLS_INSTALLED=false
    fi

    echo ""

    # Install Docker if needed
    if [ "$DOCKER_INSTALLED" = false ]; then
        case "$OS_ID" in
            rhel|centos|fedora|rocky|almalinux)
                install_docker_rhel
                ;;
            ubuntu|debian)
                install_docker_debian
                ;;
            *)
                echo -e "${RED}Unsupported OS: $OS${NC}"
                echo "Please install Docker manually from: https://docs.docker.com/engine/install/"
                exit 1
                ;;
        esac
        echo ""
    fi

    # Install additional tools if needed
    if [ "$TOOLS_INSTALLED" = false ]; then
        case "$OS_ID" in
            rhel|centos|fedora|rocky|almalinux)
                install_tools_rhel
                ;;
            ubuntu|debian)
                install_tools_debian
                ;;
            *)
                echo -e "${YELLOW}Please install these tools manually: jq dos2unix zip unzip curl git openssl wget${NC}"
                ;;
        esac
        echo ""
    fi

    # Add user to docker group
    if id -nG "$USER" | grep -qw "docker"; then
        echo -e "${GREEN}✓ User $(whoami) is already in the docker group${NC}"
    else
        add_user_to_docker_group
    fi
    echo ""

    # Test installations
    test_docker_installation
    echo ""

    test_additional_tools
    echo ""

    # Show summary
    show_summary
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run this script as root${NC}"
    echo "Run as a regular user - the script will use sudo when needed"
    exit 1
fi

# Run main function
main