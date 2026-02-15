#!/bin/bash
# Remote deployment script for portal service
# This script is executed on the main server

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
REMOTE_PATH="${REMOTE_PATH:-/opt/message_broker}"
ARCHIVE_NAME_ON_SERVER="${ARCHIVE_NAME_ON_SERVER:-portal_service.tar.gz}"
# DB_PASSWORD can be passed from PowerShell script, or use default
DB_PASSWORD="${DB_PASSWORD:-MsgBrckr#TnN\$2025}"
# Remove quotes if present (from PowerShell passing)
DB_PASSWORD=$(echo "$DB_PASSWORD" | sed "s/^'//; s/'$//")

log_step "PORTAL SERVICE DEPLOYMENT"
log_info "Remote path: $REMOTE_PATH"
log_info "Archive: $ARCHIVE_NAME_ON_SERVER"
log_info "Portal port: 8080"

# Step 1: Extract archive
log_step "STEP 1: EXTRACTING FILES"

if [ ! -f "/tmp/$ARCHIVE_NAME_ON_SERVER" ]; then
    log_error "Archive not found: /tmp/$ARCHIVE_NAME_ON_SERVER"
    exit 1
fi

log_info "Creating deployment directory..."
mkdir -p "$REMOTE_PATH/portal"
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }

