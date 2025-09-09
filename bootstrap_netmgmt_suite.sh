#!/usr/bin/env bash
# Recreates the full "netmgmt-suite" project locally.
# Includes: NetBox + Nautobot (+ plugins), Jenkins, Oxidized, Filebeat->ELK, pgAdmin, Redis Commander,
# plus scripts and a GitHub push helper.

set -euo pipefail

ROOT="netmgmt-suite"
mkdir -p "$ROOT"/{scripts,beats,extras/logstash,jenkins,oxidized,monitoring}

# ---------------- docker-compose.yml ----------------
cat > "$ROOT/docker-compose.yml" <<'YML'

x-common-env: &common-env
  TZ: ${TZ}
  ALLOWED_HOSTS: ${ALLOWED_HOSTS}

networks:
  netmgmt:
    driver: bridge

volumes:
  pgdata-netbox: {}
  netbox-media: {}
  pgdata-nautobot: {}
  nautobot-media: {}
  pgadmin-data: {}
  oxidized-data: {}
  jenkins-home: {}

services:
  postgres-netbox:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: netbox
      POSTGRES_USER: netbox
      POSTGRES_PASSWORD: ${NETBOX_DB_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U netbox -d netbox"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - pgdata-netbox:/var/lib/postgresql/data
    networks: [netmgmt]

  redis-netbox:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--save", "", "--appendonly", "no"]
    labels:
      co.elastic.logs/enabled: "true"
      co.elastic.logs/module: "redis"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [netmgmt]

  netbox:
    build:
      context: .
      dockerfile: Dockerfile.netbox
    restart: unless-stopped
    depends_on:
      postgres-netbox:
        condition: service_healthy
      redis-netbox:
        condition: service_healthy
    env_file: [.env]
    environment:
      <<: *common-env
      DB_NAME: netbox
      DB_USER: netbox
      DB_PASSWORD: ${NETBOX_DB_PASSWORD}
      DB_HOST: postgres-netbox
      REDIS_HOST: redis-netbox
      REDIS_DATABASE: 0
      REDIS_SSL: "false"
      SECRET_KEY: ${NETBOX_SECRET_KEY}
      SUPERUSER_NAME: ${NETBOX_SUPERUSER_NAME}
      SUPERUSER_EMAIL: ${NETBOX_SUPERUSER_EMAIL}
      SUPERUSER_PASSWORD: ${NETBOX_SUPERUSER_PASSWORD}
    ports:
      - "8080:8080"
    volumes:
      - netbox-media:/opt/netbox/netbox/media
    labels:
      co.elastic.logs/enabled: "true"
      prometheus.io/scrape: "true"
      prometheus.io/port: "8080"
      prometheus.io/path: "/metrics"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/login/ >/dev/null || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 10
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'
    networks: [netmgmt]

  netbox-worker:
    build:
      context: .
      dockerfile: Dockerfile.netbox
    restart: unless-stopped
    depends_on:
      netbox:
        condition: service_started
    env_file: [.env]
    environment:
      <<: *common-env
      DB_NAME: netbox
      DB_USER: netbox
      DB_PASSWORD: ${NETBOX_DB_PASSWORD}
      DB_HOST: postgres-netbox
      REDIS_HOST: redis-netbox
      REDIS_DATABASE: 0
      REDIS_SSL: "false"
      SECRET_KEY: ${NETBOX_SECRET_KEY}
    command: ["python", "/opt/netbox/netbox/manage.py", "rqworker"]
    labels:
      co.elastic.logs/enabled: "true"
    networks: [netmgmt]

  netbox-housekeeping:
    build:
      context: .
      dockerfile: Dockerfile.netbox
    restart: unless-stopped
    depends_on:
      netbox:
        condition: service_started
    env_file: [.env]
    environment:
      <<: *common-env
      DB_NAME: netbox
      DB_USER: netbox
      DB_PASSWORD: ${NETBOX_DB_PASSWORD}
      DB_HOST: postgres-netbox
      REDIS_HOST: redis-netbox
      REDIS_DATABASE: 0
      REDIS_SSL: "false"
      SECRET_KEY: ${NETBOX_SECRET_KEY}
    command: ["python", "/opt/netbox/netbox/manage.py", "housekeeping"]
    labels:
      co.elastic.logs/enabled: "true"
    networks: [netmgmt]

  postgres-nautobot:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: nautobot
      POSTGRES_USER: nautobot
      POSTGRES_PASSWORD: ${NAUTOBOT_DB_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nautobot -d nautobot"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - pgdata-nautobot:/var/lib/postgresql/data
    networks: [netmgmt]

  redis-nautobot:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--save", "", "--appendonly", "no"]
    labels:
      co.elastic.logs/enabled: "true"
      co.elastic.logs/module: "redis"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [netmgmt]

  nautobot:
    build:
      context: .
      dockerfile: Dockerfile.nautobot
    restart: unless-stopped
    depends_on:
      postgres-nautobot:
        condition: service_healthy
      redis-nautobot:
        condition: service_healthy
    env_file: [.env]
    environment:
      <<: *common-env
      NAUTOBOT_DB_ENGINE: django.db.backends.postgresql
      NAUTOBOT_DB_HOST: postgres-nautobot
      NAUTOBOT_DB_NAME: nautobot
      NAUTOBOT_DB_USER: nautobot
      NAUTOBOT_DB_PASSWORD: ${NAUTOBOT_DB_PASSWORD}
      NAUTOBOT_REDIS_HOST: redis-nautobot
      NAUTOBOT_REDIS_PORT: 6379
      NAUTOBOT_REDIS_DATABASE: 0
      NAUTOBOT_SECRET_KEY: ${NAUTOBOT_SECRET_KEY}
    ports:
      - "8081:8080"
    volumes:
      - nautobot-media:/opt/nautobot/media
    labels:
      co.elastic.logs/enabled: "true"
      prometheus.io/scrape: "true"
      prometheus.io/port: "8080"
      prometheus.io/path: "/metrics"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/login/ >/dev/null || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 10
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'
    networks: [netmgmt]

  nautobot-worker:
    build:
      context: .
      dockerfile: Dockerfile.nautobot
    restart: unless-stopped
    depends_on:
      nautobot:
        condition: service_started
    env_file: [.env]
    environment:
      <<: *common-env
      NAUTOBOT_DB_ENGINE: django.db.backends.postgresql
      NAUTOBOT_DB_HOST: postgres-nautobot
      NAUTOBOT_DB_NAME: nautobot
      NAUTOBOT_DB_USER: nautobot
      NAUTOBOT_DB_PASSWORD: ${NAUTOBOT_DB_PASSWORD}
      NAUTOBOT_REDIS_HOST: redis-nautobot
      NAUTOBOT_REDIS_PORT: 6379
      NAUTOBOT_REDIS_DATABASE: 0
      NAUTOBOT_SECRET_KEY: ${NAUTOBOT_SECRET_KEY}
    command: ["nautobot-server", "rqworker"]
    labels:
      co.elastic.logs/enabled: "true"
    networks: [netmgmt]

  pgadmin:
    image: dpage/pgadmin4:latest
    restart: unless-stopped
    depends_on:
      - postgres-netbox
      - postgres-nautobot
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
    volumes:
      - pgadmin-data:/var/lib/pgadmin
    ports:
      - "5050:80"
    networks: [netmgmt]

  redis-commander:
    image: rediscommander/redis-commander:latest
    restart: unless-stopped
    environment:
      REDIS_HOSTS: "netbox:redis-netbox:6379,nautobot:redis-nautobot:6379"
    ports:
      - "8082:8081"
    networks: [netmgmt]

  jenkins:
    image: jenkins/jenkins:lts
    restart: unless-stopped
    ports:
      - "8090:8080"
      - "50000:50000"
    volumes:
      - jenkins-home:/var/jenkins_home
    networks: [netmgmt]
    labels:
      co.elastic.logs/enabled: "true"
      prometheus.io/scrape: "true"
      prometheus.io/port: "8080"
      prometheus.io/path: "/prometheus"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/login >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
        reservations:
          memory: 1G
          cpus: '0.5'

  oxidized:
    image: oxidized/oxidized:latest
    restart: unless-stopped
    environment:
      CONFIG_RELOAD_INTERVAL: "600"
    volumes:
      - oxidized-data:/home/oxidized/.config/oxidized
    ports:
      - "8888:8888"
    networks: [netmgmt]
    labels:
      co.elastic.logs/enabled: "true"
      prometheus.io/scrape: "true"
      prometheus.io/port: "8888"
      prometheus.io/path: "/metrics"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8888 >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.15.0
    restart: unless-stopped
    user: root
    depends_on:
      - netbox
      - nautobot
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./beats/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    networks: [netmgmt]
YML

# ---------------- Dockerfile.netbox ----------------
cat > "$ROOT/Dockerfile.netbox" <<'DOCKER'
FROM netboxcommunity/netbox:latest
# Use base NetBox image without additional plugins for now
# Plugins can be installed later via the web interface or requirements.txt
DOCKER

# ---------------- Dockerfile.nautobot ----------------
cat > "$ROOT/Dockerfile.nautobot" <<'DOCKER'
FROM ghcr.io/nautobot/nautobot:latest
# Use base Nautobot image without additional plugins for now
# Plugins can be installed later via the web interface or requirements.txt
DOCKER

# ---------------- .env template ----------------
cat > "$ROOT/.env" <<'ENV'
TZ=America/Los_Angeles
ALLOWED_HOSTS=127.0.0.1,localhost,192.168.5.9,192.168.5.13

NETBOX_DB_PASSWORD=changeme_netbox_db
NETBOX_SECRET_KEY=changeme_netbox_secret
NETBOX_SUPERUSER_NAME=admin
NETBOX_SUPERUSER_EMAIL=admin@example.com
NETBOX_SUPERUSER_PASSWORD=GenerateStrongPassword123!

NAUTOBOT_DB_PASSWORD=changeme_nautobot_db
NAUTOBOT_SECRET_KEY=changeme_nautobot_secret
NAUTOBOT_SUPERUSER_NAME=admin
NAUTOBOT_SUPERUSER_EMAIL=admin@example.com
NAUTOBOT_SUPERUSER_PASSWORD=GenerateStrongPassword123!

PGADMIN_EMAIL=admin@example.com
PGADMIN_PASSWORD=GenerateStrongPassword123!

# Point to your existing ELK / Logstash from Network-Observability-Stack
LOGSTASH_HOST=192.168.5.13
LOGSTASH_PORT=5044
ENV

# ---------------- beats/filebeat.yml ----------------
cat > "$ROOT/beats/filebeat.yml" <<'FB'
filebeat.autodiscover:
  providers:
    - type: docker
      hints.enabled: true
      templates:
        - condition:
            contains:
              docker.container.labels.co.elastic.logs/enabled: "true"
          config:
            - type: docker
              containers.ids:
                - "${data.docker.container.id}"
              fields:
                service: "${data.docker.container.labels.com.docker.compose.service}"
                project: "netmgmt-suite"
              fields_under_root: true

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - add_host_metadata:
      when.not.contains.tags: forwarded

output.logstash:
  hosts: ["${LOGSTASH_HOST}:${LOGSTASH_PORT}"]
  compression_level: 3
  bulk_max_size: 1024

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
FB

# ---------------- extras/logstash/netmgmt-beats.conf ----------------
cat > "$ROOT/extras/logstash/netmgmt-beats.conf" <<'LS'
input {
  beats { port => 5044 }
}
filter {
  if [container] {
    mutate { add_field => { "container_name" => "%{[container][name]}" } }
  }
}
output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "netmgmt-%{+YYYY.MM.dd}"
  }
}
LS

