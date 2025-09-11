#!/bin/bash

# K3s Management Script for EC2
# Comprehensive admin toolkit for Rancher K3s cluster management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/k3s_management.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if kubectl is available and cluster is accessible
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        print_color $RED "Error: kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_color $RED "Error: Cannot connect to K3s cluster"
        print_color $YELLOW "Make sure your kubeconfig is properly configured"
        exit 1
    fi
}

# Confirm destructive actions
confirm_action() {
    local action=$1
    print_color $YELLOW "Are you sure you want to $action? (yes/no): "
    read -r confirmation
    if [[ $confirmation != "yes" ]]; then
        print_color $CYAN "Operation cancelled."
        return 1
    fi
    return 0
}

# Main menu
show_main_menu() {
    clear
    print_color $BLUE "================================"
    print_color $BLUE "     K3s Management Script     "
    print_color $BLUE "================================"
    echo
    print_color $GREEN "1.  Cluster Overview"
    print_color $GREEN "2.  Node Management"
    print_color $GREEN "3.  Namespace Operations"
    print_color $GREEN "4.  Deployment Management"
    print_color $GREEN "5.  Service Management"
    print_color $GREEN "6.  Pod Operations"
    print_color $GREEN "7.  Storage Management"
    print_color $GREEN "8.  Monitoring & Logs"
    print_color $GREEN "9.  Security Operations"
    print_color $GREEN "10. Backup & Restore"
    print_color $GREEN "11. Troubleshooting Tools"
    print_color $GREEN "12. Quick Actions"
    print_color $RED "0.  Exit"
    echo
    print_color $CYAN "Enter your choice: "
}

# Cluster overview functions
cluster_overview() {
    clear
    print_color $BLUE "=== Cluster Overview ==="
    echo
    print_color $GREEN "1. Cluster Info"
    print_color $GREEN "2. Node Status"
    print_color $GREEN "3. Resource Usage"
    print_color $GREEN "4. All Namespaces Overview"
    print_color $GREEN "5. Cluster Events"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $BLUE "\n=== Cluster Information ==="
            kubectl cluster-info
            kubectl version --short 2>/dev/null || kubectl version
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            print_color $BLUE "\n=== Node Status ==="
            kubectl get nodes -o wide
            echo
            print_color $BLUE "\n=== Node Resources ==="
            kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"
            echo
            read -p "Press Enter to continue..."
            ;;
        3)
            print_color $BLUE "\n=== Resource Usage ==="
            kubectl get all --all-namespaces
            echo
            read -p "Press Enter to continue..."
            ;;
        4)
            print_color $BLUE "\n=== Namespaces Overview ==="
            kubectl get namespaces
            echo
            print_color $BLUE "\n=== Resource Count by Namespace ==="
            for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
                pod_count=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l)
                svc_count=$(kubectl get services -n $ns --no-headers 2>/dev/null | wc -l)
                deploy_count=$(kubectl get deployments -n $ns --no-headers 2>/dev/null | wc -l)
                printf "%-20s Pods: %-3s Services: %-3s Deployments: %-3s\n" "$ns" "$pod_count" "$svc_count" "$deploy_count"
            done
            echo
            read -p "Press Enter to continue..."
            ;;
        5)
            print_color $BLUE "\n=== Recent Cluster Events ==="
            kubectl get events --sort-by=.metadata.creationTimestamp --all-namespaces | tail -20
            echo
            read -p "Press Enter to continue..."
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    cluster_overview
}

# Node management functions
node_management() {
    clear
    print_color $BLUE "=== Node Management ==="
    echo
    print_color $GREEN "1. List Nodes"
    print_color $GREEN "2. Node Details"
    print_color $GREEN "3. Drain Node"
    print_color $GREEN "4. Uncordon Node"
    print_color $GREEN "5. Label Node"
    print_color $GREEN "6. Remove Label from Node"
    print_color $GREEN "7. Node Resource Usage"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $BLUE "\n=== Nodes ==="
            kubectl get nodes -o wide
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            print_color $CYAN "Enter node name: "
            read -r node_name
            print_color $BLUE "\n=== Node Details: $node_name ==="
            kubectl describe node "$node_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        3)
            kubectl get nodes
            print_color $CYAN "Enter node name to drain: "
            read -r node_name
            if confirm_action "drain node $node_name"; then
                kubectl drain "$node_name" --ignore-daemonsets --delete-emptydir-data
                log "Drained node: $node_name"
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        4)
            kubectl get nodes
            print_color $CYAN "Enter node name to uncordon: "
            read -r node_name
            kubectl uncordon "$node_name"
            print_color $GREEN "Node $node_name uncordoned"
            log "Uncordoned node: $node_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        5)
            kubectl get nodes
            print_color $CYAN "Enter node name: "
            read -r node_name
            print_color $CYAN "Enter label (key=value): "
            read -r label
            kubectl label nodes "$node_name" "$label"
            print_color $GREEN "Label added to node $node_name"
            log "Added label $label to node: $node_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        6)
            kubectl get nodes --show-labels
            print_color $CYAN "Enter node name: "
            read -r node_name
            print_color $CYAN "Enter label key to remove: "
            read -r label_key
            kubectl label nodes "$node_name" "$label_key-"
            print_color $GREEN "Label removed from node $node_name"
            log "Removed label $label_key from node: $node_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        7)
            print_color $BLUE "\n=== Node Resource Usage ==="
            kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"
            echo
            print_color $BLUE "\n=== Node Capacity ==="
            kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,STORAGE:.status.capacity.ephemeral-storage
            echo
            read -p "Press Enter to continue..."
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    node_management
}

# Namespace operations
namespace_operations() {
    clear
    print_color $BLUE "=== Namespace Operations ==="
    echo
    print_color $GREEN "1. List Namespaces"
    print_color $GREEN "2. Create Namespace"
    print_color $GREEN "3. Delete Namespace"
    print_color $GREEN "4. Namespace Details"
    print_color $GREEN "5. Set Default Namespace"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $BLUE "\n=== Namespaces ==="
            kubectl get namespaces -o wide
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            print_color $CYAN "Enter namespace name: "
            read -r ns_name
            kubectl create namespace "$ns_name"
            print_color $GREEN "Namespace $ns_name created"
            log "Created namespace: $ns_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        3)
            kubectl get namespaces
            print_color $CYAN "Enter namespace name to delete: "
            read -r ns_name
            if confirm_action "delete namespace $ns_name"; then
                kubectl delete namespace "$ns_name"
                print_color $GREEN "Namespace $ns_name deleted"
                log "Deleted namespace: $ns_name"
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        4)
            kubectl get namespaces
            print_color $CYAN "Enter namespace name: "
            read -r ns_name
            print_color $BLUE "\n=== Namespace Details: $ns_name ==="
            kubectl describe namespace "$ns_name"
            echo
            print_color $BLUE "\n=== Resources in namespace ==="
            kubectl get all -n "$ns_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        5)
            kubectl get namespaces
            print_color $CYAN "Enter namespace to set as default: "
            read -r ns_name
            kubectl config set-context --current --namespace="$ns_name"
            print_color $GREEN "Default namespace set to $ns_name"
            log "Set default namespace to: $ns_name"
            echo
            read -p "Press Enter to continue..."
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    namespace_operations
}

