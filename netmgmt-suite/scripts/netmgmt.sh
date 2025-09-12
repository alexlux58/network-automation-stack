#!/usr/bin/env bash
# Network Management Suite Control Script
# Provides easy bootstrap, start, stop, and management of the entire suite

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="netmgmt-suite"
DEPLOYMENT_IP="192.168.5.9"
OBSERVABILITY_IP="192.168.5.13"
REQUIRED_PORTS=(8080 8081)

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Determine the correct working directory for docker-compose operations
get_work_dir() {
    if [ -f "docker-compose.yml" ]; then
        echo "."
    elif [ -f "../docker-compose.yml" ]; then
        echo ".."
    else
        echo ""
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check available resources
    local total_mem=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    if [ "$total_mem" -lt 4000000000 ]; then  # 4GB in bytes
        log_warning "Less than 4GB RAM available. Performance may be affected."
    fi
    
    log_success "Prerequisites check passed"
}

check_observability_stack() {
    log_info "Checking observability stack connectivity..."
    
    local services=(
        "Elasticsearch:9200"
        "Prometheus:9090"
        "Grafana:3000"
    )
    
    local all_healthy=true
    
    for service in "${services[@]}"; do
        local name=$(echo "$service" | cut -d: -f1)
        local port=$(echo "$service" | cut -d: -f2)
        
        if curl -s --connect-timeout 5 "http://$OBSERVABILITY_IP:$port" &> /dev/null; then
            log_success "$name is accessible"
        else
            log_warning "$name is not accessible at $OBSERVABILITY_IP:$port"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = false ]; then
        log_warning "Some observability services are not accessible. Logging and monitoring may not work properly."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_port_availability() {
    log_info "Checking port availability..."
    
    local occupied_ports=()
    
    for port in "${REQUIRED_PORTS[@]}"; do
        if lsof -i ":$port" &> /dev/null; then
            occupied_ports+=("$port")
        fi
    done
    
    if [ ${#occupied_ports[@]} -gt 0 ]; then
        log_error "The following ports are already in use: ${occupied_ports[*]}"
        log_info "Please stop the services using these ports or modify the docker-compose.yml file"
        exit 1
    fi
    
    log_success "All required ports are available"
}

bootstrap_project() {
    log_info "Bootstrapping network management suite..."
    
    # Determine the correct directory to create the project
    local target_dir
    if [ -f "bootstrap_netmgmt_suite.sh" ]; then
        # We're in the parent directory, create netmgmt-suite here
        target_dir="netmgmt-suite"
    elif [ -f "../bootstrap_netmgmt_suite.sh" ]; then
        # We're in netmgmt-suite, go up and create netmgmt-suite
        target_dir="../netmgmt-suite"
    elif [ -f "../../bootstrap_netmgmt_suite.sh" ]; then
        # We're in scripts, go up two levels and create netmgmt-suite
        target_dir="../../netmgmt-suite"
    else
        log_error "bootstrap_netmgmt_suite.sh not found in current, parent, or grandparent directory"
        log_info "Please run this script from the netmgmt-suite directory or its scripts subdirectory"
        exit 1
    fi
    
    if [ -d "$target_dir" ]; then
        log_warning "Project directory already exists"
        read -p "Remove existing project and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing project..."
            # Preserve the wrapper script if it exists
            local wrapper_script=""
            if [ -f "$target_dir/scripts/netmgmt.sh" ]; then
                wrapper_script=$(cat "$target_dir/scripts/netmgmt.sh")
                log_info "Preserving wrapper script..."
            fi
            
            # Change to parent directory before removing to avoid issues
            if [ "$target_dir" = "netmgmt-suite" ]; then
                # We're in the parent directory, safe to remove
                rm -rf "$target_dir"
            elif [ "$target_dir" = "../netmgmt-suite" ]; then
                # We're in netmgmt-suite, go up and remove
                cd .. && rm -rf netmgmt-suite
            elif [ "$target_dir" = "../../netmgmt-suite" ]; then
                # We're in scripts, go up two levels and remove
                cd ../.. && rm -rf netmgmt-suite
            fi
        else
            log_info "Using existing project directory"
            return 0
        fi
    fi
    
    # Run the bootstrap script
    if [ -f "bootstrap_netmgmt_suite.sh" ]; then
        bash bootstrap_netmgmt_suite.sh
        log_success "Project bootstrapped successfully"
        
        # Restore the wrapper script if it was preserved
        if [ -n "$wrapper_script" ] && [ -d "$target_dir/scripts" ]; then
            log_info "Restoring wrapper script..."
            echo "$wrapper_script" > "$target_dir/scripts/netmgmt.sh"
            chmod +x "$target_dir/scripts/netmgmt.sh"
        fi
    elif [ -f "../bootstrap_netmgmt_suite.sh" ]; then
        bash ../bootstrap_netmgmt_suite.sh
        log_success "Project bootstrapped successfully"
        
        # Restore the wrapper script if it was preserved
        if [ -n "$wrapper_script" ] && [ -d "$target_dir/scripts" ]; then
            log_info "Restoring wrapper script..."
            echo "$wrapper_script" > "$target_dir/scripts/netmgmt.sh"
            chmod +x "$target_dir/scripts/netmgmt.sh"
        fi
    elif [ -f "../../bootstrap_netmgmt_suite.sh" ]; then
        bash ../../bootstrap_netmgmt_suite.sh
        log_success "Project bootstrapped successfully"
        
        # Restore the wrapper script if it was preserved
        if [ -n "$wrapper_script" ] && [ -d "$target_dir/scripts" ]; then
            log_info "Restoring wrapper script..."
            echo "$wrapper_script" > "$target_dir/scripts/netmgmt.sh"
            chmod +x "$target_dir/scripts/netmgmt.sh"
        fi
    else
        log_error "bootstrap_netmgmt_suite.sh not found in current, parent, or grandparent directory"
        log_info "Please run this script from the netmgmt-suite directory or its scripts subdirectory"
        exit 1
    fi
}

generate_secrets() {
    log_info "Generating secure secrets..."
    
    if [ -f "scripts/gen_secrets.py" ]; then
        python3 scripts/gen_secrets.py .env
        log_success "Secrets generated successfully"
    else
        log_warning "Secret generation script not found, using default secrets"
    fi
}

start_services() {
    log_info "Starting network management suite services..."
    
    local work_dir=$(get_work_dir)
    if [ -z "$work_dir" ]; then
        log_error "Cannot find docker-compose.yml file"
        exit 1
    fi
    
    # Check if services are already running
    if (cd "$work_dir" && docker compose ps --services | grep -q .); then
        log_warning "Some services are already running"
        read -p "Restart all services? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Stopping existing services..."
            (cd "$work_dir" && docker compose down)
        else
            log_info "Starting additional services..."
        fi
    fi
    
    # Start services
    log_info "Building and starting services (this may take several minutes)..."
    (cd "$work_dir" && docker compose up -d --build)
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local unhealthy_services=$(cd "$work_dir" && docker compose ps --services | while read service; do
            if ! (cd "$work_dir" && docker compose ps "$service") | grep -q "healthy\|Up"; then
                echo "$service"
            fi
        done)
        
        if [ -z "$unhealthy_services" ]; then
            break
        fi
        
        log_info "Waiting for services to be healthy... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_warning "Some services may not be fully healthy yet"
    fi
    
    log_success "Services started successfully"
}

create_superusers() {
    log_info "Creating superusers..."
    
    local work_dir=$(get_work_dir)
    if [ -z "$work_dir" ]; then
        log_error "Cannot find docker-compose.yml file"
        exit 1
    fi
    
    if [ -f "$work_dir/scripts/bootstrap.sh" ]; then
        (cd "$work_dir" && bash scripts/bootstrap.sh)
        log_success "Superusers created successfully"
    else
        log_warning "Bootstrap script not found, superusers may need to be created manually"
    fi
}

show_status() {
    log_info "Network Management Suite Status"
    echo "=================================="
    
    local work_dir=$(get_work_dir)
    if [ -z "$work_dir" ]; then
        log_error "Cannot find docker-compose.yml file"
        exit 1
    fi
    
    # Show service status
    (cd "$work_dir" && docker compose ps)
    
    echo
    log_info "Service URLs (Local Access):"
    echo "NetBox:    http://localhost:8080/"
    echo "Nautobot:  http://localhost:8081/"
    
    echo
    log_info "Service URLs (LAN Access):"
    echo "NetBox:    http://$DEPLOYMENT_IP:8080/"
    echo "Nautobot:  http://$DEPLOYMENT_IP:8081/"
    
    echo
    # Observability stack intentionally omitted in minimal deployment
}

stop_services() {
    log_info "Stopping network management suite services..."
    
    local work_dir=$(get_work_dir)
    if [ -z "$work_dir" ]; then
        log_error "Cannot find docker-compose.yml file"
        exit 1
    fi
    
    if ! (cd "$work_dir" && docker compose ps --services | grep -q .); then
        log_warning "No services are currently running"
        return 0
    fi
    
    (cd "$work_dir" && docker compose down)
    log_success "Services stopped successfully"
}

destroy_project() {
    log_warning "This will permanently delete all data and volumes!"
    read -p "Are you sure you want to destroy the project? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destroying project..."
        
        docker compose down -v
        cd ..
        rm -rf netmgmt-suite
        log_success "Project destroyed successfully"
    else
        log_info "Destruction cancelled"
    fi
}

show_logs() {
    log_info "Showing logs (press Ctrl+C to exit)..."
    
    local work_dir=$(get_work_dir)
    if [ -z "$work_dir" ]; then
        log_error "Cannot find docker-compose.yml file"
        exit 1
    fi
    
    (cd "$work_dir" && docker compose logs -f --tail=100)
}

backup_data() {
    log_info "Creating backup..."
    
    local backup_dir="../backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup databases
    log_info "Backing up databases..."
    docker compose exec -T postgres-netbox pg_dump -U netbox netbox > "$backup_dir/netbox_backup.sql"
    docker compose exec -T postgres-nautobot pg_dump -U nautobot nautobot > "$backup_dir/nautobot_backup.sql"
    
    # Backup volumes
    log_info "Backing up volumes..."
    docker run --rm -v "$(pwd)_pgdata-netbox:/data" -v "$(pwd)/$backup_dir:/backup" alpine tar czf /backup/netbox_data.tar.gz -C /data .
    docker run --rm -v "$(pwd)_pgdata-nautobot:/data" -v "$(pwd)/$backup_dir:/backup" alpine tar czf /backup/nautobot_data.tar.gz -C /data .
    
    log_success "Backup created in $backup_dir"
}

show_help() {
    cat << EOF
Network Management Suite Control Script

USAGE:
    $0 COMMAND [OPTIONS]

COMMANDS:
    bootstrap       Bootstrap the project (create all files and directories)
    start           Start all services
    stop            Stop all services
    restart         Restart all services
    status          Show service status and URLs
    logs            Show live logs from all services
    backup          Create backup of databases and volumes
    destroy         Destroy project and all data (DESTRUCTIVE!)
    help            Show this help message

EXAMPLES:
    $0 bootstrap    # First time setup
    $0 start        # Start all services
    $0 status       # Check service status
    $0 logs         # View live logs
    $0 stop         # Stop all services

WORKFLOW:
    1. $0 bootstrap  # Initial setup
    2. $0 start      # Start services
    3. $0 status     # Verify everything is running
    4. Access services via URLs shown in status

EOF
}

# Main script logic
main() {
    case "${1:-help}" in
        bootstrap)
            check_prerequisites
            check_observability_stack
            check_port_availability
            bootstrap_project
            generate_secrets
            log_success "Bootstrap completed! Run '$0 start' to start services."
            ;;
        start)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found. Run '$0 bootstrap' first."
                exit 1
            fi
            check_prerequisites
            start_services
            create_superusers
            show_status
            ;;
        stop)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found."
                exit 1
            fi
            stop_services
            ;;
        restart)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found. Run '$0 bootstrap' first."
                exit 1
            fi
            stop_services
            sleep 5
            start_services
            show_status
            ;;
        status)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found. Run '$0 bootstrap' first."
                exit 1
            fi
            show_status
            ;;
        logs)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found. Run '$0 bootstrap' first."
                exit 1
            fi
            show_logs
            ;;
        backup)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found. Run '$0 bootstrap' first."
                exit 1
            fi
            backup_data
            ;;
        destroy)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found."
                exit 1
            fi
            destroy_project
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
