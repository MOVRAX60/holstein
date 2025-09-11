#!/bin/bash

# Linux Air-Gap Installation Script for K3s and Rancher
# Installs from assets in projectroot/airgap/

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo "Loading configuration from .env file..."
    set -a
    source .env
    set +a
fi

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Air-gap asset directories
AIRGAP_DIR="$SCRIPT_DIR/airgap"
BINARIES_DIR="$AIRGAP_DIR/binaries"
IMAGES_DIR="$AIRGAP_DIR/images"
CHARTS_DIR="$AIRGAP_DIR/charts"
MANIFESTS_DIR="$AIRGAP_DIR/manifests"

# Configuration with defaults
DOMAIN="${DOMAIN:-rancher.local}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-master}"
K3S_HOSTNAME="${DOMAIN}"
RANCHER_NAMESPACE="cattle-system"

# Certificate directory
PROJECT_CERTS_DIR="${PROJECT_CERTS_DIR:-./config/certs}"
PROJECT_CERTS_DIR=$(echo "$PROJECT_CERTS_DIR" | sed 's/^"\|"$//g')

# Initialize certificate file variables
CERT_FILE=""
KEY_FILE=""

print_color() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    clear
    print_color $BLUE "================================================="
    print_color $BLUE "    Linux Air-Gap Installation Script"
    print_color $BLUE "================================================="
    print_color $CYAN "Project Root: $SCRIPT_DIR"
    print_color $CYAN "Air-gap Assets: $AIRGAP_DIR"
    print_color $CYAN "Domain: $DOMAIN"
    print_color $CYAN "Certificate Dir: $PROJECT_CERTS_DIR"
    echo ""
}

