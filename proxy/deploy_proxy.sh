#!/bin/bash
# Remote deployment script for proxy service
# This script is executed on the proxy server

set -e  # Exit on error

# Logging functions
log_info() {
    echo "[$(date +'%H:%M:%S')] [INFO] $*"
}

log_ok() {
    echo "[$(date +'%H:%M:%S')] [OK] $*"
}

log_warn() {
    echo "[$(date +'%H:%M:%S')] [WARN] $*"
}

log_error() {
    echo "[$(date +'%H:%M:%S')] [ERROR] $*"
}

log_step() {
    echo ""
    echo "========================================"
    echo "  $*"
    echo "========================================"
    echo ""
}

# Default values
REMOTE_PATH="${REMOTE_PATH:-/opt/message_broker_proxy}"
ARCHIVE_NAME_ON_SERVER="${ARCHIVE_NAME_ON_SERVER:-proxy_service.tar.gz}"
MAIN_SERVER_URL="${MAIN_SERVER_URL:-https://173.32.115.223:8000}"

log_step "PROXY SERVICE DEPLOYMENT"
log_info "Remote path: $REMOTE_PATH"
log_info "Archive: $ARCHIVE_NAME_ON_SERVER"
log_info "Main server URL: $MAIN_SERVER_URL"

# Step 1: Extract archive
log_step "STEP 1: EXTRACTING FILES"

if [ ! -f "/tmp/$ARCHIVE_NAME_ON_SERVER" ]; then
    log_error "Archive not found: /tmp/$ARCHIVE_NAME_ON_SERVER"
    exit 1
fi

log_info "Creating deployment directory..."
mkdir -p "$REMOTE_PATH/proxy"
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }

log_info "Extracting archive..."
if [[ "$ARCHIVE_NAME_ON_SERVER" == *.tar.gz ]]; then
    # Extract to a temp location first, then move to proxy subdirectory
    TEMP_EXTRACT="/tmp/proxy_extract_$$"
    mkdir -p "$TEMP_EXTRACT"
    tar -xzf "/tmp/$ARCHIVE_NAME_ON_SERVER" -C "$TEMP_EXTRACT"
    # Move all extracted files to proxy subdirectory
    mv "$TEMP_EXTRACT"/* "$REMOTE_PATH/proxy/" 2>/dev/null || true
    mv "$TEMP_EXTRACT"/.* "$REMOTE_PATH/proxy/" 2>/dev/null || true
    rmdir "$TEMP_EXTRACT" 2>/dev/null || true
elif [[ "$ARCHIVE_NAME_ON_SERVER" == *.zip ]]; then
    # Extract to a temp location first, then move to proxy subdirectory
    TEMP_EXTRACT="/tmp/proxy_extract_$$"
    mkdir -p "$TEMP_EXTRACT"
    unzip -q "/tmp/$ARCHIVE_NAME_ON_SERVER" -d "$TEMP_EXTRACT"
    # Move all extracted files to proxy subdirectory
    mv "$TEMP_EXTRACT"/* "$REMOTE_PATH/proxy/" 2>/dev/null || true
    mv "$TEMP_EXTRACT"/.* "$REMOTE_PATH/proxy/" 2>/dev/null || true
    rmdir "$TEMP_EXTRACT" 2>/dev/null || true
else
    log_error "Unknown archive format: $ARCHIVE_NAME_ON_SERVER"
    exit 1
fi

log_ok "Files extracted to $REMOTE_PATH/proxy"

# Step 2: Install system dependencies
log_step "STEP 2: INSTALLING SYSTEM DEPENDENCIES"

log_info "Detecting package manager..."
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="apt-get update -qq"
    INSTALL_CMD="apt-get install -y -qq"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    UPDATE_CMD="yum check-update -q || true"
    INSTALL_CMD="yum install -y -q"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="dnf check-update -q || true"
    INSTALL_CMD="dnf install -y -q"
else
    log_error "No supported package manager found (apt-get, yum, dnf)"
    exit 1
fi

log_info "Using package manager: $PKG_MANAGER"
log_info "Updating package lists..."
$UPDATE_CMD

log_info "Installing Python 3, pip, and venv..."
$INSTALL_CMD python3 python3-pip python3-venv

log_info "Installing Redis server..."
$INSTALL_CMD redis-server

log_info "Installing OpenSSL..."
$INSTALL_CMD openssl

log_info "Installing other utilities..."
$INSTALL_CMD curl wget unzip tar

log_ok "System dependencies installed"

# Step 3: Configure Redis
log_step "STEP 3: CONFIGURING REDIS"

log_info "Configuring Redis to listen on localhost..."
if [ -f /etc/redis/redis.conf ]; then
    # Ubuntu/Debian
    REDIS_CONF="/etc/redis/redis.conf"
elif [ -f /etc/redis.conf ]; then
    # CentOS/RHEL
    REDIS_CONF="/etc/redis.conf"
else
    log_warn "Redis config file not found, using defaults"
    REDIS_CONF=""
fi

if [ -n "$REDIS_CONF" ]; then
    # Ensure Redis binds to localhost only
    if grep -q "^bind " "$REDIS_CONF"; then
        sed -i 's/^bind .*/bind 127.0.0.1/' "$REDIS_CONF"
    else
        echo "bind 127.0.0.1" >> "$REDIS_CONF"
    fi
    
    # Enable AOF persistence
    if grep -q "^appendonly " "$REDIS_CONF"; then
        sed -i 's/^appendonly .*/appendonly yes/' "$REDIS_CONF"
    else
        echo "appendonly yes" >> "$REDIS_CONF"
    fi
    
    log_ok "Redis configuration updated"
fi