# Deployment management functions
deployment_management() {
    clear
    print_color $BLUE "=== Deployment Management ==="
    echo
    print_color $GREEN "1.  List Deployments"
    print_color $GREEN "2.  Create Deployment"
    print_color $GREEN "3.  Update Deployment"
    print_color $GREEN "4.  Scale Deployment"
    print_color $GREEN "5.  Delete Deployment"
    print_color $GREEN "6.  Deployment Details"
    print_color $GREEN "7.  Rollback Deployment"
    print_color $GREEN "8.  Deployment History"
    print_color $GREEN "9.  Restart Deployment"
    print_color $GREEN "10. Quick Deploy from Image"
    print_color $RED "0.  Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get deployments --all-namespaces -o wide
            else
                kubectl get deployments -n "$namespace" -o wide
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            create_deployment_interactive
            ;;
        3)
            update_deployment_interactive
            ;;
        4)
            scale_deployment_interactive
            ;;
        5)
            delete_deployment_interactive
            ;;
        6)
            deployment_details_interactive
            ;;
        7)
            rollback_deployment_interactive
            ;;
        8)
            deployment_history_interactive
            ;;
        9)
            restart_deployment_interactive
            ;;
        10)
            quick_deploy_interactive
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    deployment_management
}

# Interactive deployment creation
create_deployment_interactive() {
    print_color $BLUE "\n=== Create Deployment ==="
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter container image: "
    read -r image
    print_color $CYAN "Enter number of replicas (default 1): "
    read -r replicas
    replicas=${replicas:-1}
    print_color $CYAN "Enter container port (optional): "
    read -r port

    # Create deployment YAML
    cat > /tmp/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $deploy_name
  namespace: $namespace
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $deploy_name
  template:
    metadata:
      labels:
        app: $deploy_name
    spec:
      containers:
      - name: $deploy_name
        image: $image
EOF

    if [[ -n $port ]]; then
        cat >> /tmp/deployment.yaml << EOF
        ports:
        - containerPort: $port
EOF
    fi

    print_color $BLUE "\n=== Generated YAML ==="
    cat /tmp/deployment.yaml
    echo

    if confirm_action "create this deployment"; then
        kubectl create namespace "$namespace" 2>/dev/null || true
        kubectl apply -f /tmp/deployment.yaml
        print_color $GREEN "Deployment $deploy_name created in namespace $namespace"
        log "Created deployment: $deploy_name in namespace: $namespace"
    fi

    rm -f /tmp/deployment.yaml
    echo
    read -p "Press Enter to continue..."
}

# Interactive deployment update
update_deployment_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name
    print_color $CYAN "Enter new image: "
    read -r new_image

    kubectl set image deployment/"$deploy_name" "$deploy_name"="$new_image" -n "$namespace"
    print_color $GREEN "Deployment $deploy_name updated with image $new_image"
    log "Updated deployment: $deploy_name with image: $new_image"
    echo
    read -p "Press Enter to continue..."
}

# Interactive deployment scaling
scale_deployment_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name
    print_color $CYAN "Enter number of replicas: "
    read -r replicas

    kubectl scale deployment "$deploy_name" --replicas="$replicas" -n "$namespace"
    print_color $GREEN "Deployment $deploy_name scaled to $replicas replicas"
    log "Scaled deployment: $deploy_name to $replicas replicas"
    echo
    read -p "Press Enter to continue..."
}

# Interactive deployment deletion
delete_deployment_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name

    if confirm_action "delete deployment $deploy_name"; then
        kubectl delete deployment "$deploy_name" -n "$namespace"
        print_color $GREEN "Deployment $deploy_name deleted"
        log "Deleted deployment: $deploy_name"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Deployment details
deployment_details_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name

    print_color $BLUE "\n=== Deployment Details ==="
    kubectl describe deployment "$deploy_name" -n "$namespace"

    print_color $BLUE "\n=== Related Pods ==="
    kubectl get pods -n "$namespace" -l app="$deploy_name"
    echo
    read -p "Press Enter to continue..."
}

# Rollback deployment
rollback_deployment_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name

    print_color $BLUE "\n=== Rollout History ==="
    kubectl rollout history deployment/"$deploy_name" -n "$namespace"

    print_color $CYAN "Enter revision number to rollback to (or press Enter for previous): "
    read -r revision

    if [[ -n $revision ]]; then
        kubectl rollout undo deployment/"$deploy_name" --to-revision="$revision" -n "$namespace"
    else
        kubectl rollout undo deployment/"$deploy_name" -n "$namespace"
    fi

    print_color $GREEN "Deployment $deploy_name rolled back"
    log "Rolled back deployment: $deploy_name"
    echo
    read -p "Press Enter to continue..."
}

# Deployment history
deployment_history_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name

    print_color $BLUE "\n=== Deployment History ==="
    kubectl rollout history deployment/"$deploy_name" -n "$namespace"

    print_color $BLUE "\n=== Current Status ==="
    kubectl rollout status deployment/"$deploy_name" -n "$namespace"
    echo
    read -p "Press Enter to continue..."
}

# Restart deployment
restart_deployment_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name

    if confirm_action "restart deployment $deploy_name"; then
        kubectl rollout restart deployment/"$deploy_name" -n "$namespace"
        print_color $GREEN "Deployment $deploy_name restarted"
        log "Restarted deployment: $deploy_name"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Quick deploy from image
quick_deploy_interactive() {
    print_color $BLUE "\n=== Quick Deploy from Image ==="
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name
    print_color $CYAN "Enter image (e.g., nginx:latest): "
    read -r image
    print_color $CYAN "Enter namespace (default: default): "
    read -r namespace
    namespace=${namespace:-default}
    print_color $CYAN "Enter port to expose (optional): "
    read -r port

    # Create deployment
    kubectl create deployment "$deploy_name" --image="$image" -n "$namespace"

    # Expose service if port specified
    if [[ -n $port ]]; then
        kubectl expose deployment "$deploy_name" --port="$port" --target-port="$port" -n "$namespace"
        print_color $GREEN "Deployment $deploy_name created and exposed on port $port"
    else
        print_color $GREEN "Deployment $deploy_name created"
    fi

    log "Quick deployed: $deploy_name with image: $image"
    echo
    read -p "Press Enter to continue..."
}

