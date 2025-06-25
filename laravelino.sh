#!/bin/bash

# Configuration
APP_NAME="my_app_name"
PROJECT_DIR="/var/www/html"
LOG_FILE="/var/log/laravel_setup.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log "WARNING: $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        handle_error "This script must be run as root (use sudo)"
    fi
}

# Update system packages
update_system() {
    log "Starting system update"
    if apt update && apt upgrade -y; then
        success "System updated successfully"
    else
        handle_error "Failed to update system packages"
    fi
}

# Install PHP and dependencies
install_php_dependencies() {
    log "Installing PHP and dependencies"
    local php_packages=(
        "php"
        "php-mbstring"
        "php-xml"
        "php-bcmath"
        "php-curl"
        "php-mysql"
        "php-zip"
    )
    
    if apt install "${php_packages[@]}" -y; then
        success "PHP packages installed successfully"
    else
        handle_error "Failed to install PHP packages"
    fi
}

# Install system utilities
install_system_utilities() {
    log "Installing system utilities"
    local utilities=(
        "git"
        "curl"
        "python3"
        "python3-pip"
        "unzip"
        "apache2"
        "glances"
    )
    
    if apt install "${utilities[@]}" -y; then
        success "System utilities installed successfully"
    else
        handle_error "Failed to install system utilities"
    fi
}

# Install Composer
install_composer() {
    log "Installing Composer"
    if curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; then
        success "Composer installed successfully"
        # Verify installation
        if composer --version > /dev/null 2>&1; then
            success "Composer is working correctly"
        else
            warning "Composer installed but may not be in PATH"
        fi
    else
        handle_error "Failed to install Composer"
    fi
}

# Universal shell configuration function
configure_universal_shell_path() {
    log "Configuring universal shell PATH for PHP and Composer"
    
    # Define the exports we need to add
    local php_path_export="export PATH=\$PATH:/usr/bin/php"
    local composer_path_export="export PATH=\$PATH:/usr/local/bin"
    local script_marker="# Added by Laravel setup script"
    
    # Get the actual user (not root) if script is run with sudo
    local actual_user="${SUDO_USER:-$USER}"
    local user_home
    
    if [[ "$actual_user" != "root" ]]; then
        user_home=$(eval echo "~$actual_user")
    else
        user_home="$HOME"
    fi
    
    # Define shell configuration files to update
    local shell_configs=(
        "$user_home/.bashrc"
        "$user_home/.zshrc" 
        "$user_home/.profile"
        "/etc/profile.d/laravel-setup.sh"  # System-wide configuration
    )
    
    log "Configuring PATH for user: $actual_user (home: $user_home)"
    
    # Function to add exports to a config file
    add_exports_to_config() {
        local config_file="$1"
        local config_name=$(basename "$config_file")
        local updated=false
        
        # Create the file if it doesn't exist (except for system files)
        if [[ ! -f "$config_file" ]] && [[ "$config_file" != "/etc/profile.d/"* ]]; then
            touch "$config_file"
            if [[ "$actual_user" != "root" ]]; then
                chown "$actual_user:$actual_user" "$config_file" 2>/dev/null || true
            fi
        fi
        
        # Check and add PHP PATH if not present
        if [[ -f "$config_file" ]] && ! grep -q "export PATH.*php" "$config_file" 2>/dev/null; then
            {
                echo ""
                echo "$script_marker"
                echo "$php_path_export"
            } >> "$config_file"
            updated=true
        fi
        
        # Check and add Composer PATH if not present
        if [[ -f "$config_file" ]] && ! grep -q "export PATH.*local/bin" "$config_file" 2>/dev/null; then
            if ! grep -q "$script_marker" "$config_file" 2>/dev/null; then
                echo "" >> "$config_file"
                echo "$script_marker" >> "$config_file"
            fi
            echo "$composer_path_export" >> "$config_file"
            updated=true
        fi
        
        if [[ "$updated" == true ]]; then
            success "PATH configured in $config_name"
            # Set proper ownership for user files
            if [[ "$actual_user" != "root" ]] && [[ "$config_file" != "/etc/"* ]]; then
                chown "$actual_user:$actual_user" "$config_file" 2>/dev/null || true
            fi
        else
            log "PATH already configured in $config_name"
        fi
    }
    
    # Process each configuration file
    for config in "${shell_configs[@]}"; do
        if [[ "$config" == "/etc/profile.d/laravel-setup.sh" ]]; then
            # Create system-wide configuration
            {
                echo "#!/bin/bash"
                echo "$script_marker"
                echo "$php_path_export"
                echo "$composer_path_export"
            } > "$config"
            chmod +x "$config"
            success "System-wide PATH configuration created"
        else
            add_exports_to_config "$config"
        fi
    done
    
    # Detect current shell and provide specific instructions
    local current_shell=$(basename "${SHELL:-/bin/bash}")
    local primary_config=""
    
    case "$current_shell" in
        "bash")
            primary_config="$user_home/.bashrc"
            ;;
        "zsh")
            primary_config="$user_home/.zshrc"
            ;;
        *)
            primary_config="$user_home/.profile"
            ;;
    esac
    
    warning "To apply PATH changes immediately, run one of the following:"
    echo -e "  ${YELLOW}source $primary_config${NC}"
    echo -e "  ${YELLOW}source /etc/profile.d/laravel-setup.sh${NC}"
    echo -e "  ${YELLOW}Or simply restart your terminal${NC}"
    
    # Try to source the configuration for the current session
    if [[ -f "$primary_config" ]] && [[ $- == *i* ]]; then
        source "$primary_config" 2>/dev/null && success "Configuration sourced for current session" || warning "Could not source configuration automatically"
    fi
}