log_info "Starting and enabling Redis service..."
systemctl enable redis-server 2>/dev/null || systemctl enable redis 2>/dev/null || true
systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null || true

# Wait for Redis to start
sleep 2
if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
    log_ok "Redis service is running"
else
    log_warn "Redis service may not be running - check manually"
fi

# Step 4: Set up Python environment
log_step "STEP 4: SETTING UP PYTHON ENVIRONMENT"

log_info "Creating virtual environment..."
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }
python3 -m venv venv

log_info "Activating virtual environment..."
source venv/bin/activate

log_info "Upgrading pip..."
pip install --upgrade pip --quiet

log_info "Installing Python dependencies..."
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt --quiet
    log_ok "Python dependencies installed"
else
    log_error "requirements.txt not found"
    exit 1
fi

# Step 5: Generate SSL certificates
log_step "STEP 5: GENERATING SSL CERTIFICATES"

log_info "Creating certificates directory..."
mkdir -p "$REMOTE_PATH/proxy/certs"
cd "$REMOTE_PATH/proxy/certs" || { log_error "Failed to cd to proxy/certs directory"; exit 1; }

# Generate CA certificate if it doesn't exist
if [ ! -f "ca.crt" ]; then
    log_info "Generating CA certificate..."
    openssl genrsa -out ca.key 4096
    chmod 600 ca.key
    openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
        -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"
    chmod 644 ca.crt
    log_ok "CA certificate generated"
else
    log_info "CA certificate already exists"
fi

# Generate proxy certificate if it doesn't exist
if [ ! -f "proxy.crt" ]; then
    log_info "Generating proxy certificate..."
    openssl genrsa -out proxy.key 2048
    openssl req -new -key proxy.key -out proxy.csr \
        -subj "/CN=proxy/O=MessageBroker/C=US"
    openssl x509 -req -in proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -out proxy.crt -days 365 -sha256
    chmod 600 proxy.key
    chmod 644 proxy.crt
    rm -f proxy.csr
    log_ok "Proxy certificate generated"
else
    log_info "Proxy certificate already exists"
fi

# Step 6: Create environment file
log_step "STEP 6: CONFIGURING ENVIRONMENT"

log_info "Creating .env file..."
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }

cat > "$REMOTE_PATH/.env" <<ENVEOF
# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Main Server Configuration
MAIN_SERVER_URL=$MAIN_SERVER_URL

# Certificate Paths (relative to proxy directory where service runs)
SERVER_CERT_PATH=certs/proxy.crt
SERVER_KEY_PATH=certs/proxy.key
CA_CERT_PATH=certs/ca.crt

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=$REMOTE_PATH/proxy/logs
ENVEOF

log_ok ".env file created"

# Step 7: Create necessary directories
log_info "Creating log directory..."
mkdir -p "$REMOTE_PATH/proxy/logs"
chmod 755 "$REMOTE_PATH/proxy/logs"

# Step 8: Install systemd service
log_step "STEP 8: INSTALLING SYSTEMD SERVICE"

if [ "$SKIP_SERVICES" != "true" ]; then
    log_info "Updating service file with correct paths..."
    if [ -f "$REMOTE_PATH/proxy/proxy.service" ]; then
        # Update paths in service file
        sed -i "s|/opt/message_broker|$REMOTE_PATH|g" "$REMOTE_PATH/proxy/proxy.service"
        
        # Copy service file to systemd directory
        cp "$REMOTE_PATH/proxy/proxy.service" /etc/systemd/system/proxy.service
        
        log_info "Reloading systemd daemon..."
        systemctl daemon-reload
        
        log_info "Enabling proxy service..."
        systemctl enable proxy
        
        log_ok "Proxy service installed and enabled"
    else
        log_error "proxy.service file not found"
        exit 1
    fi
else
    log_info "Skipping service installation (SKIP_SERVICES=true)"
fi

# Step 9: Create service user (if needed)
log_info "Checking for service user..."
if ! id "messagebroker" &>/dev/null; then
    log_info "Creating service user..."
    useradd -r -s /bin/false messagebroker
    log_ok "Service user created"
else
    log_info "Service user already exists"
fi

# Set ownership
log_info "Setting file ownership..."
chown -R messagebroker:messagebroker "$REMOTE_PATH"
chmod 755 "$REMOTE_PATH"
find "$REMOTE_PATH/proxy/certs" -name "*.key" -type f -exec chmod 600 {} \; 2>/dev/null || true

# Step 10: Start service
if [ "$SKIP_SERVICES" != "true" ]; then
    log_step "STEP 9: STARTING PROXY SERVICE"
    
    log_info "Starting proxy service..."
    systemctl start proxy
    
    sleep 3
    
    if systemctl is-active --quiet proxy; then
        log_ok "Proxy service is running"
        log_info "Service status:"
        systemctl status proxy --no-pager -l || true
    else
        log_error "Proxy service failed to start"
        log_info "Checking logs..."
        journalctl -u proxy -n 20 --no-pager || true
        exit 1
    fi
fi

# Final summary
log_step "DEPLOYMENT COMPLETE"

log_ok "Proxy service deployed successfully!"
echo ""
log_info "Service information:"
echo "  - Installation path: $REMOTE_PATH"
echo "  - Main server URL: $MAIN_SERVER_URL"
echo "  - Proxy port: 8001"
echo "  - Redis: localhost:6379"
echo ""
log_info "Useful commands:"
echo "  - Check status: systemctl status proxy"
echo "  - View logs: journalctl -u proxy -f"
echo "  - Restart: systemctl restart proxy"
echo "  - Stop: systemctl stop proxy"
echo ""
log_info "Test the service:"
echo "  curl -k https://localhost:8001/health"