# Service management
service_management() {
    clear
    print_color $BLUE "=== Service Management ==="
    echo
    print_color $GREEN "1. List Services"
    print_color $GREEN "2. Create Service"
    print_color $GREEN "3. Delete Service"
    print_color $GREEN "4. Service Details"
    print_color $GREEN "5. Expose Deployment"
    print_color $GREEN "6. Service Endpoints"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get services --all-namespaces -o wide
            else
                kubectl get services -n "$namespace" -o wide
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            create_service_interactive
            ;;
        3)
            delete_service_interactive
            ;;
        4)
            service_details_interactive
            ;;
        5)
            expose_deployment_interactive
            ;;
        6)
            service_endpoints_interactive
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    service_management
}

# Create service interactively
create_service_interactive() {
    print_color $BLUE "\n=== Create Service ==="
    print_color $CYAN "Enter service name: "
    read -r svc_name
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter selector (app=labelvalue): "
    read -r selector
    print_color $CYAN "Enter port: "
    read -r port
    print_color $CYAN "Enter target port (default same as port): "
    read -r target_port
    target_port=${target_port:-$port}
    print_color $CYAN "Enter service type (ClusterIP/NodePort/LoadBalancer): "
    read -r svc_type
    svc_type=${svc_type:-ClusterIP}

    kubectl create service "$svc_type" "$svc_name" --tcp="$port":"$target_port" -n "$namespace"
    kubectl patch service "$svc_name" -n "$namespace" -p '{"spec":{"selector":{"'${selector%=*}'":"'${selector#*=}'"}}}'

    print_color $GREEN "Service $svc_name created"
    log "Created service: $svc_name"
    echo
    read -p "Press Enter to continue..."
}

# Delete service
delete_service_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get services -n "$namespace"
    print_color $CYAN "Enter service name: "
    read -r svc_name

    if confirm_action "delete service $svc_name"; then
        kubectl delete service "$svc_name" -n "$namespace"
        print_color $GREEN "Service $svc_name deleted"
        log "Deleted service: $svc_name"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Service details
service_details_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get services -n "$namespace"
    print_color $CYAN "Enter service name: "
    read -r svc_name

    print_color $BLUE "\n=== Service Details ==="
    kubectl describe service "$svc_name" -n "$namespace"
    echo
    read -p "Press Enter to continue..."
}

# Expose deployment
expose_deployment_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get deployments -n "$namespace"
    print_color $CYAN "Enter deployment name: "
    read -r deploy_name
    print_color $CYAN "Enter port: "
    read -r port
    print_color $CYAN "Enter service type (ClusterIP/NodePort/LoadBalancer): "
    read -r svc_type
    svc_type=${svc_type:-ClusterIP}

    kubectl expose deployment "$deploy_name" --port="$port" --type="$svc_type" -n "$namespace"
    print_color $GREEN "Deployment $deploy_name exposed as $svc_type service"
    log "Exposed deployment: $deploy_name"
    echo
    read -p "Press Enter to continue..."
}

# Service endpoints
service_endpoints_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get services -n "$namespace"
    print_color $CYAN "Enter service name: "
    read -r svc_name

    print_color $BLUE "\n=== Service Endpoints ==="
    kubectl get endpoints "$svc_name" -n "$namespace" -o wide
    echo
    read -p "Press Enter to continue..."
}

# Pod operations
pod_operations() {
    clear
    print_color $BLUE "=== Pod Operations ==="
    echo
    print_color $GREEN "1. List Pods"
    print_color $GREEN "2. Pod Details"
    print_color $GREEN "3. Pod Logs"
    print_color $GREEN "4. Execute into Pod"
    print_color $GREEN "5. Delete Pod"
    print_color $GREEN "6. Port Forward"
    print_color $GREEN "7. Copy Files to/from Pod"
    print_color $GREEN "8. Pod Resource Usage"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get pods --all-namespaces -o wide
            else
                kubectl get pods -n "$namespace" -o wide
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            pod_details_interactive
            ;;
        3)
            pod_logs_interactive
            ;;
        4)
            pod_exec_interactive
            ;;
        5)
            delete_pod_interactive
            ;;
        6)
            port_forward_interactive
            ;;
        7)
            copy_files_interactive
            ;;
        8)
            pod_resources_interactive
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    pod_operations
}

# Pod details
pod_details_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name

    print_color $BLUE "\n=== Pod Details ==="
    kubectl describe pod "$pod_name" -n "$namespace"
    echo
    read -p "Press Enter to continue..."
}

# Pod logs
pod_logs_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name
    print_color $CYAN "Follow logs? (y/n): "
    read -r follow
    print_color $CYAN "Number of lines (default: 100): "
    read -r lines
    lines=${lines:-100}

    if [[ $follow == "y" ]]; then
        print_color $BLUE "\n=== Following logs (Ctrl+C to stop) ==="
        kubectl logs -f "$pod_name" -n "$namespace" --tail="$lines"
    else
        print_color $BLUE "\n=== Pod Logs ==="
        kubectl logs "$pod_name" -n "$namespace" --tail="$lines"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Execute into pod
pod_exec_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name
    print_color $CYAN "Enter command (default: /bin/bash): "
    read -r command
    command=${command:-/bin/bash}

    print_color $BLUE "\n=== Executing into pod (type 'exit' to return) ==="
    kubectl exec -it "$pod_name" -n "$namespace" -- "$command"
    echo
    read -p "Press Enter to continue..."
}

# Delete pod
delete_pod_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name

    if confirm_action "delete pod $pod_name"; then
        kubectl delete pod "$pod_name" -n "$namespace"
        print_color $GREEN "Pod $pod_name deleted"
        log "Deleted pod: $pod_name"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Port forward
port_forward_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name
    print_color $CYAN "Enter local port: "
    read -r local_port
    print_color $CYAN "Enter pod port: "
    read -r pod_port

    print_color $BLUE "\n=== Port forwarding $local_port:$pod_port (Ctrl+C to stop) ==="
    kubectl port-forward "$pod_name" "$local_port":"$pod_port" -n "$namespace"
    echo
    read -p "Press Enter to continue..."
}

