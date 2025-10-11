#!/bin/bash
# ============================================================================
# The Markdown Redemption - Service Installation Script
# ============================================================================
# This script installs The Markdown Redemption as a systemd service
# Usage:
#   ./install-service.sh           # Install service
#   ./install-service.sh -u        # Uninstall service
#   ./install-service.sh --uninstall

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="markdown-redemption"
SERVICE_NAME="${APP_NAME}.service"

# Determine if running as root
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=true
    SYSTEMD_DIR="/etc/systemd/system"
    USER_MODE=""
else
    IS_ROOT=false
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    USER_MODE="--user"
fi

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if service exists
service_exists() {
    systemctl $USER_MODE list-unit-files | grep -q "^${SERVICE_NAME}"
}

# Function to uninstall service
uninstall_service() {
    print_info "Uninstalling ${APP_NAME} service..."

    if service_exists; then
        # Stop service if running
        if systemctl $USER_MODE is-active --quiet "${SERVICE_NAME}"; then
            print_info "Stopping service..."
            systemctl $USER_MODE stop "${SERVICE_NAME}"
        fi

        # Disable service if enabled
        if systemctl $USER_MODE is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
            print_info "Disabling service..."
            systemctl $USER_MODE disable "${SERVICE_NAME}"
        fi

        # Remove service file
        SERVICE_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}"
        if [ -f "${SERVICE_FILE}" ]; then
            print_info "Removing service file..."
            rm -f "${SERVICE_FILE}"
        fi

        # Reload systemd
        systemctl $USER_MODE daemon-reload

        print_success "Service uninstalled successfully"
    else
        print_warning "Service not found, nothing to uninstall"
    fi

    exit 0
}

# Function to check dependencies
check_dependencies() {
    print_info "Checking dependencies..."

    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        exit 1
    fi

    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    print_info "Found Python ${PYTHON_VERSION}"

    # Check for systemd
    if ! command -v systemctl &> /dev/null; then
        print_error "systemd is not available on this system"
        exit 1
    fi

    print_success "All dependencies satisfied"
}

# Function to create virtual environment
setup_venv() {
    print_info "Setting up Python virtual environment..."

    VENV_DIR="${SCRIPT_DIR}/venv"

    if [ -d "${VENV_DIR}" ]; then
        print_warning "Virtual environment already exists, skipping creation"
    else
        python3 -m venv "${VENV_DIR}"
        print_success "Virtual environment created"
    fi

    # Activate venv and install dependencies
    print_info "Installing Python dependencies..."
    source "${VENV_DIR}/bin/activate"
    pip install --upgrade pip > /dev/null 2>&1
    pip install -r "${SCRIPT_DIR}/requirements.txt"
    deactivate

    print_success "Dependencies installed"
}

# Function to check .env file
check_env_file() {
    print_info "Checking configuration..."

    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
        print_warning ".env file not found"
        
        if [ -f "${SCRIPT_DIR}/.env.default" ]; then
            print_info "Copying .env.default to .env"
            cp "${SCRIPT_DIR}/.env.default" "${SCRIPT_DIR}/.env"
            print_warning "Please edit .env file with your settings before starting the service"
        else
            print_error ".env.default not found. Cannot create configuration."
            exit 1
        fi
    else
        print_success ".env file found"
    fi
}

# Function to load .env file
load_env() {
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        # Export variables from .env (ignore comments and empty lines)
        # Use eval to properly handle values with spaces
        set -a
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            # Export the variable
            eval "export $line"
        done < "${SCRIPT_DIR}/.env"
        set +a
    fi
}

# Function to create systemd service file
create_service_file() {
    print_info "Creating systemd service file..."

    # Load environment variables
    load_env

    # Get port from .env or default
    PORT="${PORT:-5000}"
    HOST="${HOST:-0.0.0.0}"
    WORKERS="${WORKERS:-4}"

    # Create systemd directory if it doesn't exist
    mkdir -p "${SYSTEMD_DIR}"

    # Determine user and group
    if [ "$IS_ROOT" = true ]; then
        SERVICE_USER="${SUDO_USER:-$USER}"
        SERVICE_GROUP="$(id -gn ${SERVICE_USER})"
        AFTER_TARGET="network.target"
        WANTED_BY="multi-user.target"
    else
        SERVICE_USER="$USER"
        SERVICE_GROUP="$(id -gn)"
        AFTER_TARGET="default.target"
        WANTED_BY="default.target"
    fi

    # Create service file
    SERVICE_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}"

    if [ "$IS_ROOT" = true ]; then
        # System service
        cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=The Markdown Redemption - Document to Markdown Converter
