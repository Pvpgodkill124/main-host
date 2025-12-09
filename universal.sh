#!/bin/bash

# ===============================================
# ZXMC Universal Installer
# Version: 1.3.0
# Author: Claude (Anthropic)
# ===============================================

# --- Branding and Configuration ---
BRANDING="ZXMC"
SERVER_DIR="/var/www/pterodactyl"
WINGS_DIR="/etc/pterodactyl"
SH_VERSION="1.3.0"

# --- ASCII Art Splash ---
ZMC_ART="
  ________   __  __  __  _____ 
 |___  /\ \ / / |  \/  |/ ____|
    / /  \ V /  | \  / | |     
   / /    > <   | |\/| | |     
  / /__  / . \  | |  | | |____ 
 /_____|/_/ \_\ |_|  | |\_____|
"
INITIAL_RUN_COMPLETE=""

# --- ANSI Color Codes ---
COLOR_PURPLE='\033[0;35m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
NC='\033[0m'

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
    read -n 1 -s -r -p "Press any key to return to the Main Menu..."
    clear
}

# --- Core Utility Functions ---

# Function to detect OS and set package manager variables
detect_os() {
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
            UPDATE_COMMAND="sudo apt update -y"
            UPGRADE_COMMAND="sudo apt upgrade -y"
            OS_DISPLAY=$(echo $OS | sed 's/.*/\u&/')
            echo -e "${COLOR_GREEN}Detected OS: ${OS_DISPLAY} ${OS_VERSION}${NC} (Package Manager: ${PACKAGE_MANAGER})"
            return 0
            ;;
        centos|fedora|rhel)
            PACKAGE_MANAGER="dnf"
            UPDATE_COMMAND="sudo dnf check-update -y"
            UPGRADE_COMMAND="sudo dnf upgrade -y"
            OS_DISPLAY=$(echo $OS | sed 's/.*/\u&/')
            echo -e "${COLOR_GREEN}Detected OS: ${OS_DISPLAY} ${OS_VERSION}${NC} (Package Manager: ${PACKAGE_MANAGER})"
            return 0
            ;;
        arch|manjaro)
            PACKAGE_MANAGER="pacman"
            UPDATE_COMMAND="sudo pacman -Syy --noconfirm"
            UPGRADE_COMMAND="sudo pacman -Su --noconfirm"
            OS_DISPLAY=$(echo $OS | sed 's/.*/\u&/')
            echo -e "${COLOR_GREEN}Detected OS: ${OS_DISPLAY} ${OS_VERSION}${NC} (Package Manager: ${PACKAGE_MANAGER})"
            return 0
            ;;
        *)
            OS_DISPLAY=$(echo $OS | sed 's/.*/\u&/')
            echo -e "${COLOR_RED}Unsupported OS detected (${OS_DISPLAY}).${NC}"
            return 1
            ;;
    esac
}

# Loading process simulation
show_loading() {
    local text=$1
    echo -e "${COLOR_YELLOW}${text}${NC}"
}

# ===============================================
# === 1. Update ===
# ===============================================
update_system() {
    detect_os || return
    
    title_echo "SYSTEM UPDATE"

    echo -e "${COLOR_YELLOW}Running system update...${NC}"
    eval $UPDATE_COMMAND 2>&1 | grep -v "^Get:" | grep -v "^Hit:" | grep -v "^Reading"
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${COLOR_RED}Update failed! Check your internet connection or repository configuration.${NC}"
        return
    fi
    
    echo -e "${COLOR_YELLOW}Running system upgrade...${NC}"
    DEBIAN_FRONTEND=noninteractive eval $UPGRADE_COMMAND 2>&1 | grep -v "^Get:" | grep -v "^Reading" | grep -v "^Preparing" | grep -v "^Unpacking"
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${COLOR_RED}Upgrade failed!${NC}"
        return
    fi

    echo -e "${COLOR_GREEN}System updated and upgraded successfully!${NC}"
}