# Copy files
copy_files_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name
    print_color $CYAN "Copy direction (to-pod/from-pod): "
    read -r direction

    if [[ $direction == "to-pod" ]]; then
        print_color $CYAN "Enter local file path: "
        read -r local_path
        print_color $CYAN "Enter pod destination path: "
        read -r pod_path
        kubectl cp "$local_path" "$namespace/$pod_name:$pod_path"
        print_color $GREEN "File copied to pod"
    elif [[ $direction == "from-pod" ]]; then
        print_color $CYAN "Enter pod file path: "
        read -r pod_path
        print_color $CYAN "Enter local destination path: "
        read -r local_path
        kubectl cp "$namespace/$pod_name:$pod_path" "$local_path"
        print_color $GREEN "File copied from pod"
    else
        print_color $RED "Invalid direction"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Pod resources
pod_resources_interactive() {
    print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
    read -r namespace

    print_color $BLUE "\n=== Pod Resource Usage ==="
    if [[ $namespace == "all" ]]; then
        kubectl top pods --all-namespaces 2>/dev/null || print_color $YELLOW "Metrics server not available"
    else
        kubectl top pods -n "$namespace" 2>/dev/null || print_color $YELLOW "Metrics server not available"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Storage management
storage_management() {
    clear
    print_color $BLUE "=== Storage Management ==="
    echo
    print_color $GREEN "1. List Persistent Volumes"
    print_color $GREEN "2. List Persistent Volume Claims"
    print_color $GREEN "3. Storage Classes"
    print_color $GREEN "4. Create PVC"
    print_color $GREEN "5. Delete PVC"
    print_color $GREEN "6. PV/PVC Details"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $BLUE "\n=== Persistent Volumes ==="
            kubectl get pv -o wide
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get pvc --all-namespaces -o wide
            else
                kubectl get pvc -n "$namespace" -o wide
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        3)
            print_color $BLUE "\n=== Storage Classes ==="
            kubectl get storageclass -o wide
            echo
            read -p "Press Enter to continue..."
            ;;
        4)
            create_pvc_interactive
            ;;
        5)
            delete_pvc_interactive
            ;;
        6)
            storage_details_interactive
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    storage_management
}

# Create PVC
create_pvc_interactive() {
    print_color $BLUE "\n=== Create Persistent Volume Claim ==="
    print_color $CYAN "Enter PVC name: "
    read -r pvc_name
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter size (e.g., 10Gi): "
    read -r size
    kubectl get storageclass
    print_color $CYAN "Enter storage class (or press Enter for default): "
    read -r storage_class

    cat > /tmp/pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc_name
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $size
EOF

    if [[ -n $storage_class ]]; then
        echo "  storageClassName: $storage_class" >> /tmp/pvc.yaml
    fi

    print_color $BLUE "\n=== Generated YAML ==="
    cat /tmp/pvc.yaml
    echo

    if confirm_action "create this PVC"; then
        kubectl apply -f /tmp/pvc.yaml
        print_color $GREEN "PVC $pvc_name created"
        log "Created PVC: $pvc_name"
    fi

    rm -f /tmp/pvc.yaml
    echo
    read -p "Press Enter to continue..."
}

# Delete PVC
delete_pvc_interactive() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pvc -n "$namespace"
    print_color $CYAN "Enter PVC name: "
    read -r pvc_name

    if confirm_action "delete PVC $pvc_name"; then
        kubectl delete pvc "$pvc_name" -n "$namespace"
        print_color $GREEN "PVC $pvc_name deleted"
        log "Deleted PVC: $prac_name"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Storage details
storage_details_interactive() {
    print_color $CYAN "Resource type (pv/pvc): "
    read -r resource_type

    if [[ $resource_type == "pv" ]]; then
        kubectl get pv
        print_color $CYAN "Enter PV name: "
        read -r resource_name
        kubectl describe pv "$resource_name"
    elif [[ $resource_type == "pvc" ]]; then
        print_color $CYAN "Enter namespace: "
        read -r namespace
        kubectl get pvc -n "$namespace"
        print_color $CYAN "Enter PVC name: "
        read -r resource_name
        kubectl describe pvc "$resource_name" -n "$namespace"
    else
        print_color $RED "Invalid resource type"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Monitoring and logs
monitoring_logs() {
    clear
    print_color $BLUE "=== Monitoring & Logs ==="
    echo
    print_color $GREEN "1. Cluster Resource Usage"
    print_color $GREEN "2. Node Resource Usage"
    print_color $GREEN "3. Pod Resource Usage"
    print_color $GREEN "4. Events (Recent)"
    print_color $GREEN "5. Application Logs"
    print_color $GREEN "6. System Component Status"
    print_color $GREEN "7. Resource Quotas"
    print_color $GREEN "8. Live Resource Monitor"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $BLUE "\n=== Cluster Resource Usage ==="
            kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"
            echo
            kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            print_color $BLUE "\n=== Node Resource Usage ==="
            kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"
            echo
            kubectl describe nodes | grep -E "(Name:|  cpu:|  memory:|  ephemeral-storage:)" | paste - - - -
            echo
            read -p "Press Enter to continue..."
            ;;
        3)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            print_color $BLUE "\n=== Pod Resource Usage ==="
            if [[ $namespace == "all" ]]; then
                kubectl top pods --all-namespaces 2>/dev/null || print_color $YELLOW "Metrics server not available"
            else
                kubectl top pods -n "$namespace" 2>/dev/null || print_color $YELLOW "Metrics server not available"
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        4)
            print_color $BLUE "\n=== Recent Events ==="
            kubectl get events --sort-by=.metadata.creationTimestamp --all-namespaces | tail -20
            echo
            read -p "Press Enter to continue..."
            ;;
        5)
            pod_logs_interactive
            ;;
        6)
            print_color $BLUE "\n=== System Component Status ==="
            kubectl get componentstatuses 2>/dev/null || print_color $YELLOW "Component status not available"
            echo
            print_color $BLUE "\n=== System Pods ==="
            kubectl get pods -n kube-system
            echo
            read -p "Press Enter to continue..."
            ;;
        7)
            print_color $CYAN "Enter namespace: "
            read -r namespace
            print_color $BLUE "\n=== Resource Quotas ==="
            kubectl get resourcequotas -n "$namespace"
            echo
            print_color $BLUE "\n=== Limit Ranges ==="
            kubectl get limitranges -n "$namespace"
            echo
            read -p "Press Enter to continue..."
            ;;
        8)
            print_color $BLUE "\n=== Live Resource Monitor (Ctrl+C to stop) ==="
            while true; do
                clear
                print_color $BLUE "=== Live Cluster Status ==="
                date
                echo
                kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"
                echo
                kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | head -10
                sleep 5
            done
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    monitoring_logs
}