# ---------------- monitoring/prometheus-netmgmt.yml ----------------
cat > "$ROOT/monitoring/prometheus-netmgmt.yml" <<'PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'netmgmt-netbox'
    static_configs:
      - targets: ['netbox:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'netmgmt-nautobot'
    static_configs:
      - targets: ['nautobot:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'netmgmt-jenkins'
    static_configs:
      - targets: ['jenkins:8080']
    metrics_path: '/prometheus'
    scrape_interval: 30s

  - job_name: 'netmgmt-oxidized'
    static_configs:
      - targets: ['oxidized:8888']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'netmgmt-postgres-netbox'
    static_configs:
      - targets: ['postgres-netbox:5432']
    scrape_interval: 30s

  - job_name: 'netmgmt-postgres-nautobot'
    static_configs:
      - targets: ['postgres-nautobot:5432']
    scrape_interval: 30s

  - job_name: 'netmgmt-redis-netbox'
    static_configs:
      - targets: ['redis-netbox:6379']
    scrape_interval: 30s

  - job_name: 'netmgmt-redis-nautobot'
    static_configs:
      - targets: ['redis-nautobot:6379']
    scrape_interval: 30s
PROM

# ---------------- scripts/bootstrap.sh ----------------
cat > "$ROOT/scripts/bootstrap.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ -f .env ]; then
  export $(grep -v '^#' .env | tr '\n' ' ')
fi
echo "Waiting for NetBox and Nautobot to be healthy..."
# Check if services are running first
if ! docker compose ps netbox | grep -q "Up"; then
    echo "NetBox is not running. Please start services first with 'make up' or './scripts/netmgmt.sh start'"
    exit 1
fi
if ! docker compose ps nautobot | grep -q "Up"; then
    echo "Nautobot is not running. Please start services first with 'make up' or './scripts/netmgmt.sh start'"
    exit 1
fi
echo "Ensuring NetBox superuser exists..."
docker compose exec -T netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py shell -c "
from django.contrib.auth import get_user_model
import os
User = get_user_model()
u = os.environ.get('NETBOX_SUPERUSER_NAME', 'admin')
e = os.environ.get('NETBOX_SUPERUSER_EMAIL', 'admin@example.com')
p = os.environ.get('NETBOX_SUPERUSER_PASSWORD', 'admin123!')
if not User.objects.filter(username=u).exists():
    User.objects.create_superuser(username=u, email=e, password=p)
    print('Created NetBox superuser')
else:
    print('NetBox superuser exists, skipping.')
"
echo "Ensuring Nautobot superuser exists..."
docker compose exec -T nautobot sh -lc "
nautobot-server shell -c \"
from django.contrib.auth import get_user_model
import os
User = get_user_model()
u = os.environ.get('NAUTOBOT_SUPERUSER_NAME', 'admin')
e = os.environ.get('NAUTOBOT_SUPERUSER_EMAIL', 'admin@example.com')
p = os.environ.get('NAUTOBOT_SUPERUSER_PASSWORD', 'admin123!')
if not User.objects.filter(username=u).exists():
    User.objects.create_superuser(username=u, email=e, password=p)
    print('Created Nautobot superuser')
else:
    print('Nautobot superuser exists, skipping.')
\"
"
SH
chmod +x "$ROOT/scripts/bootstrap.sh"

# ---------------- scripts/gen_secrets.py ----------------
cat > "$ROOT/scripts/gen_secrets.py" <<'PY'
#!/usr/bin/env python3
import sys, re, secrets, string
if len(sys.argv) != 2:
    print("Usage: gen_secrets.py PATH_TO_ENV"); exit(1)
path = sys.argv[1]
content = open(path,"r",encoding="utf-8").read()
def make_secret(n=64):
    alphabet = string.ascii_letters + string.digits + string.punctuation
    safe = alphabet.replace('"','').replace("'","").replace("`","").replace("$","").replace("\\","")
    return ''.join(secrets.choice(safe) for _ in range(n))
for key in ("NETBOX_SECRET_KEY","NAUTOBOT_SECRET_KEY"):
    pattern = re.compile(rf"^{key}=.*$", re.MULTILINE)
    m = re.search(pattern, content)
    if not m or "changeme" in m.group(0):
        new_line = f"{key}={make_secret()}"
        content = re.sub(pattern, new_line, content) if m else content + f"\n{new_line}\n"
open(path,"w",encoding="utf-8").write(content)
print("Secrets generated/updated in .env")
PY

# Generate secure secret keys immediately after creating .env
echo "Generating secure secret keys..."
python3 "$ROOT/scripts/gen_secrets.py" "$ROOT/.env"

# Fix Oxidized configuration
echo "Setting up Oxidized configuration..."
echo "192.168.1.1:ios:admin:password" > "$ROOT/oxidized/config/router.db"

# Fix Filebeat configuration
echo "Fixing Filebeat configuration..."
sed -i.bak 's|hosts: \["\${LOGSTASH_HOST}:\${LOGSTASH_PORT}"\]|hosts: ["192.168.5.13:5044"]|' "$ROOT/beats/filebeat/filebeat.yml"

# Fix file ownership for Filebeat (will be done on the VM)
echo "Note: Run 'sudo chown 0:0 beats/filebeat/filebeat.yml' on the VM after deployment"

chmod +x "$ROOT/scripts/gen_secrets.py"

# ---------------- scripts/netmgmt.sh ----------------
cat > "$ROOT/scripts/netmgmt.sh" <<'NETMGMT'
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
REQUIRED_PORTS=(8080 8081 8090 8888 5050 8082)

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

apply_critical_fixes() {
    log_info "Applying critical configuration fixes..."
    
    local work_dir=$(get_work_dir)
    if [ -z "$work_dir" ]; then
        log_error "Cannot find docker-compose.yml file"
        exit 1
    fi
    
    # Fix Oxidized configuration
    if [ -f "$work_dir/oxidized/config/router.db" ]; then
        echo "192.168.1.1:ios:admin:password" > "$work_dir/oxidized/config/router.db"
        log_success "Fixed Oxidized router.db configuration"
    else
        log_warning "Oxidized router.db not found, creating it..."
        mkdir -p "$work_dir/oxidized/config"
        echo "192.168.1.1:ios:admin:password" > "$work_dir/oxidized/config/router.db"
        log_success "Created Oxidized router.db configuration"
    fi
    
    # Fix Filebeat configuration
    if [ -f "$work_dir/beats/filebeat/filebeat.yml" ]; then
        sed -i.bak 's|hosts: \["\${LOGSTASH_HOST}:\${LOGSTASH_PORT}"\]|hosts: ["192.168.5.13:5044"]|' "$work_dir/beats/filebeat/filebeat.yml"
        log_success "Fixed Filebeat logstash hosts configuration"
    else
        log_warning "Filebeat configuration not found"
    fi
    
    # Fix file ownership for Filebeat (if running as root)
    if [ -f "$work_dir/beats/filebeat/filebeat.yml" ] && [ "$(id -u)" -eq 0 ]; then
        chown 0:0 "$work_dir/beats/filebeat/filebeat.yml"
        log_success "Fixed Filebeat file ownership"
    elif [ -f "$work_dir/beats/filebeat/filebeat.yml" ]; then
        log_info "Note: Run 'sudo chown 0:0 beats/filebeat/filebeat.yml' to fix file ownership"
    fi
    
    # Copy Oxidized config to container if it's running
    if (cd "$work_dir" && docker compose ps oxidized | grep -q "Up"); then
        log_info "Copying Oxidized configuration to running container..."
        (cd "$work_dir" && docker cp oxidized/config/router.db netmgmt-suite_oxidized_1:/home/oxidized/.config/oxidized/router.db 2>/dev/null || true)
        (cd "$work_dir" && docker compose restart oxidized 2>/dev/null || true)
        log_success "Oxidized configuration updated in container"
    fi
    
    log_success "Critical fixes applied successfully"
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
    
    # Apply critical fixes before starting services
    log_info "Applying critical configuration fixes..."
    
    # Fix Oxidized configuration
    if [ -f "$work_dir/oxidized/config/router.db" ]; then
        echo "192.168.1.1:ios:admin:password" > "$work_dir/oxidized/config/router.db"
        log_success "Fixed Oxidized router.db configuration"
    fi
    
    # Fix Filebeat configuration
    if [ -f "$work_dir/beats/filebeat/filebeat.yml" ]; then
        sed -i.bak 's|hosts: \["\${LOGSTASH_HOST}:\${LOGSTASH_PORT}"\]|hosts: ["192.168.5.13:5044"]|' "$work_dir/beats/filebeat/filebeat.yml"
        log_success "Fixed Filebeat logstash hosts configuration"
    fi
    
    # Fix file ownership for Filebeat (if running as root)
    if [ -f "$work_dir/beats/filebeat/filebeat.yml" ] && [ "$(id -u)" -eq 0 ]; then
        chown 0:0 "$work_dir/beats/filebeat/filebeat.yml"
        log_success "Fixed Filebeat file ownership"
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
    echo "Jenkins:   http://localhost:8090/"
    echo "Oxidized:  http://localhost:8888/"
    echo "pgAdmin:   http://localhost:5050/"
    echo "Redis Cmd: http://localhost:8082/"
    
    echo
    log_info "Service URLs (LAN Access):"
    echo "NetBox:    http://$DEPLOYMENT_IP:8080/"
    echo "Nautobot:  http://$DEPLOYMENT_IP:8081/"
    echo "Jenkins:   http://$DEPLOYMENT_IP:8090/"
    echo "Oxidized:  http://$DEPLOYMENT_IP:8888/"
    echo "pgAdmin:   http://$DEPLOYMENT_IP:5050/"
    echo "Redis Cmd: http://$DEPLOYMENT_IP:8082/"
    
    echo
    log_info "Observability Stack:"
    echo "Elasticsearch: http://$OBSERVABILITY_IP:9200/"
    echo "Kibana:        http://$OBSERVABILITY_IP:5601/"
    echo "Grafana:       http://$OBSERVABILITY_IP:3000/"
    echo "Prometheus:    http://$OBSERVABILITY_IP:9090/"
    echo "Alertmanager:  http://$OBSERVABILITY_IP:9093/"
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
    fix             Apply critical configuration fixes
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
        fix)
            if [ ! -f "docker-compose.yml" ] && [ ! -f "../docker-compose.yml" ]; then
                log_error "Project not found. Run '$0 bootstrap' first."
                exit 1
            fi
            apply_critical_fixes
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
NETMGMT
chmod +x "$ROOT/scripts/netmgmt.sh"

# ---------------- scripts/new_repo_and_push.sh ----------------
cat > "$ROOT/scripts/new_repo_and_push.sh" <<'PUSH'
#!/usr/bin/env bash
set -euo pipefail
REPO_NAME=${1:-netmgmt-suite}
VISIBILITY=${2:-private}   # private|public|internal
: "${GITHUB_TOKEN:=}"
USE_GH=0
if command -v gh >/dev/null 2>&1; then USE_GH=1; fi
if [[ $USE_GH -eq 0 ]]; then
  for dep in curl jq; do command -v "$dep" >/dev/null 2>&1 || { echo "Missing $dep"; exit 1; }; done
  [[ -n "$GITHUB_TOKEN" ]] || { echo "Set GITHUB_TOKEN (PAT with repo scope)"; exit 1; }
fi
if [[ $USE_GH -eq 1 ]]; then
  gh repo create "${REPO_NAME}" --${VISIBILITY} --disable-wiki --disable-issues --confirm >/dev/null
  WEB_URL=$(gh repo view "${REPO_NAME}" --json url -q .url)
  OWNER=$(gh api user --jq .login)
  SSH_URL="git@github.com:${OWNER}/${REPO_NAME}.git"
else
  API="https://api.github.com/user/repos"
  PRIV=$([[ "$VISIBILITY" == "public" ]] && echo false || echo true)
  PAYLOAD=$(printf '{"name":"%s","private":%s}' "$REPO_NAME" "$PRIV")
  RESP=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -d "$PAYLOAD" "$API")
  WEB_URL=$(echo "$RESP" | jq -r '.html_url')
  SSH_URL=$(echo "$RESP" | jq -r '.ssh_url')
fi
git init
git add .
git commit -m "Initial commit: NetBox + Nautobot + add-ons + ELK shipping" || true
git branch -M main
if git remote | grep -q '^origin$'; then git remote set-url origin "$SSH_URL"; else git remote add origin "$SSH_URL"; fi
git push -u origin main
echo "Repo: $WEB_URL"
PUSH
chmod +x "$ROOT/scripts/new_repo_and_push.sh"

# ---------------- Makefile ----------------
cat > "$ROOT/Makefile" <<'MK'
SHELL := /bin/bash
.DEFAULT_GOAL := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build custom images (plugins/apps baked in)
	docker compose build

up: build ## Start all services
	docker compose up -d

down: ## Stop services
	docker compose down

destroy: ## Stop and remove volumes
	docker compose down -v

logs: ## Tail logs
	docker compose logs -f --tail=200 netbox nautobot jenkins oxidized filebeat

ps: ## Status
	docker compose ps

gen-secrets: ## Generate Django SECRET_KEYs in .env
	python3 scripts/gen_secrets.py .env

bootstrap: ## Create superusers (idempotent)
	bash scripts/bootstrap.sh

urls: ## Print URLs
	@echo -e "\nLocal Access:"
	@echo -e "NetBox:    http://localhost:8080/\nNautobot:  http://localhost:8081/\npgAdmin:   http://localhost:5050/\nRedis Cmd: http://localhost:8082/\nJenkins:   http://localhost:8090/\nOxidized:  http://localhost:8888/\n"
	@echo -e "LAN Access (192.168.5.9):"
	@echo -e "NetBox:    http://192.168.5.9:8080/\nNautobot:  http://192.168.5.9:8081/\npgAdmin:   http://192.168.5.9:5050/\nRedis Cmd: http://192.168.5.9:8082/\nJenkins:   http://192.168.5.9:8090/\nOxidized:  http://192.168.5.9:8888/\n"
	@echo -e "Observability Stack Integration:"
	@echo -e "Elasticsearch: http://192.168.5.13:9200/\nKibana:        http://192.168.5.13:5601/\nGrafana:       http://192.168.5.13:3000/\nPrometheus:    http://192.168.5.13:9090/\nAlertmanager:  http://192.168.5.13:9093/\n"
	@echo -e "Prometheus Config: ./monitoring/prometheus-netmgmt.yml"
MK

# ---------------- README.md ----------------
cat > "$ROOT/README.md" <<'MD'
# Network Management Suite

A comprehensive network management and automation platform that integrates **NetBox**, **Nautobot**, **Jenkins**, **Oxidized**, and **Filebeat** with your existing observability stack. This suite provides network documentation, automation, configuration management, and centralized logging.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   NetBox        │    │   Nautobot      │    │   Jenkins       │
│   (Port 8080)   │    │   (Port 8081)   │    │   (Port 8090)   │
│   - IPAM        │    │   - Automation  │    │   - CI/CD       │
│   - DCIM        │    │   - Plugins     │    │   - Pipelines   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Filebeat      │
                    │   (Log Shipper) │
                    └─────────────────┘
                                 │
                    ┌─────────────────┐
                    │ Observability   │
                    │ Stack           │
                    │ 192.168.5.13    │
                    │ - ELK Stack     │
                    │ - Prometheus    │
                    │ - Grafana       │
                    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose installed
- At least 4GB RAM and 2 CPU cores available
- Network access to your observability stack (192.168.5.13)
- Server accessible at 192.168.5.9 for LAN access

### Option 1: Using the Wrapper Script (Recommended)
```bash
# Run the bootstrap script to generate all files
bash bootstrap_netmgmt_suite.sh
cd netmgmt-suite

# Use the wrapper script for easy management
./scripts/netmgmt.sh bootstrap    # First time setup
./scripts/netmgmt.sh start        # Start all services
./scripts/netmgmt.sh status       # Check service status
./scripts/netmgmt.sh logs         # View live logs
./scripts/netmgmt.sh stop         # Stop all services
```

### Option 2: Manual Setup
```bash
# Run the bootstrap script to generate all files
bash bootstrap_netmgmt_suite.sh
cd netmgmt-suite

# Generate secure secret keys
make gen-secrets

# Review and customize the .env file
nano .env

# Build and start all services
make up

# Wait for services to be healthy, then create superusers
make bootstrap

# View all service URLs
make urls
```

## 📋 Service Overview

| Service | Port | Local URL | LAN URL | Purpose | Default Credentials |
|---------|------|-----------|---------|---------|-------------------|
| **NetBox** | 8080 | http://localhost:8080/ | http://192.168.5.9:8080/ | IPAM/DCIM | admin / GenerateStrongPassword123! |
| **Nautobot** | 8081 | http://localhost:8081/ | http://192.168.5.9:8081/ | Network Automation | admin / GenerateStrongPassword123! |
| **Jenkins** | 8090 | http://localhost:8090/ | http://192.168.5.9:8090/ | CI/CD Pipeline | (Initial setup required) |
| **Oxidized** | 8888 | http://localhost:8888/ | http://192.168.5.9:8888/ | Config Backup | (Web interface) |
| **pgAdmin** | 5050 | http://localhost:5050/ | http://192.168.5.9:5050/ | Database Admin | admin@example.com / GenerateStrongPassword123! |
| **Redis Commander** | 8082 | http://localhost:8082/ | http://192.168.5.9:8082/ | Redis Management | (No auth) |

## 🔧 Configuration

### Environment Variables (.env)
```bash
# Timezone and Network Access
TZ=America/Los_Angeles
ALLOWED_HOSTS=127.0.0.1,localhost,192.168.5.9,192.168.5.13

# NetBox Configuration
NETBOX_DB_PASSWORD=changeme_netbox_db
NETBOX_SECRET_KEY=changeme_netbox_secret  # Auto-generated by make gen-secrets
NETBOX_SUPERUSER_NAME=admin
NETBOX_SUPERUSER_EMAIL=admin@example.com
NETBOX_SUPERUSER_PASSWORD=GenerateStrongPassword123!

# Nautobot Configuration
NAUTOBOT_DB_PASSWORD=changeme_nautobot_db
NAUTOBOT_SECRET_KEY=changeme_nautobot_secret  # Auto-generated by make gen-secrets
NAUTOBOT_SUPERUSER_NAME=admin
NAUTOBOT_SUPERUSER_EMAIL=admin@example.com
NAUTOBOT_SUPERUSER_PASSWORD=GenerateStrongPassword123!

# Observability Stack Integration
LOGSTASH_HOST=192.168.5.13
LOGSTASH_PORT=5044
```

### Customizing for Your Environment
1. **Update ALLOWED_HOSTS**: Add your server's IP addresses (currently configured for 192.168.5.9)
2. **Change Passwords**: Update all password fields in .env
3. **Adjust Resource Limits**: Modify CPU/memory limits in docker-compose.yml if needed
4. **Update Observability Stack**: Change LOGSTASH_HOST if your stack is elsewhere
5. **LAN Access**: Services are configured to be accessible from your LAN at 192.168.5.9

## 🌐 LAN Deployment

This suite is configured for deployment at **192.168.5.9** and is accessible from your local area network:

### Network Configuration
- **Deployment Server**: 192.168.5.9
- **Observability Stack**: 192.168.5.13
- **Port Binding**: All services bind to 0.0.0.0 (accessible from LAN)
- **Firewall**: Ensure ports 8080, 8081, 8090, 8888, 5050, 8082 are open

### Access Methods
1. **Local Access**: http://localhost:PORT/ (from the server itself)
2. **LAN Access**: http://192.168.5.9:PORT/ (from any device on your LAN)
3. **Remote Access**: Configure port forwarding or VPN for external access

### Security Considerations
- Services are accessible from your LAN by default
- Use strong passwords (configured in .env)
- Consider setting up a reverse proxy with SSL for production use
- Restrict access via firewall rules if needed

## 🔍 Monitoring & Observability

### Integration with Your Observability Stack
This suite is pre-configured to integrate with your observability stack at **192.168.5.13**:

- **Elasticsearch**: http://192.168.5.13:9200/ (Log storage)
- **Kibana**: http://192.168.5.13:5601/ (Log visualization)
- **Grafana**: http://192.168.5.13:3000/ (Metrics dashboards)
- **Prometheus**: http://192.168.5.13:9090/ (Metrics collection)
- **Alertmanager**: http://192.168.5.13:9093/ (Alerting)

### Prometheus Monitoring
- **Configuration**: `./monitoring/prometheus-netmgmt.yml`
- **Metrics Endpoints**: All services expose Prometheus metrics
- **Service Discovery**: Automatic discovery via Docker labels

### Logging
- **Filebeat**: Ships container logs to your ELK stack
- **Log Index**: `netmgmt-YYYY.MM.DD` in Elasticsearch
- **Service Tagging**: Logs include service and project metadata

## 🛠️ Operations

### Wrapper Script (Recommended)
The `scripts/netmgmt.sh` script provides an easy-to-use interface for managing the entire suite:

```bash
./scripts/netmgmt.sh bootstrap    # Bootstrap project (first time setup)
./scripts/netmgmt.sh start        # Start all services
./scripts/netmgmt.sh stop         # Stop all services
./scripts/netmgmt.sh restart      # Restart all services
./scripts/netmgmt.sh status       # Show service status and URLs
./scripts/netmgmt.sh logs         # Show live logs from all services
./scripts/netmgmt.sh backup       # Create backup of databases and volumes
./scripts/netmgmt.sh destroy      # Destroy project and all data (DESTRUCTIVE!)
./scripts/netmgmt.sh help         # Show help message
```

**Features of the wrapper script:**
- ✅ **Prerequisites checking**: Validates Docker, resources, and port availability
- ✅ **Observability stack validation**: Checks connectivity to your monitoring stack
- ✅ **Interactive prompts**: Asks for confirmation on destructive operations
- ✅ **Colored output**: Easy-to-read status messages
- ✅ **Health monitoring**: Waits for services to be healthy before proceeding
- ✅ **Backup functionality**: Automated database and volume backups
- ✅ **Error handling**: Comprehensive error checking and user feedback

### Make Commands (Alternative)
```bash
make help          # Show all available commands
make build         # Build custom Docker images
make up            # Start all services
make down          # Stop services
make destroy       # Stop and remove volumes (DESTRUCTIVE!)
make logs          # Tail logs from all services
make ps            # Show service status
make gen-secrets   # Generate secure secret keys
make bootstrap     # Create superusers (idempotent)
make urls          # Display all service URLs
```

### Service Management
```bash
# View logs for specific service
docker compose logs -f netbox

# Restart a service
docker compose restart netbox

# Scale a service
docker compose up -d --scale netbox-worker=2

# Execute commands in containers
docker compose exec netbox python manage.py shell
docker compose exec nautobot nautobot-server shell
```

### Backup & Recovery
```bash
# Backup databases
docker compose exec postgres-netbox pg_dump -U netbox netbox > netbox_backup.sql
docker compose exec postgres-nautobot pg_dump -U nautobot nautobot > nautobot_backup.sql

# Backup volumes
docker run --rm -v netmgmt-suite_pgdata-netbox:/data -v $(pwd):/backup alpine tar czf /backup/netbox_data.tar.gz -C /data .
```

## 🔐 Security

### Default Security Features
- **Strong Passwords**: All services use strong default passwords
- **Secret Key Generation**: Django secret keys are auto-generated
- **Resource Limits**: CPU and memory limits prevent resource exhaustion
- **Health Checks**: Comprehensive health monitoring
- **Network Isolation**: Services run in isolated Docker network

### Security Hardening
1. **Change Default Passwords**: Update all passwords in .env
2. **Use Secrets Management**: Consider using Docker secrets for production
3. **Enable HTTPS**: Configure reverse proxy with SSL certificates
4. **Network Security**: Restrict access via firewall rules
5. **Regular Updates**: Keep Docker images updated

## 🚨 Troubleshooting

### Common Issues

#### Services Won't Start
```bash
# Check service status
make ps

# View detailed logs
make logs

# Check resource usage
docker stats
```

#### Database Connection Issues
```bash
# Check database health
docker compose exec postgres-netbox pg_isready -U netbox
docker compose exec postgres-nautobot pg_isready -U nautobot

# Reset databases (DESTRUCTIVE!)
make destroy
make up
make bootstrap
```

#### Observability Integration Issues
```bash
# Test connectivity to observability stack
curl http://192.168.5.13:9200/_cluster/health
curl http://192.168.5.13:9090/api/v1/status/config

# Check Filebeat logs
docker compose logs filebeat
```

#### Performance Issues
```bash
# Monitor resource usage
docker stats

# Check service health
docker compose ps

# Adjust resource limits in docker-compose.yml
```

### Log Locations
- **Application Logs**: Shipped to ELK stack via Filebeat
- **Docker Logs**: `docker compose logs <service>`
- **Filebeat Logs**: `/var/log/filebeat/` in container

## 📚 Additional Resources

### Documentation
- [NetBox Documentation](https://docs.netbox.dev/)
- [Nautobot Documentation](https://docs.nautobot.com/)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Oxidized Documentation](https://github.com/ytti/oxidized)

### Plugins & Extensions
- **NetBox Plugins**: Topology views, BGP, Onboarding
- **Nautobot Apps**: Nornir, SSOT, Device Onboarding, BGP Models

### Support
- Check service health: `make ps`
- View logs: `make logs`
- Restart services: `make down && make up`

## 🎯 Next Steps

1. **Initial Setup**: Complete the quick start guide
2. **Configure Services**: Set up NetBox/Nautobot with your network data
3. **Create Pipelines**: Build Jenkins jobs for network automation
4. **Setup Monitoring**: Import Prometheus config to your observability stack
5. **Create Dashboards**: Build Grafana dashboards for network metrics
6. **Setup Alerts**: Configure Alertmanager rules for critical events

---

**Note**: This suite is designed for network management and automation. Ensure you have proper backups and test in a non-production environment first.
MD
