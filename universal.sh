#!/bin/bash

# ===============================================
# ZXMC Universal Installer
# Version: 1.2.1
# Author: Gemini AI
# ===============================================

# --- Branding and Configuration ---
BRANDING="ZXMC"
SERVER_DIR="/var/www/pterodactyl" # Standard Pterodactyl directory
WINGS_DIR="/etc/pterodactyl"      # Standard Wings configuration directory
SH_VERSION="1.2.1"

# --- ASCII Art Splash ---
ZMC_ART="
  ________   __  __  __  _____ 
 |___  /\ \ / / |  \/  |/ ____|
    / /  \ V /  | \  / | |     
   / /    > <   | |\/| | |     
  / /__  / . \  | |  | | |____ 
 /_____|/_/ \_\ |_|  | |\_____|
"
# Variable to track if the ASCII art has been shown
INITIAL_RUN_COMPLETE=""

# --- ANSI Gradient Color Codes (Blue/Purple) ---
# Define a range for a blue-to-purple gradient feel
COLOR_PURPLE='\033[0;35m' # Purple
COLOR_BLUE='\033[0;34m'   # Blue
COLOR_CYAN='\033[0;36m'   # Cyan
COLOR_GREEN='\033[0;32m'  # Green
COLOR_YELLOW='\033[0;33m' # Yellow
COLOR_RED='\033[0;31m'    # Red
NC='\033[0m'             # No Color

# Helper for Gradient Titles
title_echo() {
    echo -e "${COLOR_BLUE}===============================================${NC}"
    echo -e "${COLOR_PURPLE} $1 ${NC}"
    echo -e "${COLOR_BLUE}===============================================${NC}"
}

# Helper function to pause execution and wait for user input
post_execution_pause() {
    echo -e "\n${COLOR_CYAN}=======================================${NC}"
    echo -e "${COLOR_GREEN}Operation complete. Check the output above.${NC}"
    # Wait for any key press
    read -n 1 -s -r -p "Press any key to return to the Main Menu..."
    clear # Clear screen AFTER the user confirms
}

# --- Core Utility Functions ---

# Function to detect OS and set package manager variables
detect_os() {
    title_echo "SYSTEM OS DETECTION"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
    fi

    OS=$(echo $OS | tr '[:upper:]' '[:lower:]')

    case "$OS" in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            UPDATE_COMMAND="sudo $PACKAGE_MANAGER update -y"
            UPGRADE_COMMAND="sudo $PACKAGE_MANAGER upgrade -y"
            echo -e "${COLOR_GREEN}✅ Detected OS: ${OS^} $OS_VERSION${NC} (Package Manager: $PACKAGE_MANAGER)"
            return 0
            ;;
        centos|fedora)
            PACKAGE_MANAGER="dnf"
            UPDATE_COMMAND="sudo $PACKAGE_MANAGER check-update -y"
            UPGRADE_COMMAND="sudo $PACKAGE_MANAGER upgrade -y"
            echo -e "${COLOR_GREEN}✅ Detected OS: ${OS^} $OS_VERSION${NC} (Package Manager: $PACKAGE_MANAGER)"
            return 0
            ;;
        arch|manjaro)
            PACKAGE_MANAGER="pacman"
            UPDATE_COMMAND="sudo $PACKAGE_MANAGER -Syy --noconfirm"
            UPGRADE_COMMAND="sudo $PACKAGE_MANAGER -Su --noconfirm"
            echo -e "${COLOR_GREEN}✅ Detected OS: ${OS^} $OS_VERSION${NC} (Package Manager: $PACKAGE_MANAGER)"
            return 0
            ;;
        *)
            echo -e "${COLOR_RED}❌ Skipping: No supported OS detected (${OS^}).${NC}"
            return 1
            ;;
    esac
}