# Setup web directory permissions
setup_web_directory() {
    log "Setting up web directory"
    local proj_dir="$PROJECT_DIR/proj"
    
    if mkdir -p "$proj_dir" && cd "$proj_dir"; then
        success "Project directory created: $proj_dir"
    else
        handle_error "Failed to create project directory"
    fi
    
    if chown -R www-data:www-data "$PROJECT_DIR"; then
        success "Web directory permissions set"
    else
        handle_error "Failed to set web directory permissions"
    fi
}

# Create Laravel project
create_laravel_project() {
    log "Creating Laravel project: $APP_NAME"
    local proj_dir="$PROJECT_DIR/proj"
    
    cd "$proj_dir" || handle_error "Cannot access project directory"
    
    if composer create-project laravel/laravel "$APP_NAME"; then
        success "Laravel project '$APP_NAME' created successfully"
        
        # Set proper permissions for Laravel
        if chown -R www-data:www-data "$proj_dir/$APP_NAME"; then
            success "Laravel project permissions set"
        else
            warning "Failed to set Laravel project permissions"
        fi
        
        # Set storage and cache permissions
        if chmod -R 775 "$proj_dir/$APP_NAME/storage" "$proj_dir/$APP_NAME/bootstrap/cache" 2>/dev/null; then
            success "Laravel storage permissions set"
        else
            warning "Failed to set Laravel storage permissions"
        fi
    else
        handle_error "Failed to create Laravel project"
    fi
}

# Install and configure MySQL
install_mysql() {
    log "Installing MySQL server"
    if apt install mysql-server -y; then
        success "MySQL server installed successfully"
    else
        handle_error "Failed to install MySQL server"
    fi
}

# Install phpMyAdmin
install_phpmyadmin() {
    log "Installing phpMyAdmin"
    if apt install phpmyadmin -y; then
        success "phpMyAdmin installed successfully"
        warning "Remember to configure phpMyAdmin with Apache manually if needed"
    else
        handle_error "Failed to install phpMyAdmin"
    fi
}

# Restart services
restart_services() {
    log "Restarting services"
    
    if systemctl restart mysql; then
        success "MySQL service restarted"
    else
        warning "Failed to restart MySQL service"
    fi
    
    if systemctl restart apache2; then
        success "Apache2 service restarted"
    else
        warning "Failed to restart Apache2 service"
    fi
    
    # Enable services to start on boot
    systemctl enable mysql apache2
    success "Services enabled for startup"
}

# Display final information
display_final_info() {
    echo -e "\n${GREEN}=== Laravel Setup Complete ===${NC}"
    echo -e "Project Name: ${YELLOW}$APP_NAME${NC}"
    echo -e "Project Location: ${YELLOW}$PROJECT_DIR/proj/$APP_NAME${NC}"
    echo -e "Web Server: ${YELLOW}Apache2${NC}"
    echo -e "Database: ${YELLOW}MySQL${NC}"
    echo -e "Log File: ${YELLOW}$LOG_FILE${NC}"
    echo -e "\n${YELLOW}Shell Configuration:${NC}"
    echo "✓ Bash (.bashrc)"
    echo "✓ Zsh (.zshrc)" 
    echo "✓ Universal (.profile)"
    echo "✓ System-wide (/etc/profile.d/laravel-setup.sh)"
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. Restart your terminal or source your shell configuration"
    echo "2. Configure your Apache virtual host"
    echo "3. Set up your database connection in Laravel's .env file"
    echo "4. Configure phpMyAdmin if needed"
    echo "5. Test your Laravel application"
}

# Main execution function
main() {
    log "Starting Laravel setup script"
    
    check_root
    update_system
    install_php_dependencies
    install_system_utilities
    install_composer
    configure_universal_shell_path
    setup_web_directory
    create_laravel_project
    install_mysql
    install_phpmyadmin
    restart_services
    display_final_info
    
    success "Laravel setup completed successfully!"
}

# Execute main function
main "$@"