After=${AFTER_TARGET}
Wants=${AFTER_TARGET}

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${SCRIPT_DIR}
Environment="PATH=${SCRIPT_DIR}/venv/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=${SCRIPT_DIR}/.env
ExecStart=${SCRIPT_DIR}/venv/bin/gunicorn -c ${SCRIPT_DIR}/gunicorn_config.py app:app
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${APP_NAME}

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${SCRIPT_DIR}/uploads ${SCRIPT_DIR}/results ${SCRIPT_DIR}/flask_session

[Install]
WantedBy=${WANTED_BY}
EOF
    else
        # User service
        cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=The Markdown Redemption - Document to Markdown Converter
After=${AFTER_TARGET}

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
Environment="PATH=${SCRIPT_DIR}/venv/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=${SCRIPT_DIR}/.env
ExecStart=${SCRIPT_DIR}/venv/bin/gunicorn -c ${SCRIPT_DIR}/gunicorn_config.py app:app
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${APP_NAME}

[Install]
WantedBy=${WANTED_BY}
EOF
    fi

    print_success "Service file created at ${SERVICE_FILE}"
}

# Function to enable and start service
enable_service() {
    print_info "Enabling systemd service..."

    # Reload systemd
    systemctl $USER_MODE daemon-reload

    # Enable service
    systemctl $USER_MODE enable "${SERVICE_NAME}"
    print_success "Service enabled"

    # Ask user if they want to start now
    read -p "Start the service now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl $USER_MODE start "${SERVICE_NAME}"
        sleep 2
        
        if systemctl $USER_MODE is-active --quiet "${SERVICE_NAME}"; then
            print_success "Service started successfully"
            
            # Show status
            print_info "Service status:"
            systemctl $USER_MODE status "${SERVICE_NAME}" --no-pager
            
            load_env
            PORT="${PORT:-5000}"
            print_success "Application available at: http://localhost:${PORT}"
        else
            print_error "Service failed to start. Check logs with:"
            if [ "$IS_ROOT" = true ]; then
                echo "  sudo journalctl -u ${SERVICE_NAME} -n 50"
            else
                echo "  journalctl --user -u ${SERVICE_NAME} -n 50"
            fi
        fi
    else
        print_info "Service installed but not started. Start it with:"
        echo "  systemctl $USER_MODE start ${SERVICE_NAME}"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install The Markdown Redemption as a systemd service.

OPTIONS:
    -u, --uninstall    Uninstall the service
    -h, --help         Show this help message

EXAMPLES:
    $0                 # Install service
    $0 --uninstall     # Uninstall service

NOTES:
    - If run as root, installs system-wide service
    - If run as regular user, installs user service
    - Automatically creates Python virtual environment
    - Checks for .env file and creates from .env.default if needed

COMMANDS AFTER INSTALLATION:
    Start:   systemctl $USER_MODE start ${SERVICE_NAME}
    Stop:    systemctl $USER_MODE stop ${SERVICE_NAME}
    Status:  systemctl $USER_MODE status ${SERVICE_NAME}
    Logs:    journalctl $USER_MODE -u ${SERVICE_NAME} -f
    Restart: systemctl $USER_MODE restart ${SERVICE_NAME}

EOF
}

# Main installation function
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  The Markdown Redemption - Service Installer          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo

    if [ "$IS_ROOT" = true ]; then
        print_info "Running as root - installing system service"
    else
        print_info "Running as user - installing user service"
    fi
    echo

    check_dependencies
    setup_venv
    check_env_file
    create_service_file
    enable_service

    echo
    print_success "Installation complete!"
    echo
    print_info "Useful commands:"
    echo "  Status:  systemctl $USER_MODE status ${SERVICE_NAME}"
    echo "  Logs:    journalctl $USER_MODE -u ${SERVICE_NAME} -f"
    echo "  Stop:    systemctl $USER_MODE stop ${SERVICE_NAME}"
    echo "  Start:   systemctl $USER_MODE start ${SERVICE_NAME}"
    echo "  Restart: systemctl $USER_MODE restart ${SERVICE_NAME}"
    echo
}

# Parse arguments
case "${1:-}" in
    -u|--uninstall)
        uninstall_service
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
