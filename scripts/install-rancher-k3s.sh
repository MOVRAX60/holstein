#!/bin/bash

# K3s Installation Script with Monitoring Stack Integration
# Installs K3s, Helm, and Rancher configured for existing Keycloak SSO

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
K3S_VERSION="${K3S_VERSION:-latest}"
RANCHER_VERSION="${RANCHER_VERSION:-stable}"
RANCHER_NAMESPACE="cattle-system"
CERT_MANAGER_VERSION="v1.13.2"

# Get configuration from monitoring stack
DOMAIN="${DOMAIN:-rancher.local}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-master}"

# K3s specific settings
K3S_HOSTNAME="${DOMAIN}"
K3S_DATA_DIR="/var/lib/rancher/k3s"

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}    K3s + Monitoring Stack Integration${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${CYAN}Domain: $DOMAIN${NC}"
    echo -e "${CYAN}Keycloak Integration: Enabled${NC}"
    echo -e "${CYAN}K3s Version: $K3S_VERSION${NC}"
    echo -e "${CYAN}Rancher Version: $RANCHER_VERSION${NC}"
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if monitoring stack is running
check_monitoring_stack() {
    echo -e "${YELLOW}Checking monitoring stack status...${NC}"

    if ! command_exists docker-compose && ! command_exists docker; then
        echo -e "${RED}Docker/Docker Compose not found. Please install monitoring stack first.${NC}"
        return 1
    fi

    # Check if monitoring containers are running
    local running_containers=()
    local expected_containers=("keycloak" "nginx" "webapp")

    for container in "${expected_containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "holstein.*$container"; then
            running_containers+=("$container")
        fi
    done

    if [ ${#running_containers[@]} -eq 0 ]; then
        echo -e "${RED}Monitoring stack containers not found.${NC}"
        echo "Please start your monitoring stack first with: docker-compose up -d"
        return 1
    fi

    echo -e "${GREEN}✓ Monitoring stack is running${NC}"
    echo "  Found containers: ${running_containers[*]}"

    # Test Keycloak accessibility
    if curl -s -f "http://localhost/auth/realms/$KEYCLOAK_REALM/.well-known/openid-configuration" >/dev/null; then
        echo -e "${GREEN}✓ Keycloak is accessible${NC}"
    else
        echo -e "${YELLOW}⚠ Keycloak may not be fully ready yet${NC}"
    fi

    return 0
}

# Function to check system requirements
check_system_requirements() {
    echo -e "${YELLOW}Checking system requirements...${NC}"

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Error: Do not run this script as root${NC}"
        echo "Run as a regular user with sudo privileges"
        exit 1
    fi

    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}This script requires sudo access. You may be prompted for your password.${NC}"
        sudo true
    fi

    # Check available resources
    local ram_gb=$(free -g | awk 'NR==2{print $2}')
    local available_ram=$(free -g | awk 'NR==2{print $7}')
    local cpu_cores=$(nproc)

    echo "System resources:"
    echo "  Total RAM: ${ram_gb}GB"
    echo "  Available RAM: ${available_ram}GB"
    echo "  CPU Cores: ${cpu_cores}"
    echo "  Disk space: $(df -h / | awk 'NR==2{print $4}') available"

    if [ "$available_ram" -lt 2 ]; then
        echo -e "${RED}Warning: Less than 2GB RAM available. K3s + monitoring stack may struggle.${NC}"
        if ! confirm_action "Continue anyway?"; then
            exit 1
        fi
    fi

    echo -e "${GREEN}✓ System requirements check completed${NC}"
}

# Function to install K3s
install_k3s() {
    echo -e "${YELLOW}Installing K3s...${NC}"

    if command_exists k3s; then
        echo "K3s already installed: $(k3s --version | head -n1)"
        return 0
    fi

    # Configure firewall for K3s
    echo "Configuring firewall for K3s..."
    if command_exists firewall-cmd; then
        sudo firewall-cmd --permanent --add-port=6443/tcp   # Kubernetes API
        sudo firewall-cmd --permanent --add-port=10250/tcp  # Kubelet
        sudo firewall-cmd --permanent --add-port=8472/udp   # Flannel VXLAN
        sudo firewall-cmd --reload
        echo "  ✓ Firewall configured"
    fi

    # Install K3s with specific configuration for coexistence
    echo "Installing K3s with monitoring stack-friendly configuration..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --disable local-storage \
        --cluster-cidr=10.42.0.0/16 \
        --service-cidr=10.43.0.0/16 \
        --node-external-ip=$(hostname -I | awk '{print $1}') \
        --bind-address=0.0.0.0

    # Wait for K3s to be ready
    echo "Waiting for K3s to be ready..."
    local count=0
    while ! sudo k3s kubectl get nodes >/dev/null 2>&1; do
        sleep 5
        ((count++))
        if [ $count -gt 24 ]; then  # 2 minutes timeout
            echo -e "${RED}Timeout waiting for K3s to start${NC}"
            exit 1
        fi
        echo "  Waiting... ($count/24)"
    done

    # Set up kubeconfig for regular user
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    chmod 600 ~/.kube/config

    # Export KUBECONFIG for current session
    export KUBECONFIG=~/.kube/config

    # Add to bashrc for future sessions
    if ! grep -q "export KUBECONFIG" ~/.bashrc; then
        echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
    fi

    echo -e "${GREEN}✓ K3s installed and configured${NC}"
    k3s --version | head -n1
}

# Function to install Helm
install_helm() {
    echo -e "${YELLOW}Installing Helm...${NC}"

    if command_exists helm; then
        echo "Helm already installed: $(helm version --short)"
        return 0
    fi

    # Download and install Helm
    echo "Downloading Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh

    # Add Helm repositories
    echo "Adding Helm repositories..."
    helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    echo -e "${GREEN}✓ Helm installed and configured${NC}"
    helm version --short
}

# Function to install cert-manager
install_cert_manager() {
    echo -e "${YELLOW}Installing cert-manager...${NC}"

    # Check if cert-manager is already installed
    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        echo "cert-manager already installed"
        return 0
    fi

    # Install cert-manager CRDs
    echo "Installing cert-manager CRDs..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml

    # Create cert-manager namespace
    kubectl create namespace cert-manager

    # Install cert-manager via Helm
    echo "Installing cert-manager via Helm..."
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version $CERT_MANAGER_VERSION

    # Wait for cert-manager to be ready
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

    echo -e "${GREEN}✓ cert-manager installed${NC}"
}

# Function to generate certificates
generate_certificates() {
    echo -e "${YELLOW}Configuring certificates for Rancher...${NC}"

    # Check for existing certificates in project structure
    if [ -f "$PROJECT_CERTS_DIR/ssl.crt" ] && [ -f "$PROJECT_CERTS_DIR/ssl.key" ]; then
        echo "Using existing certificates from $PROJECT_CERTS_DIR"

        # Create symlinks or copy to expected location for Kubernetes
        local cert_dir="$PROJECT_CERTS_DIR"

        # Verify certificate is valid for our domain
        if openssl x509 -in "$PROJECT_CERTS_DIR/ssl.crt" -text -noout | grep -q "$K3S_HOSTNAME"; then
            echo -e "${GREEN}✓ Existing certificate is valid for $K3S_HOSTNAME${NC}"
        else
            echo -e "${YELLOW}⚠ Existing certificate may not include $K3S_HOSTNAME${NC}"
            echo "Certificate subjects:"
            openssl x509 -in "$PROJECT_CERTS_DIR/ssl.crt" -text -noout | grep -A1 "Subject Alternative Name" || true
        fi

        CERT_FILE="$PROJECT_CERTS_DIR/ssl.crt"
        KEY_FILE="$PROJECT_CERTS_DIR/ssl.key"

    elif [ -f "$PROJECT_CERTS_DIR/tls.crt" ] && [ -f "$PROJECT_CERTS_DIR/tls.key" ]; then
        echo "Using existing TLS certificates from $PROJECT_CERTS_DIR"
        CERT_FILE="$PROJECT_CERTS_DIR/tls.crt"
        KEY_FILE="$PROJECT_CERTS_DIR/tls.key"

    else
        echo "No existing certificates found in $PROJECT_CERTS_DIR"
        echo "Generating new certificates..."

        # Ensure certs directory exists
        mkdir -p "$PROJECT_CERTS_DIR"

        # Generate self-signed certificate for Rancher
        echo "Generating self-signed certificate for $K3S_HOSTNAME..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$PROJECT_CERTS_DIR/tls.key" \
            -out "$PROJECT_CERTS_DIR/tls.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$K3S_HOSTNAME" \
            -addext "subjectAltName=DNS:$K3S_HOSTNAME,DNS:localhost,IP:127.0.0.1,IP:$(hostname -I | awk '{print $1}')"

        CERT_FILE="$PROJECT_CERTS_DIR/tls.crt"
        KEY_FILE="$PROJECT_CERTS_DIR/tls.key"

        echo -e "${GREEN}✓ New certificates generated in $PROJECT_CERTS_DIR${NC}"
    fi

    # Set proper permissions
    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"

    echo "Certificate configuration:"
    echo "  Certificate: $CERT_FILE"
    echo "  Private Key: $KEY_FILE"
    echo "  Storage: $PROJECT_CERTS_DIR"
}

# Function to install Rancher
install_rancher() {
    echo -e "${YELLOW}Installing Rancher on K3s...${NC}"

    # Check if Rancher is already installed
    if kubectl get namespace $RANCHER_NAMESPACE >/dev/null 2>&1; then
        if helm list -n $RANCHER_NAMESPACE | grep -q rancher; then
            echo "Rancher already installed"
            return 0
        fi
    fi

    # Create Rancher namespace
    kubectl create namespace $RANCHER_NAMESPACE || true

    # Create TLS secret
    echo "Creating TLS secret for Rancher..."
    kubectl create secret tls tls-rancher-ingress \
        --cert=./k3s-rancher-certs/tls.crt \
        --key=./k3s-rancher-certs/tls.key \
        --namespace $RANCHER_NAMESPACE || true

    # Install Rancher via Helm
    echo "Installing Rancher via Helm..."
    helm install rancher rancher-stable/rancher \
        --namespace $RANCHER_NAMESPACE \
        --set hostname=$K3S_HOSTNAME \
        --set bootstrapPassword=admin \
        --set ingress.tls.source=secret \
        --set privateCA=true \
        --set replicas=1 \
        --version $RANCHER_VERSION

    # Wait for Rancher to be ready
    echo "Waiting for Rancher to be ready (this may take several minutes)..."
    kubectl -n $RANCHER_NAMESPACE rollout status deploy/rancher --timeout=600s

    echo -e "${GREEN}✓ Rancher installed on K3s${NC}"
}

# Function to configure Rancher for Keycloak integration
configure_rancher_keycloak() {
    echo -e "${YELLOW}Configuring Rancher for Keycloak integration...${NC}"

    # Wait for Rancher to be accessible
    echo "Waiting for Rancher to be accessible..."
    local count=0
    while ! curl -k -s "https://$K3S_HOSTNAME:6443" >/dev/null; do
        sleep 10
        ((count++))
        if [ $count -gt 30 ]; then
            echo -e "${YELLOW}Rancher may not be accessible yet. Continue with manual configuration.${NC}"
            break
        fi
        echo "  Waiting... ($count/30)"
    done

    # Create a script for manual Keycloak configuration
    cat > configure_rancher_keycloak.sh << 'EOF'
#!/bin/bash
echo "Manual Rancher Keycloak Configuration"
echo "====================================="
echo ""
echo "1. Access Rancher at: https://DOMAIN:6443"
echo "2. Login with: admin/admin"
echo "3. Go to: Users & Authentication > Auth Provider"
echo "4. Select: Keycloak (OIDC)"
echo "5. Configure with these settings:"
echo ""
echo "   Display Name Field: Keycloak SSO"
echo "   Client ID: rancher"
echo "   Client Secret: [get from Keycloak]"
echo "   Issuer: https://DOMAIN/auth/realms/REALM"
echo "   Auth Endpoint: https://DOMAIN/auth/realms/REALM/protocol/openid-connect/auth"
echo "   Token Endpoint: https://DOMAIN/auth/realms/REALM/protocol/openid-connect/token"
echo "   User Info Endpoint: https://DOMAIN/auth/realms/REALM/protocol/openid-connect/userinfo"
echo ""
echo "6. Set User Mapping:"
echo "   Username Field: preferred_username"
echo "   Display Name Field: name"
echo "   User ID Field: sub"
echo "   Groups Field: groups"
echo ""
echo "7. Click 'Enable' and test authentication"
EOF

    # Replace placeholders
    sed -i "s/DOMAIN/$DOMAIN/g" configure_rancher_keycloak.sh
    sed -i "s/REALM/$KEYCLOAK_REALM/g" configure_rancher_keycloak.sh
    chmod +x configure_rancher_keycloak.sh

    echo -e "${GREEN}✓ Configuration script created: configure_rancher_keycloak.sh${NC}"
}

# Function to update monitoring stack for K3s integration
update_monitoring_stack() {
    echo -e "${YELLOW}Updating monitoring stack for K3s integration...${NC}"

    # Check if .env file exists
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}Warning: .env file not found. Skipping environment update.${NC}"
        return 0
    fi

    # Add K3s-specific environment variables
    echo "Adding K3s configuration to .env..."

    # Remove old rancher config if it exists
    sed -i '/^RANCHER_VERSION=/d' .env
    sed -i '/^RANCHER_BOOTSTRAP_PASSWORD=/d' .env
    sed -i '/^RANCHER_PASSWORD_MIN_LENGTH=/d' .env
    sed -i '/^RANCHER_FEATURES=/d' .env
    sed -i '/^RANCHER_AUDIT_LEVEL=/d' .env
    sed -i '/^RANCHER_DEFAULT_REGISTRY=/d' .env

    # Add new K3s/external Rancher config
    cat >> .env << EOF

# K3s Rancher Integration
RANCHER_EXTERNAL_HOST=$K3S_HOSTNAME
RANCHER_EXTERNAL_PORT=6443
RANCHER_ENABLED=true
RANCHER_CLIENT_SECRET=change-this-rancher-secret
K3S_ENABLED=true
EOF

    echo -e "${GREEN}✓ Environment configuration updated${NC}"
}

# Function to show installation summary
show_summary() {
    echo ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}    K3s + Monitoring Stack Integration Complete${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""

    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo ""
    echo "Installed components:"
    echo "  ✓ K3s Kubernetes: $(k3s --version | head -n1 | awk '{print $3}')"
    echo "  ✓ Helm: $(helm version --short)"
    echo "  ✓ cert-manager: $CERT_MANAGER_VERSION"
    echo "  ✓ Rancher: $RANCHER_VERSION"
    echo ""
    echo "Access Information:"
    echo "  Monitoring Stack: https://$DOMAIN"
    echo "  K3s Rancher: https://$K3S_HOSTNAME:6443"
    echo "  Keycloak: https://$DOMAIN/auth"
    echo ""
    echo "Default Credentials:"
    echo "  Rancher: admin/admin (change immediately)"
    echo "  Keycloak: admin/[your-keycloak-password]"
    echo ""
    echo "Next Steps:"
    echo "  1. Run: ./configure_rancher_keycloak.sh for manual setup instructions"
    echo "  2. Create Rancher client in Keycloak (Client ID: rancher)"
    echo "  3. Configure Rancher OIDC authentication"
    echo "  4. Update nginx proxy to route /rancher to K3s Rancher"
    echo "  5. Test SSO integration between services"
    echo ""
    echo "Useful Commands:"
    echo "  kubectl get nodes                    # Check K3s cluster"
    echo "  kubectl get pods -A                 # Check all pods"
    echo "  helm list -A                        # Check Helm releases"
    echo "  docker-compose ps                   # Check monitoring stack"
    echo "  sudo systemctl status k3s           # Check K3s service"
    echo ""
    echo "Configuration Files:"
    echo "  ~/.kube/config                      # Kubernetes config"
    echo "  ./configure_rancher_keycloak.sh     # Keycloak setup guide"
    echo "  ./k3s-rancher-certs/                # SSL certificates"
}

# Function to run post-installation checks
post_install_checks() {
    echo -e "${YELLOW}Running post-installation checks...${NC}"

    # Check K3s service
    if systemctl is-active --quiet k3s; then
        echo -e "  ${GREEN}✓ K3s service is running${NC}"
    else
        echo -e "  ${RED}✗ K3s service is not running${NC}"
    fi

    # Check cluster status
    if kubectl get nodes | grep -q Ready; then
        echo -e "  ${GREEN}✓ K3s cluster is ready${NC}"
    else
        echo -e "  ${RED}✗ K3s cluster is not ready${NC}"
    fi

    # Check cert-manager
    if kubectl get pods -n cert-manager | grep -q Running; then
        echo -e "  ${GREEN}✓ cert-manager is running${NC}"
    else
        echo -e "  ${RED}✗ cert-manager is not running${NC}"
    fi

    # Check Rancher
    if kubectl get pods -n $RANCHER_NAMESPACE | grep -q Running; then
        echo -e "  ${GREEN}✓ Rancher is running${NC}"
    else
        echo -e "  ${RED}✗ Rancher is not running${NC}"
    fi

    # Check monitoring stack
    if docker ps | grep -q holstein; then
        echo -e "  ${GREEN}✓ Monitoring stack is running${NC}"
    else
        echo -e "  ${YELLOW}⚠ Monitoring stack may not be running${NC}"
    fi

    # Check port conflicts
    local conflicting_ports=()
    for port in 80 443; do
        if netstat -tlpn 2>/dev/null | grep ":$port " | grep -v docker; then
            conflicting_ports+=("$port")
        fi
    done

    if [ ${#conflicting_ports[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No port conflicts detected${NC}"
    else
        echo -e "  ${YELLOW}⚠ Potential port conflicts: ${conflicting_ports[*]}${NC}"
    fi
}

# Function to uninstall everything
uninstall_k3s() {
    echo -e "${YELLOW}Uninstalling K3s and Rancher...${NC}"

    if confirm_action "This will remove K3s, Rancher, and all Kubernetes resources. Continue?"; then
        # Remove Helm releases
        helm uninstall rancher -n $RANCHER_NAMESPACE 2>/dev/null || true
        helm uninstall cert-manager -n cert-manager 2>/dev/null || true

        # Uninstall K3s
        if command_exists k3s-uninstall.sh; then
            sudo k3s-uninstall.sh
        else
            sudo /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
        fi

        # Clean up files
        rm -rf ~/.kube
        rm -rf ./k3s-rancher-certs
        rm -f configure_rancher_keycloak.sh

        echo -e "${GREEN}✓ K3s uninstalled${NC}"
    fi
}

# Main menu
show_main_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}=== K3S INSTALLATION MENU ===${NC}"
        echo ""
        echo "Installation Options:"
        echo ""
        echo "  1. Full Installation (Recommended)"
        echo "  2. Check Prerequisites"
        echo "  3. Install K3s Only"
        echo "  4. Install Rancher Only"
        echo "  5. Configure Keycloak Integration"
        echo "  6. Post-Installation Checks"
        echo "  7. Show Summary"
        echo "  8. Uninstall K3s"
        echo ""
        echo "  9. Exit"
        echo ""

        read -p "Select option (1-9): " choice

        case $choice in
            1)
                if check_monitoring_stack && check_system_requirements; then
                    if confirm_action "Proceed with full K3s + Rancher installation?"; then
                        install_k3s
                        install_helm
                        install_cert_manager
                        generate_certificates
                        install_rancher
                        configure_rancher_keycloak
                        update_monitoring_stack
                        post_install_checks
                        show_summary
                    fi
                fi
                read -p "Press Enter to continue..." -r
                ;;
            2)
                check_monitoring_stack
                check_system_requirements
                read -p "Press Enter to continue..." -r
                ;;
            3)
                install_k3s
                read -p "Press Enter to continue..." -r
                ;;
            4)
                generate_certificates
                install_rancher
                read -p "Press Enter to continue..." -r
                ;;
            5)
                configure_rancher_keycloak
                read -p "Press Enter to continue..." -r
                ;;
            6)
                post_install_checks
                read -p "Press Enter to continue..." -r
                ;;
            7)
                show_summary
                read -p "Press Enter to continue..." -r
                ;;
            8)
                uninstall_k3s
                read -p "Press Enter to continue..." -r
                ;;
            9)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Handle command line arguments
case "${1:-}" in
    --full)
        show_header
        check_monitoring_stack
        check_system_requirements
        install_k3s
        install_helm
        install_cert_manager
        generate_certificates
        install_rancher
        configure_rancher_keycloak
        update_monitoring_stack
        post_install_checks
        show_summary
        ;;
    --check)
        check_monitoring_stack
        check_system_requirements
        post_install_checks
        ;;
    --uninstall)
        uninstall_k3s
        ;;
    *)
        show_main_menu
        ;;
esac