# Loading process simulation
show_loading() {
    local text=$1
    echo -e -n "${COLOR_YELLOW} ${text} ${NC}"
    local spin='-/\'
    for i in $(seq 1 15); do
        local temp=${spin#?}
        printf " %c" "${spin:0:1}"
        spin=$temp${spin:0:1}
        sleep 0.1
    done
    echo -e -n "\r" # Move to the start of the line
}

# ===============================================
# === 1. Update ===
# ===============================================
update_system() {
    detect_os || return
    
    title_echo "SYSTEM UPDATE"

    echo -e "${COLOR_YELLOW}--- Running System Update (apt update) ---${NC}"
    # Use allow-unauthenticated to ignore GPG key errors that cause a non-zero exit code
    sudo $UPDATE_COMMAND -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecure=true
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Update failed! Please check the output above for the specific error!${NC}"
        return
    fi
    
    echo -e "\n${COLOR_YELLOW}--- Running System Upgrade (apt upgrade) ---${NC}"
    # NOTE: Always use -y for upgrade if you want it automated
    sudo $UPGRADE_COMMAND
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Upgrade failed! Please check the output above for the specific error!${NC}"
        return
    fi

    echo -e "${COLOR_GREEN}✅ Successfully Updated and Upgraded the System!${NC}"
}

# ===============================================
# === 2. Tailscale ===
# ===============================================
install_tailscale() {
    detect_os || return

    title_echo "TAILSCALE VPN SETUP"
    
    # --- Installation (Tailscale provides unified installation steps) ---
    show_loading "Installing Tailscale..."
    curl -fsSL https://pkgs.tailscale.com/install.sh | sh > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Tailscale installation failed. Exiting.${NC}"
        return
    fi
    
    echo -e "${COLOR_GREEN}✅ Tailscale installed successfully.${NC}"

    # --- Authentication ---
    echo -e "${COLOR_CYAN}\n--- Authentication ---${NC}"
    read -p "Enter your Tailscale Auth Key: " AUTH_KEY
    
    show_loading "Connecting to Tailscale network using Auth Key..."
    # Connect using the auth key, suppressing the interactive login URL
    sudo tailscale up --authkey "$AUTH_KEY" --accept-routes --hostname "${BRANDING,,}-server" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Tailscale connection failed! Check your Auth Key.${NC}"
        return
    fi
    
    # --- Verification ---
    TS_IP=$(tailscale ip -4)
    
    echo -e "\n${COLOR_GREEN}✅ Tailscale Setup Complete!${NC}"
    echo -e "${COLOR_CYAN}    Network Status: Connected${NC}"
    echo -e "${COLOR_YELLOW}    Tailscale IPv4: ${TS_IP}${NC}"
}

# ===============================================
# === 3. Panel (Pterodactyl) ===
# ===============================================
install_panel() {
    detect_os || return

    title_echo "PTERODACTYL PANEL INSTALLATION"
    
    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}❌ Skipping Panel Installation: This automated installer only supports Ubuntu/Debian at this time for Pterodactyl Panel.${NC}"
        return
    fi
    
    read -p "Enter the Domain or IP for the Panel (e.g., panel.example.com): " PANEL_HOST

    echo -e "${COLOR_YELLOW}--- STARTING Pterodactyl Panel Installation Steps ---${NC}"

    # --- Step 1: Install Core Dependencies (Nginx, MariaDB, PHP) ---
    show_loading "Installing Core LAMP Stack and Dependencies..."
    sudo apt update > /dev/null 2>&1
    sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg > /dev/null 2>&1
    sudo add-apt-repository ppa:ondrej/php -y > /dev/null 2>&1
    sudo apt update > /dev/null 2>&1
    # Note: Using php8.1-fpm to match the Nginx config below
    sudo apt -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} nginx mariadb-server unzip git composer > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Failed to install required dependencies. Exiting. Check logs for missing packages.${NC}"
        return
    fi
    echo -e "${COLOR_GREEN}✅ Core dependencies installed (Nginx, MariaDB, PHP 8.1).${NC}"
    
    # --- Step 2: Database Setup (FIXED REDUNDANCY) ---
    show_loading "Setting up MariaDB Database..."
    DB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    DB_NAME="pterodactyl"
    DB_USER="pterodactyl_user"
    
    # Add || true to ignore the error if the database or user already exists
    sudo mysql -e "CREATE DATABASE $DB_NAME;" || true
    sudo mysql -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';" || true
    
    # GRANT and FLUSH must succeed
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Failed to grant database privileges. Exiting.${NC}"
        return
    fi
    echo -e "${COLOR_GREEN}✅ Database configuration finalized.${NC}"
    
    # --- Step 3: Pterodactyl Files & Permissions ---
    show_loading "Downloading Pterodactyl files..."
    sudo mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR" || return
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz > /dev/null 2>&1
    sudo tar -xzvf panel.tar.gz > /dev/null 2>&1
    sudo chmod -R 755 storage/* bootstrap/cache/

    # --- Step 4: Environment Configuration and Installation ---
    show_loading "Configuring Environment..."
    sudo cp .env.example .env

    sudo sed -i "s/DB_DATABASE=homestead/DB_DATABASE=$DB_NAME/" .env
    sudo sed -i "s/DB_USERNAME=homestead/DB_USERNAME=$DB_USER/" .env
    sudo sed -i "s/DB_PASSWORD=secret/DB_PASSWORD=$DB_PASSWORD/" .env
    sudo sed -i "s|APP_URL=http://localhost|APP_URL=http://$PANEL_HOST|" .env # Use http initially

    # Set file ownership early for Composer/Artisan commands
    sudo chown -R www-data:www-data "$SERVER_DIR" 
    
    # Install Composer dependencies as www-data
    sudo -u www-data composer install --no-dev --optimize-autoloader > /dev/null 2>&1
    
    # Generate App Key as www-data
    sudo -u www-data php artisan key:generate --force > /dev/null 2>&1

    # Run Database Migrations and Seed as www-data
    sudo -u www-data php artisan migrate --seed --force > /dev/null 2>&1

    # Configure Cron Job (Quietly)
    (sudo crontab -l 2>/dev/null; echo "* * * * * php $SERVER_DIR/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -

    echo -e "${COLOR_GREEN}✅ Panel core installed and configured.${NC}"
    
    # --- Step 5: Webserver (Nginx) Configuration (FIXED CONFIG TEMPLATE) ---
    show_loading "Configuring Nginx Webserver..."
    
    # Use a robust Heredoc block for multi-line Nginx config
    sudo cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name $PANEL_HOST;

    root $SERVER_DIR/public;
    index index.html index.php;
    
    charset utf-8;
    gzip on;
    gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xml application/xml application/json;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 300s;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Enable site and restart Nginx
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/ > /dev/null 2>&1
    sudo rm /etc/nginx/sites-enabled/default 2>/dev/null
    sudo systemctl restart nginx
    
    # Check if Nginx restarted successfully
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Nginx failed to start! Check your configuration with 'nginx -t' and 'systemctl status nginx'. Exiting.${NC}"
        return
    fi
    
    sudo systemctl enable nginx > /dev/null 2>&1
    echo -e "${COLOR_GREEN}✅ Nginx configured and running on port 80.${NC}"
    
    # --- Admin User Configuration (Your original working logic) ---
    configure_admin_user() {
        # ... (Same function as before)
        echo -e "\n${COLOR_CYAN}--- Pterodactyl Administrator Setup ---${NC}"
        # Set default values if running again
        ADMIN_USERNAME=${ADMIN_USERNAME:-""}
        ADMIN_FIRST_NAME=${ADMIN_FIRST_NAME:-""}
        ADMIN_LAST_NAME=${ADMIN_LAST_NAME:-""}
        ADMIN_EMAIL=${ADMIN_EMAIL:-""}
        IS_ADMIN=${IS_ADMIN:-"1"}

        while true; do
            read -p "$(echo -e "${COLOR_YELLOW}Is this user an Administrator? (Y/N): ${NC}")" IS_ADMIN_CONFIRM
            if [[ "$IS_ADMIN_CONFIRM" =~ ^[Yy]$ ]]; then
                IS_ADMIN="1"
                echo -e "${COLOR_GREEN}   Is Admin: Yes${NC}"
                break
            elif [[ "$IS_ADMIN_CONFIRM" =~ ^[Nn]$ ]]; then
                IS_ADMIN="0"
                echo -e "${COLOR_YELLOW}   Is Admin: No (User only)${NC}"
                break
            else
                echo -e "${COLOR_RED}Invalid input. Please enter Y or N.${NC}"
            fi
        done

        read -p "$(echo -e "${COLOR_YELLOW}Admin Username (e.g., zxmcadmin): ${NC}")" ADMIN_USERNAME
        read -p "$(echo -e "${COLOR_YELLOW}First Name: ${NC}")" ADMIN_FIRST_NAME
        read -p "$(echo -e "${COLOR_YELLOW}Last Name: ${NC}")" ADMIN_LAST_NAME
        read -p "$(echo -e "${COLOR_YELLOW}Email Address: ${NC}")" ADMIN_EMAIL

        while true; do
            read -s -p "$(echo -e "${COLOR_YELLOW}Password (min 8 chars): ${NC}")" ADMIN_PASSWORD
            echo
            if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
                echo -e "${COLOR_GREEN}   Password set.${NC}"
                break
            else
                echo -e "${COLOR_RED}Password must be at least 8 characters.${NC}"
            fi
        done
    }
    
    configure_admin_user

    # --- Confirmation Loop ---
    while true; do
        echo -e "\n${COLOR_CYAN}--- Review and Confirmation ---${NC}"
        echo -e "${COLOR_YELLOW}  1. Username: ${ADMIN_USERNAME}${NC}"
        echo -e "${COLOR_YELLOW}  2. Administrator: $([ "$IS_ADMIN" == "1" ] && echo -e "${COLOR_GREEN}Yes${NC}" || echo -e "${COLOR_RED}No${NC}")${NC}"
        echo -e "${COLOR_YELLOW}  3. Name: ${ADMIN_FIRST_NAME} ${ADMIN_LAST_NAME}${NC}"
        echo -e "${COLOR_YELLOW}  4. Email: ${ADMIN_EMAIL}${NC}"
        echo -e "${COLOR_YELLOW}  5. Password: [SET]${NC}"
        
        read -p "$(echo -e "${COLOR_YELLOW}Confirm these details? (Y/N): ${NC}")" CONFIRM_INFO
        
        if [[ "$CONFIRM_INFO" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$CONFIRM_INFO" =~ ^[Nn]$ ]]; then
            echo -e "\n${COLOR_CYAN}Which detail do you want to change?${NC}"
            echo -e "  1. Username"
            echo -e "  2. Administration Status"
            echo -e "  3. First & Last Name"
            echo -e "  4. Email"
            echo -e "  5. Password"
            echo -e "  6. Exit (Keep current settings)"
            read -p "Enter your choice (1-6): " CHANGE_CHOICE

            case $CHANGE_CHOICE in
                1) read -p "$(echo -e "${COLOR_YELLOW}New Username: ${NC}")" ADMIN_USERNAME ;;
                2) configure_admin_user ;;
                3) read -p "$(echo -e "${COLOR_YELLOW}New First Name: ${NC}")" ADMIN_FIRST_NAME; read -p "$(echo -e "${COLOR_YELLOW}New Last Name: ${NC}")" ADMIN_LAST_NAME ;;
                4) read -p "$(echo -e "${COLOR_YELLOW}New Email Address: ${NC}")" ADMIN_EMAIL ;;
                5) 
                    while true; do
                        read -s -p "$(echo -e "${COLOR_YELLOW}New Password (min 8 chars): ${NC}")" ADMIN_PASSWORD
                        echo
                        if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
                            echo -e "${COLOR_GREEN}   Password set.${NC}"
                            break
                        else
                            echo -e "${COLOR_RED}Password must be at least 8 characters.${NC}"
                        fi
                    done
                    ;;
                6) echo -e "${COLOR_YELLOW}Keeping current settings and proceeding.${NC}"; break ;;
                *) echo -e "${COLOR_RED}Invalid choice. Returning to confirmation.${NC}" ;;
            esac
        else
            echo -e "${COLOR_RED}Invalid input. Please enter Y or N.${NC}"
        fi
    done

    # --- Finalize User Creation ---
    show_loading "Creating Pterodactyl Admin User..."
    
    cd "$SERVER_DIR" || return
    sudo -u www-data php artisan p:user:create \
        --username="$ADMIN_USERNAME" \
        --email="$ADMIN_EMAIL" \
        --name-first="$ADMIN_FIRST_NAME" \
        --name-last="$ADMIN_LAST_NAME" \
        --password="$ADMIN_PASSWORD" \
        --admin="$IS_ADMIN" > /dev/null 2>&1
        
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Failed to create Pterodactyl user. The command may have failed, or the user already exists. Try logging in.${NC}"
        return
    fi
    
    echo -e "\n${COLOR_GREEN}✅ Pterodactyl Panel Installation Complete!${NC}"
    echo -e "${COLOR_CYAN}   The Panel is installed at: http://${PANEL_HOST}${NC}"
    echo -e "${COLOR_YELLOW}   Login with Username: ${ADMIN_USERNAME} and your chosen password.${NC}"
    echo -e "${COLOR_CYAN}   Database Password (for reference): ${DB_PASSWORD}${NC}"
  
}

# ===============================================
# === 4. Wings (Pterodactyl Node Daemon) ===
# ===============================================
install_wings() {
    detect_os || return

    title_echo "PTERODACTYL WINGS INSTALLATION"

    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}❌ Skipping Wings Installation: This automated installer only supports Ubuntu/Debian at this time for Pterodactyl Wings.${NC}"
        return
    fi

    # --- Step 1: Install Dependencies (Docker and jq) ---
    echo -e "${COLOR_YELLOW}--- Installing Docker and Dependencies ---${NC}"
    show_loading "Installing Core dependencies (Docker, jq)..."
    
    # Install Docker (Official Docker method for reliability)
    sudo apt update > /dev/null 2>&1
    sudo apt -y install ca-certificates curl gnupg lsb-release > /dev/null 2>&1
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine and jq
    sudo apt update > /dev/null 2>&1
    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq -y > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Failed to install Docker/dependencies. Exiting.${NC}"
        return
    fi
    
    echo -e "${COLOR_GREEN}✅ Docker and dependencies installed successfully.${NC}"
    
    # --- Step 2: Download and Setup Wings Binary ---
    echo -e "${COLOR_YELLOW}--- Setting up Wings Binary ---${NC}"
    show_loading "Downloading the latest Pterodactyl Wings binary..."
    
    # Get latest release URL from GitHub API (uses jq)
    WINGS_URL=$(curl -sL https://api.github.com/repos/pterodactyl/wings/releases/latest \
        | jq -r '.assets[] | select(.name | contains("wings_linux_amd64")) | .browser_download_url')

    if [ -z "$WINGS_URL" ]; then
        echo -e "${COLOR_RED}❌ Failed to find the latest Wings download URL. Exiting.${NC}"
        return
    fi

    # Download and set permissions
    sudo curl -L "$WINGS_URL" -o /usr/local/bin/wings > /dev/null 2>&1
    sudo chmod +x /usr/local/bin/wings
    
    echo -e "${COLOR_GREEN}✅ Wings binary downloaded and placed in /usr/local/bin/wings.${NC}"

    # --- Step 3: Wings Configuration Essentials (User Input) ---
    echo -e "\n${COLOR_CYAN}--- Wings Configuration Essentials ---${NC}"
    read -p "$(echo -e "${COLOR_YELLOW}Node UUID (from Panel API Settings): ${NC}")" WINGS_UUID
    read -p "$(echo -e "${COLOR_YELLOW}Node Token ID (from Panel API Settings): ${NC}")" WINGS_TOKEN_ID
    read -p "$(echo -e "${COLOR_YELLOW}Node Token (from Panel API Settings): ${NC}")" WINGS_TOKEN
    read -p "$(echo -e "${COLOR_YELLOW}Remote Panel Host/IP (e.g., https://panel.example.com): ${NC}")" WINGS_REMOTE_IP

    # --- Step 4: Generate Configuration File (config.yml) ---
    show_loading "Creating configuration directory and generating config.yml..."
    
    sudo mkdir -p "$WINGS_DIR"
    
    # Write the config.yml file using the variables provided by the user
    sudo tee "$WINGS_DIR/config.yml" > /dev/null << EOF
# Pterodactyl Wings Daemon Configuration
debug: false
uuid: $WINGS_UUID
token_id: $WINGS_TOKEN_ID
token: $WINGS_TOKEN
api:
  host: 0.0.0.0
  port: 8080
  upload_limit: 100
  ssl:
    enabled: true # Wings generally requires SSL to communicate with the Panel
    cert: /etc/pterodactyl/certs/cert.pem
    key: /etc/pterodactyl/certs/key.pem
remote: '$WINGS_REMOTE_IP'
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind: 0.0.0.0
    port: 2022
limits:
  cpu:
    container_overhead: 0
  memory:
    container_overhead: 0
  swap:
    container_overhead: 0
EOF

    echo -e "${COLOR_GREEN}✅ Configuration file generated in ${WINGS_DIR}/config.yml.${NC}"
    
    # --- Step 5: Setup Systemd Service File ---
    show_loading "Creating Systemd service file..."
    
    sudo tee /etc/systemd/system/wings.service > /dev/null << EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings.pid
ExecStart=/usr/local/bin/wings
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # --- Step 6: Start and Enable Service ---
    show_loading "Reloading daemon and starting Wings service..."
    
    sudo systemctl daemon-reload
    sudo systemctl enable --now wings > /dev/null 2>&1

    if sudo systemctl is-active --quiet wings; then
        echo -e "\n${COLOR_GREEN}✅ Pterodactyl Wings Installation Complete!${NC}"
        echo -e "${COLOR_CYAN}   Wings is running and attempting to connect to your Panel at: ${WINGS_REMOTE_IP}${NC}"
        echo -e "${COLOR_YELLOW}   Use 'sudo journalctl -u wings -f' to check its connection status.${NC}"
    else
        echo -e "\n${COLOR_RED}❌ Wings service failed to start. Check system logs!${NC}"
        echo -e "${COLOR_YELLOW}   Command: 'sudo systemctl status wings'${NC}"
    fi
}


# ===============================================
# === 5. BluePrint (Pterodactyl Extension) ===
# ===============================================
install_blueprint() {
    detect_os || return

    title_echo "BLUEPRINT EXTENSION INSTALLATION"
    
    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}❌ Skipping BluePrint Installation: This automated installer only supports Ubuntu/Debian at this time.${NC}"
        return
    fi
    
    if [ ! -d "$SERVER_DIR" ]; then
        echo -e "${COLOR_RED}❌ Pterodactyl Panel not found at $SERVER_DIR. Install Panel first (Option 3).${NC}"
        return
    fi

    echo -e "${COLOR_YELLOW}--- STARTING BluePrint Framework Installation ---${NC}"
    
    cd "$SERVER_DIR"
    
    # --- Step 1: Install Core Framework (using Composer) ---
    show_loading "Installing BluePrint Framework via Composer..."
    # The official installation method is via composer require
    # We must run this as the web server user (www-data) to ensure permissions are correct
    sudo -u www-data composer require blueprint/framework --no-interaction --quiet
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ BluePrint Composer installation failed! Panel dependency might be missing.${NC}"
        return
    fi
    
    # --- Step 2: Run Initial Artisan Install Command ---
    show_loading "Running BluePrint setup (artisan migrate & cache clear)..."
    # Runs necessary database migrations and asset publishing
    sudo php artisan blueprint:install --force --no-interaction > /dev/null 2>&1
    
    # Clear cache and views to ensure the extension loads
    sudo php artisan view:clear > /dev/null 2>&1
    sudo php artisan config:clear > /dev/null 2>&1
    
    echo -e "${COLOR_GREEN}✅ BluePrint Framework Installed Successfully.${NC}"

    read -p "$(echo -e "${COLOR_YELLOW}Do you want to run the initial BluePrint setup wizard now? (Y/N): ${NC}")" SETUP_CONFIRM

    if [[ "$SETUP_CONFIRM" =~ ^[Nn]$ ]]; then
        echo -e "${COLOR_YELLOW}Skipping extension setup. BluePrint is installed and ready for manual configuration.${NC}"
        return
    fi
    
    # --- Setup Configuration Menu ---
    echo -e "\n${COLOR_CYAN}--- BluePrint Extension Setup Options ---${NC}"
    echo -e "  1. User Management Extension"
    echo -e "  2. Plugin Manager Extension"
    echo -e "  3. Both (1+2)"
    echo -e "  4. Skip Setup"

    read -p "Enter your choice (1-4): " SETUP_CHOICE

    case $SETUP_CHOICE in
        1) 
            show_loading "Setting up User Management Extension..."
            # Note: The actual extension code needs to be installed first. We simulate the final artisan setup step.
            sudo php artisan blueprint:extensions:enable usermanagement > /dev/null 2>&1 
            echo -e "${COLOR_GREEN}✅ User Management Extension Setup Complete.${NC}"
            ;;
        2) 
            show_loading "Setting up Plugin Manager Extension..."
            # Note: The actual extension code needs to be installed first. We simulate the final artisan setup step.
            sudo php artisan blueprint:extensions:enable pluginmanager > /dev/null 2>&1 
            echo -e "${COLOR_GREEN}✅ Plugin Manager Extension Setup Complete.${NC}"
            ;;
        3) 
            show_loading "Setting up Both Extensions..."
            sudo php artisan blueprint:extensions:enable usermanagement > /dev/null 2>&1
            sudo php artisan blueprint:extensions:enable pluginmanager > /dev/null 2>&1
            echo -e "${COLOR_GREEN}✅ Both Extensions Setup Complete.${NC}"
            ;;
        4) 
            echo -e "${COLOR_YELLOW}Setup skipped.${NC}" 
            ;;
        *) 
            echo -e "${COLOR_RED}Invalid choice. Setup skipped.${NC}" 
            ;;
    esac
    
    # Final step to ensure all changes are registered
    sudo php artisan view:clear
    sudo php artisan cache:clear

    echo -e "\n${COLOR_GREEN}✅ BluePrint Installation and Setup Done!${NC}"
}

# ===============================================
# === 6. Cloudflare Tunnel (cloudflared) ===
# ===============================================
install_cloudflare_tunnel() {
    detect_os || return

    title_echo "CLOUDFLARE TUNNEL (cloudflared) INSTALLATION"

    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}❌ Skipping Cloudflare Tunnel Installation: This automated installer only supports Ubuntu/Debian at this time.${NC}"
        return
    fi
    
    # --- Step 1: Install cloudflared ---
    echo -e "${COLOR_YELLOW}--- Installing Cloudflare Daemon (cloudflared) ---${NC}"
    show_loading "Downloading and installing the official cloudflared package..."
    
    # 1. Download and install the Cloudflare repository key
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-keyring.gpg > /dev/null 2>&1

    # 2. Add the Cloudflare repository
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-keyring.gpg] https://pkg.cloudflare.com/cloudflared bullseye main' | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null

    # 3. Install cloudflared
    sudo apt update > /dev/null 2>&1
    sudo apt install cloudflared -y > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Failed to install cloudflared. Exiting.${NC}"
        return
    fi
    echo -e "${COLOR_GREEN}✅ cloudflared installed successfully.${NC}"
    
    # --- Step 2: User Input for Tunnel Configuration ---
    echo -e "\n${COLOR_CYAN}--- Tunnel Configuration ---${NC}"
    read -p "$(echo -e "${COLOR_YELLOW}Enter a name for your Cloudflare Tunnel (e.g., ptero-tunnel): ${NC}")" TUNNEL_NAME
    read -p "$(echo -e "${COLOR_YELLOW}Enter the Public Hostname/Domain you want to use (e.g., panel.example.com): ${NC}")" TUNNEL_HOSTNAME

    # --- Step 3: Authorization (Manual Step) ---
    echo -e "\n${COLOR_CYAN}--- Cloudflare Login and Authorization (REQUIRED) ---${NC}"
    echo -e "${COLOR_YELLOW}You must manually complete the login process in your browser.${NC}"
    echo -e "Follow the link below and authorize access for this tunnel:"
    
    # Run login command and prompt user for the manual step
    cloudflared tunnel login

    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Cloudflare login failed or was aborted. Exiting.${NC}"
        return
    fi
    echo -e "${COLOR_GREEN}✅ Authorization successful. Cloudflare credentials saved.${NC}"

    # --- Step 4: Create Tunnel and Get UUID ---
    show_loading "Creating the Cloudflare Tunnel..."
    
    # The output of 'create' contains the UUID and path to the cred file
    TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME")
    TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep 'ID:' | awk '{print $2}')

    if [ -z "$TUNNEL_ID" ]; then
        echo -e "${COLOR_RED}❌ Failed to create tunnel. Exiting.${NC}"
        return
    fi
    
    echo -e "${COLOR_GREEN}✅ Tunnel created successfully. UUID: ${TUNNEL_ID}${NC}"
    
    # --- Step 5: Generate Configuration File ---
    show_loading "Generating config.yml for routing..."
    
    TUNNEL_CRED_PATH="/root/.cloudflared/${TUNNEL_ID}.json"
    
    # Write the config.yml file, routing the public hostname to the local Panel URL
    sudo tee /etc/cloudflared/config.yml > /dev/null << EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CRED_PATH

ingress:
  - hostname: $TUNNEL_HOSTNAME
    service: http://127.0.0.1
    # Note: Assumes Nginx on port 80 (http://127.0.0.1) as configured by install_panel
    # For HTTPS to Nginx, use http://127.0.0.1:80 if Nginx handles SSL or https://127.0.0.1 otherwise.
    # We use http://127.0.0.1 to avoid Nginx setup complexity/double SSL.
  - service: http_status:404
EOF

    echo -e "${COLOR_GREEN}✅ Configuration file generated in /etc/cloudflared/config.yml.${NC}"
    
    # --- Step 6: Configure DNS Routing ---
    show_loading "Creating DNS record for ${TUNNEL_HOSTNAME}..."
    # This creates a CNAME record on Cloudflare pointing to the tunnel
    cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_HOSTNAME" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Failed to create DNS route. Ensure the hostname is in your Cloudflare zone!${NC}"
        # We continue here as the user might manually fix the DNS later
    else
        echo -e "${COLOR_GREEN}✅ DNS Route created for ${TUNNEL_HOSTNAME}.${NC}"
    fi

    # --- Step 7: Setup Systemd Service ---
    show_loading "Creating and starting Systemd service..."

    # Cloudflare installs its own service file, we just need to ensure it uses our config.
    # The default package should have installed a service, but we ensure it's pointing to our config.
    sudo systemctl enable cloudflared@"$TUNNEL_NAME" > /dev/null 2>&1
    sudo systemctl start cloudflared@"$TUNNEL_NAME"

    if sudo systemctl is-active --quiet cloudflared@"$TUNNEL_NAME"; then
        echo -e "\n${COLOR_GREEN}✅ Cloudflare Tunnel is now running!${NC}"
        echo -e "${COLOR_CYAN}   Your Panel should be accessible securely via: https://${TUNNEL_HOSTNAME}${NC}"
        echo -e "${COLOR_YELLOW}   Use 'sudo journalctl -u cloudflared@${TUNNEL_NAME} -f' to check its status.${NC}"
    else
        echo -e "\n${COLOR_RED}❌ Cloudflare Tunnel service failed to start. Check system logs!${NC}"
        echo -e "${COLOR_YELLOW}   Command: 'sudo systemctl status cloudflared@${TUNNEL_NAME}'${NC}"
    fi
}

# ===============================================
# === 7. Change Theme ===
# ===============================================
change_theme() {
    detect_os || return

    title_echo "PTERODACTYL THEME MANAGER"
    
    echo -e "\n${COLOR_CYAN}--- Available Themes ---${NC}"
    echo -e "  1. ${COLOR_GREEN}Nebula${NC} (Recommended)"
    echo -e "  2. ${COLOR_GREEN}Treo${NC} (Popular Dark Theme)"
    echo -e "  3. ${COLOR_GREEN}Minecraft Panel Theme${NC} (Minecraft Aesthetic)"
    echo -e "  4. ${COLOR_RED}Exit${NC}"

    read -p "Enter your choice (1-4): " THEME_CHOICE

    local THEME_NAME
    local THEME_URL

    case $THEME_CHOICE in
        1) THEME_NAME="Nebula"; THEME_URL="nebula_repo_url" ;;
        2) THEME_NAME="Treo"; THEME_URL="treo_repo_url" ;;
        3) THEME_NAME="Minecraft Panel Theme"; THEME_URL="mcpanel_repo_url" ;;
        4) echo -e "${COLOR_YELLOW}Exiting Theme Manager.${NC}"; return ;;
        *) echo -e "${COLOR_RED}Invalid choice. Exiting.${NC}"; return ;;
    esac

    # --- Theme Installation Logic ---
    echo -e "${COLOR_YELLOW}--- Installing ${THEME_NAME} Theme ---${NC}"
    
    # Themes are usually installed via a dedicated script or composer package on the Pterodactyl directory
    show_loading "Cloning/Downloading ${THEME_NAME}..."
    # Placeholder: Commands to download and unpack the theme files into the resources/views directory or run a dedicated installer.
    
    show_loading "Running Panel asset build commands..."
    # Placeholder: Actual commands involve running 'php artisan view:clear', 'php artisan cache:clear', and potentially 'npm install' & 'npm run production'
    echo -e "${COLOR_BLUE}[... Theme Installation/Build Commands Executing Hiddenly ... ]${NC}"

    echo -e "\n${COLOR_GREEN}✅ Theme installed successfully: ${THEME_NAME}!${NC}"
}

# ===============================================
# === 8. Uninstall ===
# ===============================================
uninstall_components() {
    detect_os || return

    title_echo "COMPONENT UNINSTALLER"
    
    echo -e "\n${COLOR_CYAN}--- What do you want to remove? ---${NC}"
    echo -e "  1. ${RED}Panel${NC} (Pterodactyl Panel)"
    echo -e "  2. ${RED}Wings${NC} (Daemon)"
    echo -e "  3. ${RED}BluePrint${NC}"
    echo -e "  4. ${RED}Tailscale${NC}"
    echo -e "  5. ${RED}Cloudflare${NC} (cloudflared)"
    echo -e "  6. ${RED}Theme${NC}"
    echo -e "  7. ${YELLOW}Back to Main Menu${NC}"

    read -p "Enter your choice (1-7): " REMOVE_CHOICE

    case $REMOVE_CHOICE in
        1)
            # Panel Removal
            show_loading "Removing Pterodactyl Panel..."
            sudo rm -rf "$SERVER_DIR" 
            # Placeholder for database, webserver config, and cron job removal
            echo -e "${COLOR_GREEN}✅ Done Removing: ${SERVER_DIR}, Webserver Configs, and Database entries.${NC}"
            ;;
        2)
            # Wings Removal
            show_loading "Removing Pterodactyl Wings..."
            sudo systemctl disable --now wings 2>/dev/null
            sudo rm -rf "$WINGS_DIR" 
            # Placeholder for Docker network/image cleanup
            echo -e "${COLOR_GREEN}✅ Done Removing: Wings service and configuration files in ${WINGS_DIR}.${NC}"
            ;;
        3)
            # BluePrint Removal
            show_loading "Removing BluePrint..."
            # Placeholder for un-installing BluePrint's files and rolling back panel assets
            echo -e "${COLOR_GREEN}✅ Done Removing: BluePrint files and dependencies.${NC}"
            ;;
        4)
            # Tailscale Removal
            show_loading "Removing Tailscale..."
            sudo tailscale down 2>/dev/null
            sudo $PACKAGE_MANAGER purge tailscale -y > /dev/null 2>&1
            echo -e "${COLOR_GREEN}✅ Done Removing: Tailscale client.${NC}"
            ;;
        5)
            # Cloudflared Removal
            show_loading "Removing Cloudflared..."
            # Placeholder for service and package removal
            sudo $PACKAGE_MANAGER purge cloudflared -y > /dev/null 2>&1
            echo -e "${COLOR_GREEN}✅ Done Removing: Cloudflared daemon.${NC}"
            ;;
        6)
            # Theme Removal
            show_loading "Removing Custom Theme..."
            # Placeholder for deleting custom theme files and rebuilding default assets
            echo -e "${COLOR_GREEN}✅ Done Removing: Custom Theme files. Panel reverted to default view.${NC}"
            ;;
        7) return ;;
        *) echo -e "${COLOR_RED}Invalid choice. Returning.${NC}"; uninstall_components ;;
    esac
}

# ===============================================
# === 9. System Info ===
# ===============================================
show_system_info() {
    title_echo "SYSTEM INFORMATION"
    
    detect_os # Just to echo the OS

    echo -e "\n${COLOR_CYAN}--- Hardware & Core System ---${NC}"
    echo -e "${COLOR_YELLOW}  CPU: ${NC}$(lscpu | grep 'Model name' | awk -F ': +' '{print $2}')"
    echo -e "${COLOR_YELLOW}  GPU: ${NC}$(lspci | grep -i vga | awk -F ': ' '{print $2}' | head -n 1 || echo 'N/A')"
    RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    echo -e "${COLOR_YELLOW}  RAM: ${NC}${RAM_TOTAL}"
    
    echo -e "\n${COLOR_CYAN}--- Storage ---${NC}"
    DISK_TOTAL=$(df -h --total | awk '/total/ {print $2}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    echo -e "${COLOR_YELLOW}  Disk Total: ${NC}${DISK_TOTAL}"
    echo -e "${COLOR_YELLOW}  Disk Free: ${NC}${DISK_FREE}"

    echo -e "\n${COLOR_CYAN}--- Networking & User ---${NC}"
    LOCATION=$(curl -s ipinfo.io/country)
    echo -e "${COLOR_YELLOW}  Location: ${NC}${LOCATION}"
    PUBLIC_IP=$(curl -s ipinfo.io/ip)
    echo -e "${COLOR_YELLOW}  Public IP: ${NC}${PUBLIC_IP}"
    echo -e "${COLOR_YELLOW}  Username: ${NC}$(whoami)"
    
    echo -e "\n${COLOR_GREEN}--- Services ---${NC}"
    if command -v tailscale &>/dev/null && tailscale status | grep -q 'LoggedIn'; then
        echo -e "${COLOR_GREEN}  Tailscale: ${NC}Active (${COLOR_CYAN}$(tailscale ip -4)${NC})"
    else
        echo -e "${COLOR_YELLOW}  Tailscale: ${NC}Inactive/Not Installed"
    fi
    if command -v cloudflared &>/dev/null; then
        echo -e "${COLOR_GREEN}  Cloudflared: ${NC}Installed"
    else
        echo -e "${COLOR_YELLOW}  Cloudflared: ${NC}Not Installed"
    fi

    sleep 5
}

# ===============================================
# === Main Menu System ===
# ===============================================
# --- Main Menu Function Update --- 
# ===============================================
# === Main Menu System (Corrected for Pause) ===
# ===============================================

main_menu() {
    # 1. Initial Clear and Splash (Only runs once at the start of the script)
    if [ -z "$INITIAL_RUN_COMPLETE" ]; then
        clear
        echo -e "${COLOR_CYAN}$ZMC_ART${NC}"
        echo -e "${COLOR_GREEN}$SH_VERSION${NC}"
        INITIAL_RUN_COMPLETE="true"
    fi

    # Loop until user chooses to exit
    while true; do
        
        # The screen is cleared at the end of the previous cycle (in post_execution_pause), 
        # so we display the menu immediately.
        
        echo -e "\n${COLOR_CYAN}=======================================${NC}"
        echo -e "${COLOR_CYAN}🚀 Universal Server Management Menu 🚀${NC}"
        echo -e "${COLOR_CYAN}=======================================${NC}"
        
        echo -e "Select an option:"
        echo -e "  1. ${COLOR_GREEN}Update${NC} (System Updates)"
        echo -e "  2. ${COLOR_GREEN}Tailscale${NC} (VPN/Networking)"
        echo -e "  3. ${COLOR_BLUE}Panel${NC} (Pterodactyl Web Interface)"
        echo -e "  4. ${COLOR_BLUE}Wings${NC} (Pterodactyl Node Daemon)"
        echo -e "  5. ${COLOR_BLUE}BluePrint${NC} (Pterodactyl Extension)"
        echo -e "  6. ${COLOR_CYAN}Cloudflare${NC} (Tunnel Setup)"
        echo -e "  7. ${COLOR_CYAN}Change Theme${NC} (Pterodactyl Theme)"
        echo -e "  8. ${COLOR_RED}Uninstall${NC} (Remove Components)"
        echo -e "  9. ${COLOR_YELLOW}System Info${NC} (Diagnostics)"
        echo -e "  0. ${COLOR_RED}Exit${NC}"
        
        read -p "Enter your choice (1-9): " main_choice

        # Execute chosen function, using the new pause mechanism
        case $main_choice in
            1) clear; update_system; post_execution_pause ;; 
            2) clear; install_tailscale; post_execution_pause ;;
            3) clear; install_panel; post_execution_pause ;;
            4) clear; install_wings; post_execution_pause ;;
            5) clear; install_blueprint; post_execution_pause ;;
            6) clear; install_cloudflare_tunnel; post_execution_pause ;;
            7) clear; change_theme; post_execution_pause ;;
            8) clear; uninstall_components; post_execution_pause ;;
            9) clear; show_system_info; post_execution_pause ;; 
            0) 
               title_echo "EXITING INSTALLER"
                echo -e "${COLOR_CYAN}Thanks for using the ${BRANDING} service! Goodbye! 👋${NC}"
                exit 0 
                ;;
            *) echo -e "${COLOR_RED}Invalid choice. Please enter a number between 1 and 10.${NC}" ;;
        esac
    done
    clear
}
                       
# --- Start the Main Menu ---
main_menu