confirm_action() {
    local message="$1"
    print_color $YELLOW "$message"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check air-gap assets
check_airgap_assets() {
    print_color $BLUE "=== Checking Air-Gap Assets ==="

    if [ ! -d "$AIRGAP_DIR" ]; then
        print_color $RED "Error: Air-gap directory not found: $AIRGAP_DIR"
        print_color $YELLOW "Please run the Windows download script first"
        return 1
    fi

    local missing_assets=()

    # Check for required directories
    for dir in "$BINARIES_DIR" "$IMAGES_DIR" "$MANIFESTS_DIR"; do
        if [ ! -d "$dir" ]; then
            missing_assets+=("Directory: $dir")
        fi
    done

    # Check for required files
    local required_files=(
        "$BINARIES_DIR/k3s"
        "$BINARIES_DIR/k3s-install.sh"
        "$BINARIES_DIR/helm-v3.13.3-linux-amd64.tar.gz"
        "$IMAGES_DIR/k3s-airgap-images-amd64.tar"
        "$MANIFESTS_DIR/cert-manager.crds.yaml"
        "$MANIFESTS_DIR/cert-manager.yaml"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_assets+=("File: $file")
        fi
    done

    if [ ${#missing_assets[@]} -gt 0 ]; then
        print_color $RED "Missing air-gap assets:"
        for asset in "${missing_assets[@]}"; do
            print_color $RED "  ✗ $asset"
        done
        return 1
    fi

    print_color $GREEN "✓ All required air-gap assets found"

    # Show version info if available
    if [ -f "$AIRGAP_DIR/versions.json" ]; then
        print_color $CYAN "Version Information:"
        if command_exists jq; then
            jq -r '. | to_entries[] | "  \(.key): \(.value)"' "$AIRGAP_DIR/versions.json"
        else
            cat "$AIRGAP_DIR/versions.json" | sed 's/^/  /'
        fi
    fi

    return 0
}

# Function to install K3s from air-gap assets
install_k3s_airgap() {
    print_color $BLUE "=== Installing K3s (Air-Gap) ==="

    if command_exists k3s; then
        print_color $YELLOW "K3s already installed: $(k3s --version | head -n1)"
        return 0
    fi

    # Install K3s binary
    print_color $CYAN "Installing K3s binary..."
    sudo cp "$BINARIES_DIR/k3s" /usr/local/bin/k3s
    sudo chmod +x /usr/local/bin/k3s

    # Create K3s images directory and copy air-gap images
    print_color $CYAN "Setting up K3s images..."
    sudo mkdir -p /var/lib/rancher/k3s/agent/images/
    sudo cp "$IMAGES_DIR/k3s-airgap-images-amd64.tar" /var/lib/rancher/k3s/agent/images/

    # Configure firewall if firewall-cmd exists
    if command_exists firewall-cmd; then
        print_color $CYAN "Configuring firewall..."
        sudo firewall-cmd --permanent --add-port=6443/tcp   # Kubernetes API
        sudo firewall-cmd --permanent --add-port=10250/tcp  # Kubelet
        sudo firewall-cmd --permanent --add-port=8472/udp   # Flannel VXLAN
        sudo firewall-cmd --reload
        print_color $GREEN "✓ Firewall configured"
    fi

    # Install K3s service using air-gap method
    print_color $CYAN "Installing K3s service..."
    INSTALL_K3S_SKIP_DOWNLOAD=true \
    sudo -E "$BINARIES_DIR/k3s-install.sh" \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --disable local-storage \
        --cluster-cidr=10.42.0.0/16 \
        --service-cidr=10.43.0.0/16 \
        --node-external-ip=$(hostname -I | awk '{print $1}') \
        --bind-address=0.0.0.0

    # Wait for K3s to be ready
    print_color $CYAN "Waiting for K3s to be ready..."
    local count=0
    while ! sudo k3s kubectl get nodes >/dev/null 2>&1; do
        sleep 5
        ((count++))
        if [ $count -gt 24 ]; then
            print_color $RED "Timeout waiting for K3s to start"
            print_color $YELLOW "Check logs with: sudo journalctl -u k3s"
            return 1
        fi
        echo "  Waiting... ($count/24)"
    done

    # Set up kubeconfig for regular user
    print_color $CYAN "Setting up kubeconfig..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    chmod 600 ~/.kube/config
    export KUBECONFIG=~/.kube/config

    # Add to bashrc for future sessions
    if ! grep -q "export KUBECONFIG" ~/.bashrc; then
        echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
    fi

    print_color $GREEN "✓ K3s installed successfully!"
    k3s --version | head -n1
}

# Function to install Helm from air-gap assets
install_helm_airgap() {
    print_color $BLUE "=== Installing Helm (Air-Gap) ==="

    if command_exists helm; then
        print_color $YELLOW "Helm already installed: $(helm version --short)"
        return 0
    fi

    # Extract and install Helm
    print_color $CYAN "Installing Helm binary..."
    local helm_archive="$BINARIES_DIR/helm-v3.13.3-linux-amd64.tar.gz"

    if [ ! -f "$helm_archive" ]; then
        print_color $RED "Error: Helm archive not found: $helm_archive"
        return 1
    fi

    # Extract to temporary directory
    local temp_dir=$(mktemp -d)
    tar -xzf "$helm_archive" -C "$temp_dir"

    # Install Helm binary
    sudo cp "$temp_dir/linux-amd64/helm" /usr/local/bin/helm
    sudo chmod +x /usr/local/bin/helm

    # Cleanup
    rm -rf "$temp_dir"

    print_color $GREEN "✓ Helm installed successfully!"
    helm version --short
}

# Function to load container images
load_container_images() {
    print_color $BLUE "=== Loading Container Images ==="

    # Load K3s images (already loaded during K3s installation)
    print_color $CYAN "K3s images loaded during installation"

    # Load additional container images if they exist
    if [ -d "$IMAGES_DIR" ]; then
        local image_count=0
        for image_tar in "$IMAGES_DIR"/*.tar; do
            if [ -f "$image_tar" ] && [ "$(basename "$image_tar")" != "k3s-airgap-images-amd64.tar" ]; then
                print_color $CYAN "Loading image: $(basename "$image_tar")"
                if sudo k3s ctr images import "$image_tar"; then
                    ((image_count++))
                else
                    print_color $YELLOW "Warning: Failed to load $(basename "$image_tar")"
                fi
            fi
        done

        if [ $image_count -gt 0 ]; then
            print_color $GREEN "✓ Loaded $image_count additional container images"
        else
            print_color $YELLOW "No additional container images found to load"
            print_color $CYAN "Run the Docker script on a connected machine to download images"
        fi
    fi
}

# Function to install cert-manager from air-gap assets
install_cert_manager_airgap() {
    print_color $BLUE "=== Installing cert-manager (Air-Gap) ==="

    # Ensure KUBECONFIG is set
    export KUBECONFIG=~/.kube/config

    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        print_color $YELLOW "cert-manager already installed"
        return 0
    fi

    # Install cert-manager CRDs
    print_color $CYAN "Installing cert-manager CRDs..."
    kubectl apply -f "$MANIFESTS_DIR/cert-manager.crds.yaml"

    # Create cert-manager namespace
    print_color $CYAN "Creating cert-manager namespace..."
    kubectl create namespace cert-manager

    # Install cert-manager from manifests or chart
    if [ -f "$MANIFESTS_DIR/cert-manager.yaml" ]; then
        print_color $CYAN "Installing cert-manager from manifests..."
        kubectl apply -f "$MANIFESTS_DIR/cert-manager.yaml"
    elif [ -f "$CHARTS_DIR/cert-manager-"*.tgz ]; then
        print_color $CYAN "Installing cert-manager from chart..."
        local cert_manager_chart=$(ls "$CHARTS_DIR/cert-manager-"*.tgz | head -n1)
        helm install cert-manager "$cert_manager_chart" \
            --namespace cert-manager \
            --set installCRDs=false
    else
        print_color $RED "Error: Neither cert-manager manifests nor charts found"
        return 1
    fi

    # Wait for cert-manager to be ready
    print_color $CYAN "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=300s

    print_color $GREEN "✓ cert-manager installed successfully!"
}

# Function to generate certificates
generate_certificates() {
    print_color $BLUE "=== Generating Certificates ==="

    # Create certificate directory
    mkdir -p "$PROJECT_CERTS_DIR"

    # Check for existing certificates
    if [ -f "$PROJECT_CERTS_DIR/tls.crt" ] && [ -f "$PROJECT_CERTS_DIR/tls.key" ]; then
        print_color $YELLOW "Certificates already exist"
        CERT_FILE="$PROJECT_CERTS_DIR/tls.crt"
        KEY_FILE="$PROJECT_CERTS_DIR/tls.key"
        export CERT_FILE KEY_FILE
        return 0
    fi

    print_color $CYAN "Generating self-signed certificate for $K3S_HOSTNAME..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROJECT_CERTS_DIR/tls.key" \
        -out "$PROJECT_CERTS_DIR/tls.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$K3S_HOSTNAME" \
        -addext "subjectAltName=DNS:$K3S_HOSTNAME,DNS:localhost,IP:127.0.0.1,IP:$(hostname -I | awk '{print $1}')"

    # Set proper permissions
    chmod 644 "$PROJECT_CERTS_DIR/tls.crt"
    chmod 600 "$PROJECT_CERTS_DIR/tls.key"

    CERT_FILE="$PROJECT_CERTS_DIR/tls.crt"
    KEY_FILE="$PROJECT_CERTS_DIR/tls.key"
    export CERT_FILE KEY_FILE

    print_color $GREEN "✓ Certificates generated successfully!"
    print_color $CYAN "Certificate: $CERT_FILE"
    print_color $CYAN "Private Key: $KEY_FILE"
}

# Function to install Rancher from air-gap assets
install_rancher_airgap() {
    print_color $BLUE "=== Installing Rancher (Air-Gap) ==="

    # Ensure KUBECONFIG is set
    export KUBECONFIG=~/.kube/config

    # Verify kubectl connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_color $RED "Error: Cannot connect to Kubernetes cluster"
        print_color $YELLOW "Ensure K3s is running and kubeconfig is set"
        return 1
    fi

    # Check if Rancher is already installed
    if helm list -n $RANCHER_NAMESPACE 2>/dev/null | grep -q rancher; then
        print_color $YELLOW "Rancher already installed"
        return 0
    fi

    # Create Rancher namespace
    print_color $CYAN "Creating Rancher namespace..."
    kubectl create namespace $RANCHER_NAMESPACE 2>/dev/null || true

    # Ensure certificates exist
    if [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ] || [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        print_color $YELLOW "Certificates not found, generating..."
        generate_certificates
    fi

    # Create TLS secret
    print_color $CYAN "Creating TLS secret for Rancher..."
    kubectl delete secret tls-rancher-ingress -n $RANCHER_NAMESPACE 2>/dev/null || true
    kubectl create secret tls tls-rancher-ingress \
        --cert="$CERT_FILE" \
        --key="$KEY_FILE" \
        --namespace $RANCHER_NAMESPACE

    # Install Rancher from chart
    local rancher_chart=$(ls "$CHARTS_DIR/rancher-"*.tgz 2>/dev/null | head -n1)
    if [ -f "$rancher_chart" ]; then
        print_color $CYAN "Installing Rancher from chart: $(basename "$rancher_chart")"
        helm install rancher "$rancher_chart" \
            --namespace $RANCHER_NAMESPACE \
            --set hostname=$K3S_HOSTNAME \
            --set bootstrapPassword=admin \
            --set ingress.tls.source=secret \
            --set privateCA=true \
            --set replicas=1
    else
        print_color $RED "Error: Rancher chart not found in $CHARTS_DIR"
        return 1
    fi

    # Wait for Rancher to be ready
    print_color $CYAN "Waiting for Rancher to be ready (this may take several minutes)..."
    kubectl -n $RANCHER_NAMESPACE rollout status deploy/rancher --timeout=600s

    print_color $GREEN "✓ Rancher installed successfully!"
}

# Function to show installation summary
show_installation_summary() {
    print_color $BLUE "================================================="
    print_color $BLUE "    Air-Gap Installation Complete"
    print_color $BLUE "================================================="
    echo ""

    print_color $GREEN "Installation completed successfully!"
    echo ""

    print_color $CYAN "Installed Components:"
    if command_exists k3s; then
        print_color $CYAN "  ✓ K3s: $(k3s --version | head -n1 | awk '{print $3}')"
    fi
    if command_exists helm; then
        print_color $CYAN "  ✓ Helm: $(helm version --short)"
    fi
    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        print_color $CYAN "  ✓ cert-manager: Installed"
    fi
    if helm list -n $RANCHER_NAMESPACE 2>/dev/null | grep -q rancher; then
        print_color $CYAN "  ✓ Rancher: Installed"
    fi

    echo ""
    print_color $CYAN "Access Information:"
    print_color $CYAN "  Rancher UI: https://$K3S_HOSTNAME:6443"
    print_color $CYAN "  Default Login: admin/admin (change immediately!)"

    echo ""
    print_color $CYAN "Useful Commands:"
    print_color $CYAN "  kubectl get nodes                    # Check cluster status"
    print_color $CYAN "  kubectl get pods -A                 # Check all pods"
    print_color $CYAN "  helm list -A                        # Check Helm releases"
    print_color $CYAN "  sudo systemctl status k3s           # Check K3s service"

    echo ""
    print_color $YELLOW "Next Steps:"
    print_color $CYAN "1. Access Rancher UI and change default password"
    print_color $CYAN "2. Configure Keycloak integration if needed"
    print_color $CYAN "3. Deploy your applications"
}

# Function to run post-installation checks
post_install_checks() {
    print_color $BLUE "=== Post-Installation Checks ==="

    # Check K3s service
    if systemctl is-active --quiet k3s; then
        print_color $GREEN "  ✓ K3s service is running"
    else
        print_color $RED "  ✗ K3s service is not running"
    fi

    # Check cluster status
    if kubectl get nodes 2>/dev/null | grep -q Ready; then
        print_color $GREEN "  ✓ K3s cluster is ready"
    else
        print_color $RED "  ✗ K3s cluster is not ready"
    fi

    # Check cert-manager
    if kubectl get pods -n cert-manager 2>/dev/null | grep -q Running; then
        print_color $GREEN "  ✓ cert-manager is running"
    else
        print_color $YELLOW "  ⚠ cert-manager is not running"
    fi

    # Check Rancher
    if kubectl get pods -n $RANCHER_NAMESPACE 2>/dev/null | grep -q Running; then
        print_color $GREEN "  ✓ Rancher is running"
    else
        print_color $YELLOW "  ⚠ Rancher is not running"
    fi

    # Check for failed pods
    local failed_pods=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | wc -l)
    if [ $failed_pods -le 1 ]; then  # Header line counts as 1
        print_color $GREEN "  ✓ No failed pods detected"
    else
        print_color $YELLOW "  ⚠ Some pods may have issues"
        kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
    fi
}

# Main menu
show_main_menu() {
    while true; do
        print_header
        print_color $YELLOW "=== LINUX AIR-GAP INSTALLATION MENU ==="
        echo ""
        print_color $GREEN "Installation Steps:"
        print_color $GREEN "  1. Check Air-Gap Assets"
        print_color $GREEN "  2. Install K3s (Air-Gap)"
        print_color $GREEN "  3. Install Helm (Air-Gap)"
        print_color $GREEN "  4. Load Container Images"
        print_color $GREEN "  5. Install cert-manager (Air-Gap)"
        print_color $GREEN "  6. Generate Certificates"
        print_color $GREEN "  7. Install Rancher (Air-Gap)"
        print_color $GREEN "  8. Full Air-Gap Installation"
        echo ""
        print_color $CYAN "Utilities:"
        print_color $CYAN "  9. Post-Installation Checks"
        print_color $CYAN "  10. Show Summary"
        echo ""
        print_color $RED "  0. Exit"
        echo ""

        read -p "Select option (0-10): " choice

        case $choice in
            1)
                check_airgap_assets
                read -p "Press Enter to continue..."
                ;;
            2)
                install_k3s_airgap
                read -p "Press Enter to continue..."
                ;;
            3)
                install_helm_airgap
                read -p "Press Enter to continue..."
                ;;
            4)
                load_container_images
                read -p "Press Enter to continue..."
                ;;
            5)
                install_cert_manager_airgap
                read -p "Press Enter to continue..."
                ;;
            6)
                generate_certificates
                read -p "Press Enter to continue..."
                ;;
            7)
                install_rancher_airgap
                read -p "Press Enter to continue..."
                ;;
            8)
                if confirm_action "Proceed with full air-gap installation?"; then
                    check_airgap_assets && \
                    install_k3s_airgap && \
                    install_helm_airgap && \
                    load_container_images && \
                    install_cert_manager_airgap && \
                    generate_certificates && \
                    install_rancher_airgap && \
                    post_install_checks && \
                    show_installation_summary
                fi
                read -p "Press Enter to continue..."
                ;;
            9)
                post_install_checks
                read -p "Press Enter to continue..."
                ;;
            10)
                show_installation_summary
                read -p "Press Enter to continue..."
                ;;
            0)
                print_color $GREEN "Goodbye!"
                exit 0
                ;;
            *)
                print_color $RED "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Handle command line arguments
case "${1:-}" in
    --full)
        print_header
        check_airgap_assets
        install_k3s_airgap
        install_helm_airgap
        load_container_images
        install_cert_manager_airgap
        generate_certificates
        install_rancher_airgap
        post_install_checks
        show_installation_summary
        ;;
    --check)
        check_airgap_assets
        post_install_checks
        ;;
    *)
        show_main_menu
        ;;
esac