# ===============================================
# === 2. Tailscale ===
# ===============================================
install_tailscale() {
    detect_os || return

    title_echo "TAILSCALE VPN SETUP"
    
    show_loading "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Tailscale installation failed.${NC}"
        return
    fi
    
    echo -e "${COLOR_GREEN}Tailscale installed successfully.${NC}"

    echo -e "\n${COLOR_CYAN}--- Authentication ---${NC}"
    read -p "Enter your Tailscale Auth Key: " AUTH_KEY
    
    show_loading "Connecting to Tailscale network..."
    HOSTNAME_LOWER=$(echo ${BRANDING} | tr '[:upper:]' '[:lower:]')
    sudo tailscale up --authkey "$AUTH_KEY" --accept-routes --hostname "${HOSTNAME_LOWER}-server" 2>&1 | tail -n 5

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${COLOR_RED}Tailscale connection failed! Check your Auth Key.${NC}"
        return
    fi
    
    TS_IP=$(tailscale ip -4 2>/dev/null)
    
    echo -e "\n${COLOR_GREEN}Tailscale Setup Complete!${NC}"
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
        echo -e "${COLOR_RED}This installer only supports Ubuntu/Debian for Pterodactyl Panel.${NC}"
        return
    fi
    
    read -p "Enter the Domain or IP for the Panel (e.g., panel.example.com): " PANEL_HOST

    echo -e "${COLOR_YELLOW}--- Starting Pterodactyl Panel Installation ---${NC}"

    show_loading "Installing dependencies (this may take a few minutes)..."
    sudo apt update > /dev/null 2>&1
    sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg > /dev/null 2>&1
    sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
    sudo apt update > /dev/null 2>&1
    sudo apt -y install php8.1 php8.1-cli php8.1-gd php8.1-mysql php8.1-pdo php8.1-mbstring php8.1-tokenizer php8.1-bcmath php8.1-xml php8.1-fpm php8.1-curl php8.1-zip php8.1-redis nginx mariadb-server redis-server tar unzip git composer > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Failed to install dependencies.${NC}"
        return
    fi
    
    # Start and enable Redis
    sudo systemctl enable redis-server > /dev/null 2>&1
    sudo systemctl start redis-server > /dev/null 2>&1
    
    echo -e "${COLOR_GREEN}Dependencies installed (including Redis).${NC}"
    
    show_loading "Configuring MariaDB database..."
    DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    DB_NAME="pterodactyl"
    DB_USER="pterodactyl_user"
    
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};" 2>/dev/null
    sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';" 2>/dev/null
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;" 2>/dev/null
    sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    echo -e "${COLOR_GREEN}Database configured.${NC}"
    
    show_loading "Downloading Pterodactyl Panel..."
    sudo mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR" || return
    sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz 2>/dev/null
    sudo tar -xzf panel.tar.gz 2>/dev/null
    sudo chmod -R 755 storage/* bootstrap/cache/ 2>/dev/null

    echo -e "${COLOR_GREEN}Panel files downloaded.${NC}"
    
    show_loading "Configuring environment..."
    sudo cp .env.example .env 2>/dev/null

    sudo sed -i "s/DB_DATABASE=panel/DB_DATABASE=${DB_NAME}/" .env
    sudo sed -i "s/DB_USERNAME=pterodactyl/DB_USERNAME=${DB_USER}/" .env
    sudo sed -i "s/DB_PASSWORD=/DB_PASSWORD=${DB_PASSWORD}/" .env
    sudo sed -i "s|APP_URL=http://example.com|APP_URL=http://${PANEL_HOST}|" .env
    sudo sed -i "s/APP_ENV=production/APP_ENV=production/" .env
    sudo sed -i "s/APP_DEBUG=false/APP_DEBUG=false/" .env
    
    # Configure Redis cache settings
    sudo sed -i "s/CACHE_DRIVER=file/CACHE_DRIVER=redis/" .env
    sudo sed -i "s/SESSION_DRIVER=file/SESSION_DRIVER=redis/" .env
    sudo sed -i "s/QUEUE_CONNECTION=sync/QUEUE_CONNECTION=redis/" .env

    sudo chown -R www-data:www-data "$SERVER_DIR"
    
    echo -e "${COLOR_YELLOW}Installing Composer dependencies (this may take several minutes)...${NC}"
    cd "$SERVER_DIR"
    sudo -u www-data composer install --no-dev --optimize-autoloader --no-interaction 2>&1 | grep -E "(Installing|Generating|Package)" | tail -n 10
    
    echo -e "${COLOR_GREEN}Composer dependencies installed.${NC}"
    
    show_loading "Generating application key..."
    sudo -u www-data php artisan key:generate --force > /dev/null 2>&1

    show_loading "Running database migrations..."
    sudo -u www-data php artisan migrate --seed --force 2>&1 | grep -E "(Migrating|Seeding)"

    CRON_CMD="* * * * * php ${SERVER_DIR}/artisan schedule:run >> /dev/null 2>&1"
    (sudo crontab -l 2>/dev/null | grep -v "schedule:run"; echo "$CRON_CMD") | sudo crontab -

    echo -e "${COLOR_GREEN}Panel configured.${NC}"
    
    show_loading "Configuring Nginx..."
    
    sudo tee /etc/nginx/sites-available/pterodactyl.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name PANEL_DOMAIN;

    root PANEL_ROOT/public;
    index index.html index.php;
    
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 300s;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    sudo sed -i "s|PANEL_DOMAIN|${PANEL_HOST}|g" /etc/nginx/sites-available/pterodactyl.conf
    sudo sed -i "s|PANEL_ROOT|${SERVER_DIR}|g" /etc/nginx/sites-available/pterodactyl.conf

    sudo ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Nginx configuration error!${NC}"
        return
    fi
    
    sudo systemctl restart nginx
    sudo systemctl enable nginx > /dev/null 2>&1
    echo -e "${COLOR_GREEN}Nginx configured.${NC}"
    
    echo -e "\n${COLOR_CYAN}--- Administrator Account Setup ---${NC}"
    
    read -p "Admin Email: " ADMIN_EMAIL
    read -p "Admin Username: " ADMIN_USERNAME
    read -p "First Name: " ADMIN_FIRST_NAME
    read -p "Last Name: " ADMIN_LAST_NAME
    read -s -p "Password (min 8 characters): " ADMIN_PASSWORD
    echo
    
    while [ ${#ADMIN_PASSWORD} -lt 8 ]; do
        echo -e "${COLOR_RED}Password must be at least 8 characters!${NC}"
        read -s -p "Password: " ADMIN_PASSWORD
        echo
    done

    show_loading "Creating administrator account..."
    cd "$SERVER_DIR"
    
    # First verify database connection
    if ! sudo -u www-data php artisan db:show > /dev/null 2>&1; then
        echo -e "${COLOR_RED}Database connection test failed. Checking configuration...${NC}"
        # Try to fix common issues
        sudo systemctl restart mysql
        sleep 2
    fi
    
    # Create admin user with proper error handling
    OUTPUT=$(sudo -u www-data php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USERNAME" \
        --name-first="$ADMIN_FIRST_NAME" \
        --name-last="$ADMIN_LAST_NAME" \
        --password="$ADMIN_PASSWORD" \
        --admin=1 \
        --no-interaction 2>&1)
    
    if echo "$OUTPUT" | grep -q "successfully\|created"; then
        echo -e "${COLOR_GREEN}Admin user created successfully!${NC}"
    else
        echo -e "${COLOR_RED}Admin user creation failed. Output:${NC}"
        echo "$OUTPUT" | tail -n 5
        echo -e "\n${COLOR_YELLOW}You can create the admin manually later with:${NC}"
        echo -e "${COLOR_CYAN}cd ${SERVER_DIR} && php artisan p:user:make${NC}"
    fi
    
    echo -e "\n${COLOR_GREEN}Pterodactyl Panel Installation Complete!${NC}"
    echo -e "${COLOR_CYAN}   Access your panel at: http://${PANEL_HOST}${NC}"
    echo -e "${COLOR_YELLOW}   Username: ${ADMIN_USERNAME}${NC}"
    echo -e "${COLOR_CYAN}   Database Password (save this): ${DB_PASSWORD}${NC}"
}

# ===============================================
# === 4. Wings (Pterodactyl Node Daemon) ===
# ===============================================
install_wings() {
    detect_os || return

    title_echo "PTERODACTYL WINGS INSTALLATION"

    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}This installer only supports Ubuntu/Debian for Wings.${NC}"
        return
    fi

    echo -e "${COLOR_YELLOW}--- Installing Docker ---${NC}"
    show_loading "Installing Docker and dependencies..."
    
    sudo apt update > /dev/null 2>&1
    sudo apt -y install ca-certificates curl gnupg lsb-release > /dev/null 2>&1
    
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt update > /dev/null 2>&1
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Failed to install Docker.${NC}"
        return
    fi
    
    sudo systemctl enable --now docker > /dev/null 2>&1
    echo -e "${COLOR_GREEN}Docker installed.${NC}"
    
    show_loading "Downloading Wings..."
    
    WINGS_URL=$(curl -sSL https://api.github.com/repos/pterodactyl/wings/releases/latest | grep -o '"browser_download_url": "[^"]*wings_linux_[^"]*"' | grep -o 'https://[^"]*' | head -1)

    if [ -z "$WINGS_URL" ]; then
        echo -e "${COLOR_RED}Failed to get Wings download URL.${NC}"
        return
    fi

    sudo curl -L -o /usr/local/bin/wings "$WINGS_URL" 2>/dev/null
    sudo chmod +x /usr/local/bin/wings
    
    echo -e "${COLOR_GREEN}Wings binary installed.${NC}"

    echo -e "\n${COLOR_CYAN}--- Wings Configuration ---${NC}"
    echo -e "${COLOR_YELLOW}Paste your Wings configuration from the Panel (entire config.yml content):${NC}"
    echo -e "${COLOR_YELLOW}Press Ctrl+D when done pasting${NC}"
    
    sudo mkdir -p "$WINGS_DIR"
    cat > /tmp/wings_config.yml
    sudo mv /tmp/wings_config.yml "$WINGS_DIR/config.yml"

    show_loading "Creating systemd service..."
    
    sudo tee /etc/systemd/system/wings.service > /dev/null << 'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now wings > /dev/null 2>&1

    sleep 2
    
    if sudo systemctl is-active --quiet wings; then
        echo -e "\n${COLOR_GREEN}Wings installed and running!${NC}"
        echo -e "${COLOR_YELLOW}   Check status: sudo systemctl status wings${NC}"
    else
        echo -e "\n${COLOR_RED}Wings failed to start. Check logs: sudo journalctl -u wings -n 50${NC}"
    fi
}

# ===============================================
# === 5. BluePrint (Pterodactyl Extension) ===
# ===============================================
install_blueprint() {
    detect_os || return

    title_echo "BLUEPRINT FRAMEWORK INSTALLATION"
    
    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}This installer only supports Ubuntu/Debian.${NC}"
        return
    fi
    
    if [ ! -d "$SERVER_DIR" ]; then
        echo -e "${COLOR_RED}Pterodactyl Panel not found. Install Panel first (Option 3).${NC}"
        return
    fi

    echo -e "${COLOR_YELLOW}--- Installing BluePrint ---${NC}"
    
    cd "$SERVER_DIR" || return
    
    show_loading "Downloading BluePrint installer..."
    sudo curl -L https://blueprint.zip/api/latest -o blueprint.zip 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Failed to download BluePrint.${NC}"
        return
    fi
    
    show_loading "Extracting and installing..."
    sudo unzip -o blueprint.zip > /dev/null 2>&1
    sudo chmod +x blueprint.sh
    echo "y" | sudo bash blueprint.sh 2>&1 | tail -n 10
    
    if [ $? -eq 0 ]; then
        echo -e "${COLOR_GREEN}BluePrint Framework installed successfully!${NC}"
        echo -e "${COLOR_CYAN}   Access BluePrint settings in your Panel admin area.${NC}"
    else
        echo -e "${COLOR_RED}BluePrint installation encountered issues.${NC}"
    fi
    
    sudo rm -f blueprint.zip
}

# ===============================================
# === 6. Cloudflare Tunnel ===
# ===============================================
install_cloudflare_tunnel() {
    detect_os || return

    title_echo "CLOUDFLARE TUNNEL INSTALLATION"

    if [ "$PACKAGE_MANAGER" != "apt" ]; then
        echo -e "${COLOR_RED}This installer only supports Ubuntu/Debian.${NC}"
        return
    fi
    
    show_loading "Installing cloudflared..."
    
    sudo mkdir -p /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-archive-keyring.gpg > /dev/null 2>&1

    CODENAME=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared ${CODENAME} main" | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null

    sudo apt update > /dev/null 2>&1
    sudo apt install -y cloudflared > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Failed to install cloudflared.${NC}"
        return
    fi
    echo -e "${COLOR_GREEN}cloudflared installed.${NC}"
    
    echo -e "\n${COLOR_CYAN}--- Cloudflare Authentication ---${NC}"
    echo -e "${COLOR_YELLOW}Opening browser for authentication...${NC}"
    
    cloudflared tunnel login

    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Authentication failed.${NC}"
        return
    fi
    echo -e "${COLOR_GREEN}Authenticated successfully.${NC}"

    read -p "Enter tunnel name (e.g., ptero-tunnel): " TUNNEL_NAME
    read -p "Enter your domain (e.g., panel.example.com): " TUNNEL_HOSTNAME

    show_loading "Creating tunnel..."
    
    cloudflared tunnel create "$TUNNEL_NAME" 2>&1 | tee /tmp/tunnel_output.txt | tail -n 5
    TUNNEL_ID=$(grep -oP '(?<=tunnel )[a-f0-9-]+(?= with)' /tmp/tunnel_output.txt | head -1)

    if [ -z "$TUNNEL_ID" ]; then
        TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    fi

    if [ -z "$TUNNEL_ID" ]; then
        echo -e "${COLOR_RED}Failed to create tunnel.${NC}"
        return
    fi
    
    echo -e "${COLOR_GREEN}Tunnel created: $TUNNEL_ID${NC}"
    
    show_loading "Configuring tunnel..."
    
    sudo mkdir -p /root/.cloudflared
    CRED_FILE="/root/.cloudflared/${TUNNEL_ID}.json"
    
    sudo tee /root/.cloudflared/config.yml > /dev/null << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $TUNNEL_HOSTNAME
    service: http://localhost:80
  - service: http_status:404
EOF

    show_loading "Creating DNS route..."
    cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_HOSTNAME" 2>&1 | tail -n 3
    
    show_loading "Installing as service..."
    sudo cloudflared service install > /dev/null 2>&1
    sudo systemctl start cloudflared
    sudo systemctl enable cloudflared > /dev/null 2>&1

    sleep 2
    
    if sudo systemctl is-active --quiet cloudflared; then
        echo -e "\n${COLOR_GREEN}Cloudflare Tunnel is running!${NC}"
        echo -e "${COLOR_CYAN}   Your site should be accessible at: https://${TUNNEL_HOSTNAME}${NC}"
    else
        echo -e "\n${COLOR_RED}Tunnel failed to start.${NC}"
        echo -e "${COLOR_YELLOW}   Check logs: sudo journalctl -u cloudflared -n 50${NC}"
    fi
    
    rm -f /tmp/tunnel_output.txt
}

# ===============================================
# === 7. RDP/VNC Setup ===
# ===============================================
install_rdp_vnc() {
    detect_os || return

    title_echo "RDP/VNC REMOTE DESKTOP SETUP"
    
    echo -e "\n${COLOR_CYAN}--- Remote Desktop Configuration ---${NC}"
    echo -e "  1. Install Desktop Environment (Current OS)"
    echo -e "  2. Install New OS in Container (QEMU/KVM)"
    echo -e "  3. Back to Main Menu"
    
    read -p "Enter your choice (1-3): " RDP_MAIN_CHOICE
    
    case $RDP_MAIN_CHOICE in
        1) install_desktop_environment ;;
        2) install_os_container ;;
        3) return ;;
        *) echo -e "${COLOR_RED}Invalid choice.${NC}"; return ;;
    esac
}

# Desktop Environment Installation for Current OS
install_desktop_environment() {
    title_echo "DESKTOP ENVIRONMENT INSTALLATION"
    
    echo -e "\n${COLOR_CYAN}--- Available Desktop Environments ---${NC}"
    echo -e "  1. XFCE (Lightweight)"
    echo -e "  2. LXDE (Ultra Lightweight)"
    echo -e "  3. GNOME (Full Featured)"
    echo -e "  4. KDE Plasma (Modern)"
    echo -e "  5. MATE (Traditional)"
    echo -e "  6. Cinnamon (Elegant)"
    echo -e "  7. Cancel"
    
    read -p "Select Desktop Environment (1-7): " DE_CHOICE
    
    local DE_NAME=""
    local DE_PACKAGE=""
    
    case $DE_CHOICE in
        1) DE_NAME="XFCE"; DE_PACKAGE="xfce4 xfce4-goodies" ;;
        2) DE_NAME="LXDE"; DE_PACKAGE="lxde-core lxde" ;;
        3) DE_NAME="GNOME"; DE_PACKAGE="ubuntu-desktop" ;;
        4) DE_NAME="KDE Plasma"; DE_PACKAGE="kubuntu-desktop" ;;
        5) DE_NAME="MATE"; DE_PACKAGE="ubuntu-mate-desktop" ;;
        6) DE_NAME="Cinnamon"; DE_PACKAGE="cinnamon-desktop-environment" ;;
        7) return ;;
        *) echo -e "${COLOR_RED}Invalid choice.${NC}"; return ;;
    esac
    
    echo -e "\n${COLOR_CYAN}--- Remote Access Protocol ---${NC}"
    echo -e "  1. RDP (xRDP - Windows Remote Desktop Compatible)"
    echo -e "  2. VNC (TigerVNC - Universal VNC Protocol)"
    echo -e "  3. Both RDP and VNC"
    echo -e "  4. Cancel"
    
    read -p "Select Protocol (1-4): " PROTOCOL_CHOICE
    
    case $PROTOCOL_CHOICE in
        1) PROTOCOL="RDP" ;;
        2) PROTOCOL="VNC" ;;
        3) PROTOCOL="BOTH" ;;
        4) return ;;
        *) echo -e "${COLOR_RED}Invalid choice.${NC}"; return ;;
    esac
    
    # Installation
    show_loading "Installing ${DE_NAME} Desktop Environment..."
    
    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        sudo apt update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive sudo apt install -y $DE_PACKAGE > /dev/null 2>&1
        
        if [ $? -ne 0 ]; then
            echo -e "${COLOR_RED}Failed to install ${DE_NAME}.${NC}"
            return
        fi
        
        echo -e "${COLOR_GREEN}${DE_NAME} installed successfully.${NC}"
        
        # Install Remote Access
        if [ "$PROTOCOL" = "RDP" ] || [ "$PROTOCOL" = "BOTH" ]; then
            show_loading "Installing xRDP..."
            sudo apt install -y xrdp > /dev/null 2>&1
            
            # Configure xRDP
            sudo systemctl enable xrdp > /dev/null 2>&1
            sudo systemctl start xrdp
            
            # Allow RDP through firewall if UFW is active
            if sudo ufw status | grep -q "active"; then
                sudo ufw allow 3389/tcp > /dev/null 2>&1
            fi
            
            echo -e "${COLOR_GREEN}xRDP installed and running on port 3389.${NC}"
        fi
        
        if [ "$PROTOCOL" = "VNC" ] || [ "$PROTOCOL" = "BOTH" ]; then
            show_loading "Installing TigerVNC..."
            sudo apt install -y tigervnc-standalone-server tigervnc-common > /dev/null 2>&1
            
            # Setup VNC
            echo -e "\n${COLOR_CYAN}--- VNC Password Setup ---${NC}"
            read -s -p "Enter VNC Password (6-8 characters): " VNC_PASS
            echo
            
            mkdir -p ~/.vnc
            echo "$VNC_PASS" | vncpasswd -f > ~/.vnc/passwd
            chmod 600 ~/.vnc/passwd
            
            # Create VNC startup script
            cat > ~/.vnc/xstartup << 'VNCEOF'
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
VNCEOF
            chmod +x ~/.vnc/xstartup
            
            # Start VNC server
            vncserver :1 -geometry 1920x1080 -depth 24 > /dev/null 2>&1
            
            # Allow VNC through firewall
            if sudo ufw status | grep -q "active"; then
                sudo ufw allow 5901/tcp > /dev/null 2>&1
            fi
            
            echo -e "${COLOR_GREEN}TigerVNC installed and running on port 5901.${NC}"
        fi
        
    else
        echo -e "${COLOR_RED}This feature currently only supports Ubuntu/Debian.${NC}"
        return
    fi
    
    # Display connection info
    PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "your-server-ip")
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "tailscale-not-configured")
    
    echo -e "\n${COLOR_GREEN}=== Installation Complete! ===${NC}"
    echo -e "${COLOR_CYAN}Desktop Environment: ${DE_NAME}${NC}"
    
    if [ "$PROTOCOL" = "RDP" ] || [ "$PROTOCOL" = "BOTH" ]; then
        echo -e "\n${COLOR_YELLOW}--- RDP Connection Info ---${NC}"
        echo -e "${COLOR_CYAN}  Protocol: RDP (Remote Desktop)${NC}"
        echo -e "${COLOR_CYAN}  Port: 3389${NC}"
        echo -e "${COLOR_CYAN}  Public IP: ${PUBLIC_IP}:3389${NC}"
        echo -e "${COLOR_CYAN}  Tailscale IP: ${TS_IP}:3389${NC}"
        echo -e "${COLOR_YELLOW}  Windows: Use 'Remote Desktop Connection'${NC}"
        echo -e "${COLOR_YELLOW}  Linux: Use 'rdesktop' or 'xfreerdp'${NC}"
    fi
    
    if [ "$PROTOCOL" = "VNC" ] || [ "$PROTOCOL" = "BOTH" ]; then
        echo -e "\n${COLOR_YELLOW}--- VNC Connection Info ---${NC}"
        echo -e "${COLOR_CYAN}  Protocol: VNC${NC}"
        echo -e "${COLOR_CYAN}  Port: 5901${NC}"
        echo -e "${COLOR_CYAN}  Public IP: ${PUBLIC_IP}:5901${NC}"
        echo -e "${COLOR_CYAN}  Tailscale IP: ${TS_IP}:5901${NC}"
        echo -e "${COLOR_YELLOW}  Use VNC Viewer (TightVNC, RealVNC, etc.)${NC}"
        echo -e "${COLOR_YELLOW}  VNC Display: :1${NC}"
    fi
    
    echo -e "\n${COLOR_GREEN}TIP: Use Tailscale IP for secure access!${NC}"
}

# OS Container Installation (QEMU/KVM)
install_os_container() {
    title_echo "VIRTUAL OS INSTALLATION (QEMU/KVM)"
    
    echo -e "\n${COLOR_CYAN}--- Available Operating Systems ---${NC}"
    echo -e "  1. Debian 12 (Stable)"
    echo -e "  2. Ubuntu 22.04 LTS"
    echo -e "  3. Arch Linux (Latest)"
    echo -e "  4. Kali Linux (Latest)"
    echo -e "  5. Fedora (Latest)"
    echo -e "  6. Alpine Linux (Lightweight)"
    echo -e "  7. Cancel"
    
    read -p "Select OS to install (1-7): " OS_CHOICE
    
    local OS_NAME=""
    local ISO_URL=""
    
    case $OS_CHOICE in
        1) 
            OS_NAME="Debian 12"
            ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
            ;;
        2) 
            OS_NAME="Ubuntu 22.04"
            ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
            ;;
        3) 
            OS_NAME="Arch Linux"
            ISO_URL="https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso"
            ;;
        4) 
            OS_NAME="Kali Linux"
            ISO_URL="https://cdimage.kali.org/kali-2024.1/kali-linux-2024.1-installer-amd64.iso"
            ;;
        5) 
            OS_NAME="Fedora"
            ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/39/Server/x86_64/iso/Fedora-Server-netinst-x86_64-39-1.5.iso"
            ;;
        6) 
            OS_NAME="Alpine Linux"
            ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.1-x86_64.iso"
            ;;
        7) return ;;
        *) echo -e "${COLOR_RED}Invalid choice.${NC}"; return ;;
    esac
    
    echo -e "\n${COLOR_CYAN}--- VM Configuration ---${NC}"
    read -p "VM Name (e.g., myvm): " VM_NAME
    read -p "RAM in GB (e.g., 2, 4, 8): " VM_RAM
    read -p "Disk Size in GB (e.g., 20, 40, 80): " VM_DISK
    read -p "CPU Cores (e.g., 2, 4): " VM_CPU
    
    VM_NAME=${VM_NAME:-myvm}
    VM_RAM=${VM_RAM:-2}
    VM_DISK=${VM_DISK:-20}
    VM_CPU=${VM_CPU:-2}
    
    # Install QEMU/KVM
    show_loading "Installing QEMU/KVM virtualization..."
    
    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        sudo apt update > /dev/null 2>&1
        sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager > /dev/null 2>&1
        
        if [ $? -ne 0 ]; then
            echo -e "${COLOR_RED}Failed to install QEMU/KVM.${NC}"
            return
        fi
        
        sudo systemctl enable libvirtd > /dev/null 2>&1
        sudo systemctl start libvirtd
        sudo usermod -aG libvirt $(whoami) > /dev/null 2>&1
        sudo usermod -aG kvm $(whoami) > /dev/null 2>&1
        
        echo -e "${COLOR_GREEN}QEMU/KVM installed successfully.${NC}"
    else
        echo -e "${COLOR_RED}This feature currently only supports Ubuntu/Debian.${NC}"
        return
    fi
    
    # Create VM directory
    VM_DIR="/var/lib/libvirt/images"
    sudo mkdir -p "$VM_DIR"
    
    # Download ISO
    show_loading "Downloading ${OS_NAME} ISO (this may take several minutes)..."
    ISO_FILE="${VM_DIR}/${VM_NAME}.iso"
    sudo curl -L "$ISO_URL" -o "$ISO_FILE" 2>&1 | grep -oP '\d+%' | tail -1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Failed to download ISO.${NC}"
        return
    fi
    
    echo -e "${COLOR_GREEN}ISO downloaded successfully.${NC}"
    
    # Create virtual disk
    show_loading "Creating virtual disk (${VM_DISK}GB)..."
    DISK_FILE="${VM_DIR}/${VM_NAME}.qcow2"
    sudo qemu-img create -f qcow2 "$DISK_FILE" ${VM_DISK}G > /dev/null 2>&1
    
    echo -e "${COLOR_GREEN}Virtual disk created.${NC}"
    
    # Create VM
    show_loading "Creating virtual machine..."
    
    sudo virt-install \
        --name "$VM_NAME" \
        --ram $((VM_RAM * 1024)) \
        --vcpus "$VM_CPU" \
        --disk path="$DISK_FILE",format=qcow2 \
        --cdrom "$ISO_FILE" \
        --os-variant generic \
        --network network=default \
        --graphics vnc,listen=0.0.0.0,port=5902 \
        --noautoconsole > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Failed to create VM.${NC}"
        return
    fi
    
    PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "your-server-ip")
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "tailscale-not-configured")
    
    echo -e "\n${COLOR_GREEN}=== Virtual Machine Created Successfully! ===${NC}"
    echo -e "${COLOR_CYAN}VM Name: ${VM_NAME}${NC}"
    echo -e "${COLOR_CYAN}OS: ${OS_NAME}${NC}"
    echo -e "${COLOR_CYAN}RAM: ${VM_RAM}GB${NC}"
    echo -e "${COLOR_CYAN}Disk: ${VM_DISK}GB${NC}"
    echo -e "${COLOR_CYAN}CPUs: ${VM_CPU}${NC}"
    
    echo -e "\n${COLOR_YELLOW}--- VNC Access (for OS installation) ---${NC}"
    echo -e "${COLOR_CYAN}  Port: 5902${NC}"
    echo -e "${COLOR_CYAN}  Public IP: ${PUBLIC_IP}:5902${NC}"
    echo -e "${COLOR_CYAN}  Tailscale IP: ${TS_IP}:5902${NC}"
    echo -e "${COLOR_YELLOW}  Use VNC Viewer to connect and complete OS installation${NC}"
    
    echo -e "\n${COLOR_YELLOW}--- VM Management Commands ---${NC}"
    echo -e "${COLOR_CYAN}  Start VM: sudo virsh start ${VM_NAME}${NC}"
    echo -e "${COLOR_CYAN}  Stop VM: sudo virsh shutdown ${VM_NAME}${NC}"
    echo -e "${COLOR_CYAN}  Delete VM: sudo virsh undefine ${VM_NAME} --remove-all-storage${NC}"
    echo -e "${COLOR_CYAN}  List VMs: sudo virsh list --all${NC}"
}

# ===============================================
# === 8. Change Theme ===
# ===============================================
change_theme() {
    detect_os || return

    title_echo "PTERODACTYL THEME MANAGER"
    
    if [ ! -d "$SERVER_DIR" ]; then
        echo -e "${COLOR_RED}Pterodactyl Panel not found. Install Panel first (Option 3).${NC}"
        return
    fi
    
    echo -e "\n${COLOR_CYAN}--- Available Themes ---${NC}"
    echo -e "  1. Slate (Dark Modern Theme)"
    echo -e "  2. Twilight (Purple/Blue Theme)"
    echo -e "  3. Minecraft Theme"
    echo -e "  4. Cancel"

    read -p "Enter your choice (1-4): " THEME_CHOICE

    case $THEME_CHOICE in
        1) 
            THEME_NAME="Slate"
            THEME_CMD="cd ${SERVER_DIR} && curl -L https://raw.githubusercontent.com/Ferks-FK/Pterodactyl-AutoThemes/main/install.sh | bash -s -- slate"
            ;;
        2) 
            THEME_NAME="Twilight"
            THEME_CMD="cd ${SERVER_DIR} && curl -L https://raw.githubusercontent.com/Ferks-FK/Pterodactyl-AutoThemes/main/install.sh | bash -s -- twilight"
            ;;
        3) 
            THEME_NAME="Minecraft"
            THEME_CMD="cd ${SERVER_DIR} && curl -L https://raw.githubusercontent.com/Ferks-FK/Pterodactyl-AutoThemes/main/install.sh | bash -s -- minecraft"
            ;;
        4) 
            echo -e "${COLOR_YELLOW}Theme installation cancelled.${NC}"
            return
            ;;
        *) 
            echo -e "${COLOR_RED}Invalid choice.${NC}"
            return
            ;;
    esac

    show_loading "Installing ${THEME_NAME} theme..."
    
    eval $THEME_CMD 2>&1 | tail -n 10
    
    if [ $? -eq 0 ]; then
        echo -e "${COLOR_GREEN}${THEME_NAME} theme installed!${NC}"
        echo -e "${COLOR_YELLOW}   Refresh your browser to see the new theme.${NC}"
    else
        echo -e "${COLOR_RED}Theme installation failed.${NC}"
    fi
}

# ===============================================
# === 8. Uninstall ===
# ===============================================
uninstall_components() {
    detect_os || return

    title_echo "COMPONENT UNINSTALLER"
    
    echo -e "\n${COLOR_CYAN}--- What do you want to remove? ---${NC}"
    echo -e "  1. Panel (Pterodactyl Panel)"
    echo -e "  2. Wings (Daemon)"
    echo -e "  3. BluePrint"
    echo -e "  4. Tailscale"
    echo -e "  5. Cloudflare Tunnel"
    echo -e "  6. Docker"
    echo -e "  7. Back to Main Menu"

    read -p "Enter your choice (1-7): " REMOVE_CHOICE

    case $REMOVE_CHOICE in
        1)
            show_loading "Removing Pterodactyl Panel..."
            sudo systemctl stop nginx 2>/dev/null
            sudo rm -rf "$SERVER_DIR" 
            sudo rm -f /etc/nginx/sites-enabled/pterodactyl.conf
            sudo rm -f /etc/nginx/sites-available/pterodactyl.conf
            sudo systemctl start nginx 2>/dev/null
            sudo mysql -e "DROP DATABASE IF EXISTS pterodactyl;" 2>/dev/null
            sudo mysql -e "DROP USER IF EXISTS 'pterodactyl_user'@'127.0.0.1';" 2>/dev/null
            echo -e "${COLOR_GREEN}Panel removed.${NC}"
            ;;
        2)
            show_loading "Removing Wings..."
            sudo systemctl stop wings 2>/dev/null
            sudo systemctl disable wings 2>/dev/null
            sudo rm -f /etc/systemd/system/wings.service
            sudo rm -rf "$WINGS_DIR"
            sudo rm -f /usr/local/bin/wings
            sudo systemctl daemon-reload
            echo -e "${COLOR_GREEN}Wings removed.${NC}"
            ;;
        3)
            show_loading "Removing BluePrint..."
            cd "$SERVER_DIR" 2>/dev/null && sudo bash blueprint.sh -remove 2>&1 | tail -n 5
            echo -e "${COLOR_GREEN}BluePrint removed.${NC}"
            ;;
        4)
            show_loading "Removing Tailscale..."
            sudo tailscale down 2>/dev/null
            sudo apt remove --purge -y tailscale > /dev/null 2>&1
            echo -e "${COLOR_GREEN}Tailscale removed.${NC}"
            ;;
        5)
            show_loading "Removing Cloudflare Tunnel..."
            sudo systemctl stop cloudflared 2>/dev/null
            sudo systemctl disable cloudflared 2>/dev/null
            sudo apt remove --purge -y cloudflared > /dev/null 2>&1
            sudo rm -rf /root/.cloudflared
            echo -e "${COLOR_GREEN}Cloudflare Tunnel removed.${NC}"
            ;;
        6)
            show_loading "Removing Docker..."
            sudo apt remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
            sudo rm -rf /var/lib/docker
            echo -e "${COLOR_GREEN}Docker removed.${NC}"
            ;;
        7) return ;;
        *) echo -e "${COLOR_RED}Invalid choice.${NC}" ;;
    esac
}

# ===============================================
# === 9. System Info ===
# ===============================================
show_system_info() {
    title_echo "SYSTEM INFORMATION"
    
    detect_os

    echo -e "\n${COLOR_CYAN}--- Hardware & Core System ---${NC}"
    CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[[:space:]]*//')
    echo -e "${COLOR_YELLOW}  CPU: ${NC}${CPU_MODEL}"
    
    GPU_MODEL=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | sed 's/.*: //' | head -n 1)
    echo -e "${COLOR_YELLOW}  GPU: ${NC}${GPU_MODEL:-N/A}"
    
    RAM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
    RAM_USED=$(free -h | awk '/^Mem:/ {print $3}')
    echo -e "${COLOR_YELLOW}  RAM: ${NC}${RAM_USED} / ${RAM_TOTAL}"
    
    echo -e "\n${COLOR_CYAN}--- Storage ---${NC}"
    DISK_INFO=$(df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 " used)"}')
    echo -e "${COLOR_YELLOW}  Root Disk: ${NC}${DISK_INFO}"

    echo -e "\n${COLOR_CYAN}--- Network ---${NC}"
    PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "Unable to fetch")
    echo -e "${COLOR_YELLOW}  Public IP: ${NC}${PUBLIC_IP}"
    
    LOCATION=$(curl -s --max-time 3 ipinfo.io/country 2>/dev/null || echo "Unknown")
    echo -e "${COLOR_YELLOW}  Location: ${NC}${LOCATION}"
    
    echo -e "\n${COLOR_CYAN}--- Services Status ---${NC}"
    
    if command -v tailscale &>/dev/null; then
        if tailscale status &>/dev/null 2>&1 | grep -q "Logged in"; then
            TS_IP=$(tailscale ip -4 2>/dev/null)
            echo -e "${COLOR_GREEN}  Tailscale: ${NC}Active (${TS_IP})"
        else
            echo -e "${COLOR_YELLOW}  Tailscale: ${NC}Installed but not connected"
        fi
    else
        echo -e "${COLOR_RED}  Tailscale: ${NC}Not Installed"
    fi
    
    if command -v cloudflared &>/dev/null; then
        if sudo systemctl is-active --quiet cloudflared 2>/dev/null; then
            echo -e "${COLOR_GREEN}  Cloudflared: ${NC}Running"
        else
            echo -e "${COLOR_YELLOW}  Cloudflared: ${NC}Installed but not running"
        fi
    else
        echo -e "${COLOR_RED}  Cloudflared: ${NC}Not Installed"
    fi
    
    if command -v docker &>/dev/null; then
        if sudo systemctl is-active --quiet docker 2>/dev/null; then
            echo -e "${COLOR_GREEN}  Docker: ${NC}Running"
        else
            echo -e "${COLOR_YELLOW}  Docker: ${NC}Installed but not running"
        fi
    else
        echo -e "${COLOR_RED}  Docker: ${NC}Not Installed"
    fi
    
    if [ -d "$SERVER_DIR" ]; then
        echo -e "${COLOR_GREEN}  Pterodactyl Panel: ${NC}Installed"
    else
        echo -e "${COLOR_RED}  Pterodactyl Panel: ${NC}Not Installed"
    fi
    
    if [ -f "/usr/local/bin/wings" ]; then
        if sudo systemctl is-active --quiet wings 2>/dev/null; then
            echo -e "${COLOR_GREEN}  Wings: ${NC}Running"
        else
            echo -e "${COLOR_YELLOW}  Wings: ${NC}Installed but not running"
        fi
    else
        echo -e "${COLOR_RED}  Wings: ${NC}Not Installed"
    fi
    
    echo -e "\n${COLOR_CYAN}--- Current User ---${NC}"
    echo -e "${COLOR_YELLOW}  Username: ${NC}$(whoami)"
    echo -e "${COLOR_YELLOW}  Home Directory: ${NC}$HOME"
}