# Security operations
security_operations() {
    clear
    print_color $BLUE "=== Security Operations ==="
    echo
    print_color $GREEN "1. Service Accounts"
    print_color $GREEN "2. Roles and RoleBindings"
    print_color $GREEN "3. Secrets Management"
    print_color $GREEN "4. ConfigMaps"
    print_color $GREEN "5. Network Policies"
    print_color $GREEN "6. Pod Security"
    print_color $GREEN "7. RBAC Check"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get serviceaccounts --all-namespaces
            else
                kubectl get serviceaccounts -n "$namespace"
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        2)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            print_color $BLUE "\n=== Roles ==="
            if [[ $namespace == "all" ]]; then
                kubectl get roles --all-namespaces
            else
                kubectl get roles -n "$namespace"
            fi
            print_color $BLUE "\n=== RoleBindings ==="
            if [[ $namespace == "all" ]]; then
                kubectl get rolebindings --all-namespaces
            else
                kubectl get rolebindings -n "$namespace"
            fi
            print_color $BLUE "\n=== ClusterRoles ==="
            kubectl get clusterroles
            print_color $BLUE "\n=== ClusterRoleBindings ==="
            kubectl get clusterrolebindings
            echo
            read -p "Press Enter to continue..."
            ;;
        3)
            secrets_management
            ;;
        4)
            configmaps_management
            ;;
        5)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get networkpolicies --all-namespaces
            else
                kubectl get networkpolicies -n "$namespace"
            fi
            echo
            read -p "Press Enter to continue..."
            ;;
        6)
            print_color $BLUE "\n=== Pod Security Standards ==="
            kubectl get podsecuritypolicy 2>/dev/null || print_color $YELLOW "Pod Security Policies not available"
            echo
            print_color $BLUE "\n=== Security Contexts ==="
            kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.securityContext}{"\n"}{end}' | head -10
            echo
            read -p "Press Enter to continue..."
            ;;
        7)
            rbac_check
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    security_operations
}

# Secrets management
secrets_management() {
    print_color $BLUE "\n=== Secrets Management ==="
    print_color $GREEN "1. List Secrets"
    print_color $GREEN "2. Create Secret"
    print_color $GREEN "3. Delete Secret"
    print_color $GREEN "4. Secret Details"
    print_color $RED "0. Back"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get secrets --all-namespaces
            else
                kubectl get secrets -n "$namespace"
            fi
            ;;
        2)
            print_color $CYAN "Enter secret name: "
            read -r secret_name
            print_color $CYAN "Enter namespace: "
            read -r namespace
            print_color $CYAN "Enter key: "
            read -r key
            print_color $CYAN "Enter value: "
            read -s value
            echo
            kubectl create secret generic "$secret_name" --from-literal="$key"="$value" -n "$namespace"
            print_color $GREEN "Secret $secret_name created"
            log "Created secret: $secret_name"
            ;;
        3)
            print_color $CYAN "Enter namespace: "
            read -r namespace
            kubectl get secrets -n "$namespace"
            print_color $CYAN "Enter secret name: "
            read -r secret_name
            if confirm_action "delete secret $secret_name"; then
                kubectl delete secret "$secret_name" -n "$namespace"
                print_color $GREEN "Secret $secret_name deleted"
                log "Deleted secret: $secret_name"
            fi
            ;;
        4)
            print_color $CYAN "Enter namespace: "
            read -r namespace
            kubectl get secrets -n "$namespace"
            print_color $CYAN "Enter secret name: "
            read -r secret_name
            kubectl describe secret "$secret_name" -n "$namespace"
            ;;
        0) return ;;
    esac
    echo
    read -p "Press Enter to continue..."
}

# ConfigMaps management
configmaps_management() {
    print_color $BLUE "\n=== ConfigMaps Management ==="
    print_color $GREEN "1. List ConfigMaps"
    print_color $GREEN "2. Create ConfigMap"
    print_color $GREEN "3. Delete ConfigMap"
    print_color $GREEN "4. ConfigMap Details"
    print_color $RED "0. Back"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get configmaps --all-namespaces
            else
                kubectl get configmaps -n "$namespace"
            fi
            ;;
        2)
            print_color $CYAN "Enter configmap name: "
            read -r cm_name
            print_color $CYAN "Enter namespace: "
            read -r namespace
            print_color $CYAN "Enter key: "
            read -r key
            print_color $CYAN "Enter value: "
            read -r value
            kubectl create configmap "$cm_name" --from-literal="$key"="$value" -n "$namespace"
            print_color $GREEN "ConfigMap $cm_name created"
            log "Created configmap: $cm_name"
            ;;
        3)
            print_color $CYAN "Enter namespace: "
            read -r namespace
            kubectl get configmaps -n "$namespace"
            print_color $CYAN "Enter configmap name: "
            read -r cm_name
            if confirm_action "delete configmap $cm_name"; then
                kubectl delete configmap "$cm_name" -n "$namespace"
                print_color $GREEN "ConfigMap $cm_name deleted"
                log "Deleted configmap: $cm_name"
            fi
            ;;
        4)
            print_color $CYAN "Enter namespace: "
            read -r namespace
            kubectl get configmaps -n "$namespace"
            print_color $CYAN "Enter configmap name: "
            read -r cm_name
            kubectl describe configmap "$cm_name" -n "$namespace"
            ;;
        0) return ;;
    esac
    echo
    read -p "Press Enter to continue..."
}

# RBAC check
rbac_check() {
    print_color $BLUE "\n=== RBAC Check ==="
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter service account name: "
    read -r sa_name
    print_color $CYAN "Enter verb (get/list/create/delete/etc): "
    read -r verb
    print_color $CYAN "Enter resource (pods/services/deployments/etc): "
    read -r resource

    kubectl auth can-i "$verb" "$resource" --as=system:serviceaccount:"$namespace":"$sa_name" -n "$namespace"
    echo
    read -p "Press Enter to continue..."
}

# Backup and restore
backup_restore() {
    clear
    print_color $BLUE "=== Backup & Restore ==="
    echo
    print_color $GREEN "1. Export Resources"
    print_color $GREEN "2. Backup Namespace"
    print_color $GREEN "3. Export All Configurations"
    print_color $GREEN "4. Create Resource Snapshots"
    print_color $GREEN "5. List Available Backups"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            export_resources
            ;;
        2)
            backup_namespace
            ;;
        3)
            export_all_configs
            ;;
        4)
            create_snapshots
            ;;
        5)
            list_backups
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    backup_restore
}