log_info "Extracting archive..."
if [[ "$ARCHIVE_NAME_ON_SERVER" == *.tar.gz ]]; then
    # Extract to a temp location first, then move to portal subdirectory
    TEMP_EXTRACT="/tmp/portal_extract_$$"
    mkdir -p "$TEMP_EXTRACT"
    tar -xzf "/tmp/$ARCHIVE_NAME_ON_SERVER" -C "$TEMP_EXTRACT"
    # Move all extracted files to portal subdirectory
    mv "$TEMP_EXTRACT"/* "$REMOTE_PATH/portal/" 2>/dev/null || true
    mv "$TEMP_EXTRACT"/.* "$REMOTE_PATH/portal/" 2>/dev/null || true
    rmdir "$TEMP_EXTRACT" 2>/dev/null || true
elif [[ "$ARCHIVE_NAME_ON_SERVER" == *.zip ]]; then
    # Extract to a temp location first, then move to portal subdirectory
    TEMP_EXTRACT="/tmp/portal_extract_$$"
    mkdir -p "$TEMP_EXTRACT"
    unzip -q "/tmp/$ARCHIVE_NAME_ON_SERVER" -d "$TEMP_EXTRACT"
    # Move all extracted files to portal subdirectory
    mv "$TEMP_EXTRACT"/* "$REMOTE_PATH/portal/" 2>/dev/null || true
    mv "$TEMP_EXTRACT"/.* "$REMOTE_PATH/portal/" 2>/dev/null || true
    rmdir "$TEMP_EXTRACT" 2>/dev/null || true
else
    log_error "Unknown archive format: $ARCHIVE_NAME_ON_SERVER"
    exit 1
fi

log_ok "Files extracted to $REMOTE_PATH/portal"

# Step 2: Install system dependencies (if not already installed)
log_step "STEP 2: CHECKING SYSTEM DEPENDENCIES"

log_info "Checking for Python 3..."
if ! command -v python3 &> /dev/null; then
    log_info "Installing Python 3..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip python3-venv
    elif command -v yum &> /dev/null; then
        yum install -y -q python3 python3-pip
    elif command -v dnf &> /dev/null; then
        dnf install -y -q python3 python3-pip
    else
        log_error "No supported package manager found"
        exit 1
    fi
    log_ok "Python 3 installed"
else
    log_info "Python 3 already installed"
fi

# Step 3: Set up Python environment
log_step "STEP 3: SETTING UP PYTHON ENVIRONMENT"

log_info "Checking for virtual environment..."
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }

if [ ! -d "venv" ]; then
    log_info "Creating virtual environment..."
    python3 -m venv venv
    log_ok "Virtual environment created"
else
    log_info "Virtual environment already exists"
fi

log_info "Activating virtual environment..."
source venv/bin/activate

log_info "Upgrading pip..."
pip install --upgrade pip --quiet

log_info "Installing portal Python dependencies..."
if [ -f "portal/requirements.txt" ]; then
    # Check if dependencies are already installed
    if pip show fastapi &> /dev/null; then
        log_info "Some dependencies already installed, checking for updates..."
        pip install -r portal/requirements.txt --quiet --upgrade
    else
        pip install -r portal/requirements.txt --quiet
    fi
    log_ok "Python dependencies installed"
else
    log_error "portal/requirements.txt not found"
    exit 1
fi

# Step 4: Update environment file
log_step "STEP 4: CONFIGURING ENVIRONMENT"

log_info "Updating .env file..."
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }

# Check if .env exists, if not create it
if [ ! -f ".env" ]; then
    log_info "Creating .env file..."
    cat > .env <<ENVEOF
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=$DB_PASSWORD

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Main Server Configuration
MAIN_SERVER_URL=https://localhost:8000

# Portal Configuration
PORTAL_HOST=0.0.0.0
PORTAL_PORT=8080
SESSION_SECRET=$(openssl rand -hex 32)

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=$REMOTE_PATH/logs
ENVEOF
    log_ok ".env file created"
else
    log_info ".env file already exists, updating values..."
    
    # Update DB_PASSWORD if provided
    if [ -n "$DB_PASSWORD" ]; then
        if grep -q "^DB_PASSWORD=" .env; then
            sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" .env
        else
            echo "DB_PASSWORD=$DB_PASSWORD" >> .env
        fi
        log_ok "Updated DB_PASSWORD in .env"
    fi
    
    # Ensure MAIN_SERVER_URL is set
    if ! grep -q "^MAIN_SERVER_URL=" .env; then
        echo "MAIN_SERVER_URL=https://localhost:8000" >> .env
    fi
    
    # Ensure PORTAL_PORT is set
    if ! grep -q "^PORTAL_PORT=" .env; then
        echo "PORTAL_PORT=8080" >> .env
    fi
    
    # Ensure SESSION_SECRET is set
    if ! grep -q "^SESSION_SECRET=" .env; then
        SESSION_SECRET=$(openssl rand -hex 32)
        echo "SESSION_SECRET=$SESSION_SECRET" >> .env
        log_ok "Generated SESSION_SECRET"
    fi
    
    log_ok ".env file updated"
fi

# Fix line endings if file was transferred from Windows
sed -i 's/\r$//' .env

# Step 5: Create necessary directories
log_info "Creating log directory..."
mkdir -p "$REMOTE_PATH/portal/logs"
chmod 755 "$REMOTE_PATH/portal/logs"

# Step 6: Install systemd service
log_step "STEP 5: INSTALLING SYSTEMD SERVICE"

if [ "$SKIP_SERVICES" != "true" ]; then
    log_info "Updating service file with correct paths..."
    if [ -f "$REMOTE_PATH/portal/portal.service" ]; then
        # Update paths in service file if needed
        sed -i "s|/opt/message_broker|$REMOTE_PATH|g" "$REMOTE_PATH/portal/portal.service"
        
        # Copy service file to systemd directory
        cp "$REMOTE_PATH/portal/portal.service" /etc/systemd/system/portal.service
        
        log_info "Reloading systemd daemon..."
        systemctl daemon-reload
        
        log_info "Enabling portal service..."
        systemctl enable portal
        
        log_ok "Portal service installed and enabled"
    else
        log_error "portal.service file not found"
        exit 1
    fi
else
    log_info "Skipping service installation (SKIP_SERVICES=true)"
fi

# Step 7: Create service user (if needed)
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
chown -R messagebroker:messagebroker "$REMOTE_PATH/portal"
chmod 755 "$REMOTE_PATH/portal"

# Step 8: Verify main_server service (portal depends on it)
log_info "Checking main_server service status..."
if systemctl is-active --quiet main_server 2>/dev/null || systemctl is-active --quiet main-server 2>/dev/null; then
    log_ok "Main server service is running"
else
    log_warn "Main server service is not running"
    log_info "Portal requires main_server to be running. Please start it:"
    log_info "  systemctl start main_server"
fi

# Step 9: Start service
if [ "$SKIP_SERVICES" != "true" ]; then
    log_step "STEP 6: STARTING PORTAL SERVICE"
    
    log_info "Starting portal service..."
    systemctl start portal
    
    sleep 3
    
    if systemctl is-active --quiet portal; then
        log_ok "Portal service is running"
        log_info "Service status:"
        systemctl status portal --no-pager -l || true
    else
        log_error "Portal service failed to start"
        log_info "Checking logs..."
        journalctl -u portal -n 20 --no-pager || true
        exit 1
    fi
fi

# Final summary
log_step "DEPLOYMENT COMPLETE"

log_ok "Portal service deployed successfully!"
echo ""
log_info "Service information:"
echo "  - Installation path: $REMOTE_PATH/portal"
echo "  - Portal port: 8080"
echo "  - Domain: msgportal.samsolutions.ir"
echo "  - Main server URL: https://localhost:8000"
echo ""
log_info "Useful commands:"
echo "  - Check status: systemctl status portal"
echo "  - View logs: journalctl -u portal -f"
echo "  - Restart: systemctl restart portal"
echo "  - Stop: systemctl stop portal"
echo ""
log_info "Access the portal:"
echo "  - http://msgportal.samsolutions.ir:8080"
echo "  - http://173.32.115.223:8080 (if using IP directly)"
echo ""
log_info "Note: Ensure main_server service is running for portal to function properly"