# ===============================================
# === Main Menu ===
# ===============================================
main_menu() {
    if [ -z "$INITIAL_RUN_COMPLETE" ]; then
        clear
        echo -e "${COLOR_CYAN}${ZMC_ART}${NC}"
        echo -e "${COLOR_GREEN}Version: ${SH_VERSION}${NC}"
        echo -e "${COLOR_CYAN}Author: Claude (Anthropic)${NC}\n"
        INITIAL_RUN_COMPLETE="true"
    fi

    while true; do
        echo -e "${COLOR_CYAN}=======================================${NC}"
        echo -e "${COLOR_CYAN}🚀 Universal Server Management Menu 🚀${NC}"
        echo -e "${COLOR_CYAN}=======================================${NC}\n"
        
        echo -e "Select an option:"
        echo -e "  1. ${COLOR_GREEN}Update${NC} - System Updates"
        echo -e "  2. ${COLOR_GREEN}Tailscale${NC} - VPN/Networking"
        echo -e "  3. ${COLOR_BLUE}Panel${NC} - Pterodactyl Web Interface"
        echo -e "  4. ${COLOR_BLUE}Wings${NC} - Pterodactyl Node Daemon"
        echo -e "  5. ${COLOR_BLUE}BluePrint${NC} - Pterodactyl Extension"
        echo -e "  6. ${COLOR_CYAN}Cloudflare${NC} - Tunnel Setup"
        echo -e "  7. ${COLOR_PURPLE}RDP/VNC${NC} - Remote Desktop Setup"
        echo -e "  8. ${COLOR_CYAN}Change Theme${NC} - Panel Theme"
        echo -e "  9. ${COLOR_RED}Uninstall${NC} - Remove Components"
        echo -e " 10. ${COLOR_YELLOW}System Info${NC} - Diagnostics"
        echo -e "  0. ${COLOR_RED}Exit${NC}\n"
        
        read -p "Enter your choice (0-10): " main_choice

        case $main_choice in
            1) clear; update_system; post_execution_pause ;;
            2) clear; install_tailscale; post_execution_pause ;;
            3) clear; install_panel; post_execution_pause ;;
            4) clear; install_wings; post_execution_pause ;;
            5) clear; install_blueprint; post_execution_pause ;;
            6) clear; install_cloudflare_tunnel; post_execution_pause ;;
            7) clear; install_rdp_vnc; post_execution_pause ;;
            8) clear; change_theme; post_execution_pause ;;
            9) clear; uninstall_components; post_execution_pause ;;
            10) clear; show_system_info; post_execution_pause ;;
            0) 
                title_echo "EXITING INSTALLER"
                echo -e "${COLOR_CYAN}Thanks for using ${BRANDING}! Goodbye! 👋${NC}"
                exit 0 
                ;;
            *) echo -e "${COLOR_RED}Invalid choice. Please enter 0-10.${NC}" ;;
        esac
    done
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${COLOR_RED}Please run this script as root or with sudo${NC}"
    exit 1
fi

main_menu