# Export resources
export_resources() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter resource type (deployment/service/configmap/secret/all): "
    read -r resource_type

    backup_dir="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    if [[ $resource_type == "all" ]]; then
        kubectl get all -n "$namespace" -o yaml > "$backup_dir/all-resources.yaml"
        kubectl get configmaps -n "$namespace" -o yaml > "$backup_dir/configmaps.yaml"
        kubectl get secrets -n "$namespace" -o yaml > "$backup_dir/secrets.yaml"
        kubectl get pvc -n "$namespace" -o yaml > "$backup_dir/pvcs.yaml"
    else
        kubectl get "$resource_type" -n "$namespace" -o yaml > "$backup_dir/$resource_type.yaml"
    fi

    print_color $GREEN "Resources exported to $backup_dir"
    log "Exported resources: $resource_type from namespace: $namespace"
    echo
    read -p "Press Enter to continue..."
}

# Backup namespace
backup_namespace() {
    print_color $CYAN "Enter namespace to backup: "
    read -r namespace

    backup_dir="$SCRIPT_DIR/backups/namespace_${namespace}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Export namespace definition
    kubectl get namespace "$namespace" -o yaml > "$backup_dir/namespace.yaml"

    # Export all resources
    kubectl get all -n "$namespace" -o yaml > "$backup_dir/all-resources.yaml"
    kubectl get configmaps -n "$namespace" -o yaml > "$backup_dir/configmaps.yaml"
    kubectl get secrets -n "$namespace" -o yaml > "$backup_dir/secrets.yaml"
    kubectl get pvc -n "$namespace" -o yaml > "$backup_dir/pvcs.yaml"
    kubectl get serviceaccounts -n "$namespace" -o yaml > "$backup_dir/serviceaccounts.yaml"
    kubectl get roles -n "$namespace" -o yaml > "$backup_dir/roles.yaml"
    kubectl get rolebindings -n "$namespace" -o yaml > "$backup_dir/rolebindings.yaml"
    kubectl get networkpolicies -n "$namespace" -o yaml > "$backup_dir/networkpolicies.yaml" 2>/dev/null || true

    print_color $GREEN "Namespace $namespace backed up to $backup_dir"
    log "Backed up namespace: $namespace"
    echo
    read -p "Press Enter to continue..."
}

# Export all configurations
export_all_configs() {
    backup_dir="$SCRIPT_DIR/backups/cluster_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    print_color $BLUE "Creating cluster backup..."

    # Cluster-wide resources
    kubectl get nodes -o yaml > "$backup_dir/nodes.yaml"
    kubectl get namespaces -o yaml > "$backup_dir/namespaces.yaml"
    kubectl get clusterroles -o yaml > "$backup_dir/clusterroles.yaml"
    kubectl get clusterrolebindings -o yaml > "$backup_dir/clusterrolebindings.yaml"
    kubectl get storageclass -o yaml > "$backup_dir/storageclasses.yaml"
    kubectl get pv -o yaml > "$backup_dir/persistentvolumes.yaml"

    # Per-namespace resources
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        ns_dir="$backup_dir/namespaces/$ns"
        mkdir -p "$ns_dir"

        kubectl get all -n "$ns" -o yaml > "$ns_dir/all-resources.yaml" 2>/dev/null || true
        kubectl get configmaps -n "$ns" -o yaml > "$ns_dir/configmaps.yaml" 2>/dev/null || true
        kubectl get secrets -n "$ns" -o yaml > "$ns_dir/secrets.yaml" 2>/dev/null || true
        kubectl get pvc -n "$ns" -o yaml > "$ns_dir/pvcs.yaml" 2>/dev/null || true
    done

    print_color $GREEN "Full cluster backup created at $backup_dir"
    log "Created full cluster backup"
    echo
    read -p "Press Enter to continue..."
}

# Create snapshots
create_snapshots() {
    print_color $CYAN "Enter resource type (deployment/statefulset/daemonset): "
    read -r resource_type
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter resource name: "
    read -r resource_name

    snapshot_dir="$SCRIPT_DIR/snapshots/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$snapshot_dir"

    kubectl get "$resource_type" "$resource_name" -n "$namespace" -o yaml > "$snapshot_dir/${resource_type}_${resource_name}.yaml"

    # If it's a deployment, also capture related services
    if [[ $resource_type == "deployment" ]]; then
        kubectl get services -n "$namespace" -l app="$resource_name" -o yaml > "$snapshot_dir/services_${resource_name}.yaml" 2>/dev/null || true
    fi

    print_color $GREEN "Snapshot created at $snapshot_dir"
    log "Created snapshot: $resource_type/$resource_name"
    echo
    read -p "Press Enter to continue..."
}

# List backups
list_backups() {
    print_color $BLUE "\n=== Available Backups ==="
    if [[ -d "$SCRIPT_DIR/backups" ]]; then
        ls -la "$SCRIPT_DIR/backups/"
    else
        print_color $YELLOW "No backups found"
    fi

    print_color $BLUE "\n=== Available Snapshots ==="
    if [[ -d "$SCRIPT_DIR/snapshots" ]]; then
        ls -la "$SCRIPT_DIR/snapshots/"
    else
        print_color $YELLOW "No snapshots found"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Troubleshooting tools
troubleshooting_tools() {
    clear
    print_color $BLUE "=== Troubleshooting Tools ==="
    echo
    print_color $GREEN "1. Cluster Health Check"
    print_color $GREEN "2. Node Diagnostics"
    print_color $GREEN "3. Pod Troubleshooting"
    print_color $GREEN "4. Network Connectivity Test"
    print_color $GREEN "5. Resource Usage Analysis"
    print_color $GREEN "6. Event Analysis"
    print_color $GREEN "7. Service Discovery Test"
    print_color $GREEN "8. DNS Resolution Test"
    print_color $RED "0. Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            cluster_health_check
            ;;
        2)
            node_diagnostics
            ;;
        3)
            pod_troubleshooting
            ;;
        4)
            network_connectivity_test
            ;;
        5)
            resource_usage_analysis
            ;;
        6)
            event_analysis
            ;;
        7)
            service_discovery_test
            ;;
        8)
            dns_resolution_test
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    troubleshooting_tools
}

# Cluster health check
cluster_health_check() {
    print_color $BLUE "\n=== Cluster Health Check ==="

    print_color $BLUE "\n1. Cluster Info:"
    kubectl cluster-info

    print_color $BLUE "\n2. Node Status:"
    kubectl get nodes

    print_color $BLUE "\n3. System Pods:"
    kubectl get pods -n kube-system

    print_color $BLUE "\n4. Component Status:"
    kubectl get componentstatuses 2>/dev/null || print_color $YELLOW "Component status not available"

    print_color $BLUE "\n5. Recent Events:"
    kubectl get events --sort-by=.metadata.creationTimestamp | tail -10

    print_color $BLUE "\n6. Failed Pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded

    print_color $BLUE "\n7. Resource Usage:"
    kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"

    echo
    read -p "Press Enter to continue..."
}

# Node diagnostics
node_diagnostics() {
    kubectl get nodes
    print_color $CYAN "Enter node name for diagnostics: "
    read -r node_name

    print_color $BLUE "\n=== Node Diagnostics: $node_name ==="

    print_color $BLUE "\n1. Node Details:"
    kubectl describe node "$node_name"

    print_color $BLUE "\n2. Node Conditions:"
    kubectl get node "$node_name" -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}{"\n"}' | paste - -

    print_color $BLUE "\n3. Pods on Node:"
    kubectl get pods --all-namespaces --field-selector=spec.nodeName="$node_name"

    print_color $BLUE "\n4. Node Resource Usage:"
    kubectl top node "$node_name" 2>/dev/null || print_color $YELLOW "Metrics server not available"

    echo
    read -p "Press Enter to continue..."
}

# Pod troubleshooting
pod_troubleshooting() {
    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get pods -n "$namespace"
    print_color $CYAN "Enter pod name: "
    read -r pod_name

    print_color $BLUE "\n=== Pod Troubleshooting: $pod_name ==="

    print_color $BLUE "\n1. Pod Status:"
    kubectl get pod "$pod_name" -n "$namespace" -o wide

    print_color $BLUE "\n2. Pod Details:"
    kubectl describe pod "$pod_name" -n "$namespace"

    print_color $BLUE "\n3. Pod Events:"
    kubectl get events --field-selector involvedObject.name="$pod_name" -n "$namespace"

    print_color $BLUE "\n4. Container Logs:"
    kubectl logs "$pod_name" -n "$namespace" --tail=20

    print_color $BLUE "\n5. Previous Container Logs (if crashed):"
    kubectl logs "$pod_name" -n "$namespace" --previous --tail=20 2>/dev/null || print_color $YELLOW "No previous logs available"

    print_color $BLUE "\n6. Resource Usage:"
    kubectl top pod "$pod_name" -n "$namespace" 2>/dev/null || print_color $YELLOW "Metrics server not available"

    echo
    read -p "Press Enter to continue..."
}

# Network connectivity test
network_connectivity_test() {
    print_color $BLUE "\n=== Network Connectivity Test ==="

    # Create a test pod for network testing
    kubectl run nettest --image=nicolaka/netshoot --rm -it --restart=Never -- /bin/bash -c "
        echo 'Testing DNS resolution:'
        nslookup kubernetes.default.svc.cluster.local
        echo ''
        echo 'Testing external connectivity:'
        curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' http://www.google.com
        echo ''
        echo 'Testing cluster connectivity:'
        curl -s -o /dev/null -w 'Kubernetes API HTTP Status: %{http_code}\n' https://kubernetes.default.svc.cluster.local:443 -k
    " 2>/dev/null || print_color $RED "Network test failed"

    echo
    read -p "Press Enter to continue..."
}

# Resource usage analysis
resource_usage_analysis() {
    print_color $BLUE "\n=== Resource Usage Analysis ==="

    print_color $BLUE "\n1. Node Resource Usage:"
    kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"

    print_color $BLUE "\n2. Top Resource Consuming Pods:"
    kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -10 || print_color $YELLOW "Metrics server not available"

    print_color $BLUE "\n3. Pod Resource Requests vs Limits:"
    kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory,CPU_LIM:.spec.containers[*].resources.limits.cpu,MEM_LIM:.spec.containers[*].resources.limits.memory | head -20

    print_color $BLUE "\n4. Node Capacity vs Allocatable:"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU_CAP:.status.capacity.cpu,CPU_ALLOC:.status.allocatable.cpu,MEM_CAP:.status.capacity.memory,MEM_ALLOC:.status.allocatable.memory

    echo
    read -p "Press Enter to continue..."
}

# Event analysis
event_analysis() {
    print_color $BLUE "\n=== Event Analysis ==="

    print_color $BLUE "\n1. Recent Warning Events:"
    kubectl get events --all-namespaces --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail -10

    print_color $BLUE "\n2. Recent Normal Events:"
    kubectl get events --all-namespaces --field-selector type=Normal --sort-by=.metadata.creationTimestamp | tail -10

    print_color $BLUE "\n3. Events by Reason:"
    kubectl get events --all-namespaces -o custom-columns=REASON:.reason,MESSAGE:.message,FIRST:.firstTimestamp,LAST:.lastTimestamp | sort | uniq -c | sort -nr | head -10

    print_color $BLUE "\n4. Failed Events:"
    kubectl get events --all-namespaces | grep -i "failed\|error\|unhealthy" | tail -10

    echo
    read -p "Press Enter to continue..."
}

# Service discovery test
service_discovery_test() {
    print_color $BLUE "\n=== Service Discovery Test ==="

    print_color $BLUE "\n1. All Services:"
    kubectl get services --all-namespaces

    print_color $CYAN "Enter namespace: "
    read -r namespace
    kubectl get services -n "$namespace"
    print_color $CYAN "Enter service name to test: "
    read -r service_name

    print_color $BLUE "\n2. Service Details:"
    kubectl describe service "$service_name" -n "$namespace"

    print_color $BLUE "\n3. Service Endpoints:"
    kubectl get endpoints "$service_name" -n "$namespace"

    print_color $BLUE "\n4. Testing Service Connectivity:"
    kubectl run service-test --image=curlimages/curl --rm -it --restart=Never -- curl -s "$service_name.$namespace.svc.cluster.local" 2>/dev/null || print_color $RED "Service connectivity test failed"

    echo
    read -p "Press Enter to continue..."
}

# DNS resolution test
dns_resolution_test() {
    print_color $BLUE "\n=== DNS Resolution Test ==="

    print_color $BLUE "\n1. CoreDNS Pods:"
    kubectl get pods -n kube-system -l k8s-app=kube-dns

    print_color $BLUE "\n2. CoreDNS ConfigMap:"
    kubectl get configmap coredns -n kube-system -o yaml | grep -A 20 Corefile || print_color $YELLOW "CoreDNS config not found"

    print_color $BLUE "\n3. Testing DNS Resolution:"
    kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>/dev/null || print_color $RED "DNS test failed"

    print_color $BLUE "\n4. DNS Service:"
    kubectl get service -n kube-system | grep dns

    echo
    read -p "Press Enter to continue..."
}

# Quick actions
quick_actions() {
    clear
    print_color $BLUE "=== Quick Actions ==="
    echo
    print_color $GREEN "1.  Show All Resources"
    print_color $GREEN "2.  Scale Deployment Up/Down"
    print_color $GREEN "3.  Restart Deployment"
    print_color $GREEN "4.  Get Pod Logs"
    print_color $GREEN "5.  Delete Failed Pods"
    print_color $GREEN "6.  Show Resource Usage"
    print_color $GREEN "7.  Port Forward Service"
    print_color $GREEN "8.  Copy Files to Pod"
    print_color $GREEN "9.  Execute Command in Pod"
    print_color $GREEN "10. Create Debug Pod"
    print_color $GREEN "11. Show Cluster Summary"
    print_color $GREEN "12. Emergency Pod Cleanup"
    print_color $RED "0.  Back to Main Menu"
    echo
    print_color $CYAN "Enter your choice: "
    read -r choice

    case $choice in
        1)
            print_color $CYAN "Enter namespace (or 'all' for all namespaces): "
            read -r namespace
            if [[ $namespace == "all" ]]; then
                kubectl get all --all-namespaces
            else
                kubectl get all -n "$namespace"
            fi
            ;;
        2)
            scale_deployment_interactive
            ;;
        3)
            restart_deployment_interactive
            ;;
        4)
            pod_logs_interactive
            ;;
        5)
            print_color $BLUE "\n=== Deleting Failed Pods ==="
            kubectl get pods --all-namespaces --field-selector=status.phase=Failed
            if confirm_action "delete all failed pods"; then
                kubectl delete pods --all-namespaces --field-selector=status.phase=Failed
                print_color $GREEN "Failed pods deleted"
                log "Deleted failed pods"
            fi
            ;;
        6)
            print_color $BLUE "\n=== Resource Usage ==="
            kubectl top nodes 2>/dev/null || print_color $YELLOW "Metrics server not available"
            echo
            kubectl top pods --all-namespaces 2>/dev/null | head -10 || print_color $YELLOW "Metrics server not available"
            ;;
        7)
            port_forward_interactive
            ;;
        8)
            copy_files_interactive
            ;;
        9)
            pod_exec_interactive
            ;;
        10)
            create_debug_pod
            ;;
        11)
            cluster_summary
            ;;
        12)
            emergency_cleanup
            ;;
        0) return ;;
        *) print_color $RED "Invalid choice" ;;
    esac
    echo
    read -p "Press Enter to continue..."
    quick_actions
}

# Create debug pod
create_debug_pod() {
    print_color $BLUE "\n=== Create Debug Pod ==="
    print_color $CYAN "Enter namespace: "
    read -r namespace
    print_color $CYAN "Enter debug pod name (default: debug-pod): "
    read -r debug_name
    debug_name=${debug_name:-debug-pod}

    kubectl run "$debug_name" --image=nicolaka/netshoot -n "$namespace" --rm -it --restart=Never

    log "Created debug pod: $debug_name"
    echo
    read -p "Press Enter to continue..."
}

# Cluster summary
cluster_summary() {
    print_color $BLUE "\n=== Cluster Summary ==="

    print_color $BLUE "\n📊 Cluster Overview:"
    kubectl get nodes --no-headers | wc -l | xargs printf "Nodes: %s\n"
    kubectl get namespaces --no-headers | wc -l | xargs printf "Namespaces: %s\n"
    kubectl get pods --all-namespaces --no-headers | wc -l | xargs printf "Total Pods: %s\n"
    kubectl get deployments --all-namespaces --no-headers | wc -l | xargs printf "Deployments: %s\n"
    kubectl get services --all-namespaces --no-headers | wc -l | xargs printf "Services: %s\n"

    print_color $BLUE "\n🔧 Node Status:"
    kubectl get nodes --no-headers | awk '{print $2}' | sort | uniq -c

    print_color $BLUE "\n📦 Pod Status:"
    kubectl get pods --all-namespaces --no-headers | awk '{print $4}' | sort | uniq -c

    print_color $BLUE "\n⚠️  Recent Issues:"
    kubectl get events --all-namespaces --field-selector type=Warning --no-headers | tail -5 | awk '{print $6 ": " $7 " " $8 " " $9 " " $10}'

    print_color $BLUE "\n💾 Storage:"
    kubectl get pv --no-headers | wc -l | xargs printf "Persistent Volumes: %s\n"
    kubectl get pvc --all-namespaces --no-headers | wc -l | xargs printf "Persistent Volume Claims: %s\n"

    echo
    read -p "Press Enter to continue..."
}

# Emergency cleanup
emergency_cleanup() {
    print_color $RED "\n=== Emergency Pod Cleanup ==="
    print_color $YELLOW "This will delete pods in problematic states"

    print_color $BLUE "\n1. Failed Pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Failed

    print_color $BLUE "\n2. Pods in Unknown State:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Unknown

    print_color $BLUE "\n3. Pending Pods (older than 10 minutes):"
    kubectl get pods --all-namespaces --field-selector=status.phase=Pending -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp | awk 'NR>1 {print $0}'

    if confirm_action "perform emergency cleanup"; then
        print_color $BLUE "\nCleaning up failed pods..."
        kubectl delete pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null || true

        print_color $BLUE "Cleaning up unknown state pods..."
        kubectl delete pods --all-namespaces --field-selector=status.phase=Unknown 2>/dev/null || true

        print_color $GREEN "Emergency cleanup completed"
        log "Performed emergency cleanup"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Main script execution
main() {
    # Check prerequisites
    check_prerequisites

    # Initialize log file
    touch "$LOG_FILE"
    log "K3s Management Script started"

    # Main loop
    while true; do
        show_main_menu
        read -r choice

        case $choice in
            1) cluster_overview ;;
            2) node_management ;;
            3) namespace_operations ;;
            4) deployment_management ;;
            5) service_management ;;
            6) pod_operations ;;
            7) storage_management ;;
            8) monitoring_logs ;;
            9) security_operations ;;
            10) backup_restore ;;
            11) troubleshooting_tools ;;
            12) quick_actions ;;
            0)
                print_color $GREEN "Thank you for using K3s Management Script!"
                log "K3s Management Script ended"
                exit 0
                ;;
            *)
                print_color $RED "Invalid choice. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Run the main function
main "$@"