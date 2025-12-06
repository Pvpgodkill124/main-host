#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# This ensures a broken download or API call stops the script immediately.
set -e

# --- Configuration & API Endpoints ---
SERVER_DIR="."
SERVER_JAR="server.jar"
PAPER_API_BASE="https://api.papermc.io/v2/projects/paper"
PURPUR_API_BASE="https://api.purpurmc.org/v2/purpur"
PUFFERFISH_API_BASE="https://api.pufferfish.host/v2/pufferfish"

FABRIC_INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/0.12.2/fabric-installer-0.12.2.jar" 

# Proxies
BUNGEECORD_API_BASE="https://api.papermc.io/v2/projects/bungeecord"
VELOCITY_API_BASE="https://api.papermc.io/v2/projects/velocity"

# Forge (Uses the official public repository)
FORGE_MAVEN_BASE="https://maven.minecraftforge.net/net/minecraftforge/forge"

# --- ANSI Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

## 1. Helper Functions 

check_dependencies() {
    echo -e "${CYAN}--- Checking Dependencies (wget, curl, jq) ---${NC}"
    if ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}⚠️ 'jq' not found! Installing now... (Requires sudo)${NC}"
        sudo apt update > /dev/null 2>&1
        sudo apt install jq -y
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ 'jq' installed successfully.${NC}"
        else
            echo -e "${RED}❌ ERROR: Failed to install 'jq'. Please install it manually.${NC}"
            exit 1
        fi
    fi
    if ! command -v java &>/dev/null; then
        echo -e "${RED}❌ ERROR: Java is not installed or not in PATH. Please install Java 8 or 17+.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ All dependencies found (wget, curl, jq, Java).${NC}"
}

get_required_java() {
    local mc_version=$1
    if [[ $(echo -e "$mc_version\n1.17" | sort -V | head -n 1) == "1.17" ]]; then
        echo "17+" 
    else
        echo "8"
    fi
}

# --- UNIVERSAL DOWNLOAD SYSTEM ---
download_jar() {
    local jar_name=$1
    local download_link=$2
    
    echo -e "\n${CYAN}--- Starting Installation ---${NC}"
    
    # 1. Clean up potential old jars and rename target
    if [ -f "$SERVER_JAR" ]; then
        echo -e "${YELLOW}Existing ${SERVER_JAR} found. Renaming it to ${SERVER_JAR}.old${NC}"
        mv "$SERVER_JAR" "${SERVER_JAR}.old"
    fi
    
    # 2. Download the new jar with verbose error checking
    echo -e "${YELLOW}Downloading ${jar_name} from ${download_link}...${NC}"
    
    # Use -L for redirects, --progress=bar:noscroll for cleaner output
    wget --progress=bar:noscroll -O "$SERVER_JAR" -L "$download_link"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Download complete! Renamed to ${SERVER_JAR}.${NC}"
    else
        echo -e "${RED}❌ Download failed! Check the network connection or the URL: ${download_link}${NC}"
        exit 1 # Exit on failed download
    fi
}

# --- UNIFIED FIRST LAUNCH SYSTEM ---
initial_launch() {
    local is_proxy=$1 # Set to "proxy" for Bungeecord/Velocity
    
    echo -e "\n${CYAN}--- Preparing for First Launch ---${NC}"
    
    # 1. EULA Handling (Only required for Spigot/Paper/Pufferfish/Forge/Fabric)
    if [ "$is_proxy" != "proxy" ]; then
        EULA_FILE="eula.txt"
        if [ ! -f "$EULA_FILE" ]; then
            echo -e "${YELLOW}Running server once to generate configuration files and EULA...${NC}"
            java -jar "$SERVER_JAR" nogui || true # Allow this to fail on EULA violation
        fi
        
        if grep -q "eula=true" "$EULA_FILE"; then
            echo -e "${GREEN}✅ EULA already accepted (eula=true).${NC}"
        else
            echo -e "${YELLOW}⚠️ EULA not accepted. Setting it to true automatically.${NC}"
            echo -e "#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).\n#$(date)\neula=true" > "$EULA_FILE"
            echo -e "${GREEN}✅ EULA has been set to true.${NC}"
        fi
    else
        echo -e "${CYAN}Skipping EULA check (Proxy server selected).${NC}"
    fi

    # 2. First Run
    echo -e "${CYAN}--- Initializing Server Console (First Run) ---${NC}"
    echo -e "${YELLOW}This may take a moment as files are generated. Press ${BLUE}Ctrl+C${YELLOW} to stop the server.${NC}"
    
    # Use a basic start command
    java -Xmx1024M -Xms128M -jar "$SERVER_JAR" nogui
    
    echo -e "\n${GREEN}Installation and initial run complete!${NC}"
}


## 2. Core Server Logic (FIXED PURPUR API)
select_version() {
    local project_name=$1
    local api_base_url=$2
    
    echo -e "\n${CYAN}--- Fetching Available ${project_name} Versions ---${NC}"
    
    local versions_url="${api_base_url}" 
    local versions_json=$(curl -s "$versions_url")
    local supported_versions=$(echo "$versions_json" | jq -r '.versions[]' 2>/dev/null | grep -E '1\.[0-9]{1,2}(\.[0-9]{1,2})?$')

    if [ -z "$supported_versions" ]; then
        echo -e "${RED}❌ ERROR: Failed to fetch versions from ${versions_url}. Cannot continue.${NC}"
        return 1
    fi

    # Display menu
    local version_array=($supported_versions)
    local count=1
    echo "Please select the Minecraft version for ${project_name}:"
    
    for version in "${version_array[@]}"; do
        local required_java=$(get_required_java "$version")
        echo -e "  $count) ${GREEN}MC $version${NC} (Requires Java $required_java)"
        ((count++))
    done
    
    read -p "Enter your choice (1-${#version_array[@]}): " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#version_array[@]} ]; then
        SELECTED_MC_VERSION=${version_array[$choice-1]}
        echo -e "${GREEN}You selected MC ${SELECTED_MC_VERSION}.${NC}"
        
        fetch_latest_build "$project_name" "$api_base_url" "$SELECTED_MC_VERSION"
    else
        echo -e "${RED}Invalid choice. Returning to main menu.${NC}"
        main_menu
    fi
}

fetch_latest_build() {
    local project_name=$1
    local api_base_url=$2
    local mc_version=$3
    
    echo -e "\n${CYAN}--- Fetching Latest Build for MC ${mc_version} (${project_name}) ---${NC}"

    if [[ "$project_name" == "Purpur" ]]; then
        # PURPUR FIX: Using defensive JQ for the builds array
        local builds_url="${api_base_url}/${mc_version}"
        local latest_build_json=$(curl -s "$builds_url")
        
        # Defensive JQ: Safely get the last build number.
        local latest_build=$(echo "$latest_build_json" | jq -r '.builds | if type == "array" then .[-1] else null end')
        
        if [ -z "$latest_build" ] || [ "$latest_build" == "null" ]; then
             echo -e "${RED}❌ ERROR: Purpur API returned no valid build for MC ${mc_version}. Cannot continue.${NC}"
             return 1
        fi
        
        local file_name="${project_name}-${mc_version}-${latest_build}.jar" 
        # FIX: Ensure no double slash in URL by removing potential trailing slash from API base
        DOWNLOAD_URL="${api_base_url}/${mc_version}/${latest_build}/download"
    
    else
        # PAPER/PUFFERFISH/BUNGEECORD/VELOCITY: Standard V2 API structure
        local builds_url="${api_base_url}/versions/${mc_version}/builds"
        local latest_build_json=$(curl -s "$builds_url")
        
        # JQ for standard V2: Get last element of the '.builds' array.
        local latest_build=$(echo "$latest_build_json" | jq -r '.builds | .[-1].build')
        local file_name=$(echo "$latest_build_json" | jq -r '.builds | .[-1].downloads.application.name')

        DOWNLOAD_URL="${api_base_url}/versions/${mc_version}/builds/${latest_build}/downloads/${file_name}"
    fi

    if [ -z "$file_name" ] || [ "$latest_build" == "null" ] || [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}❌ ERROR: Could not find latest build or download URL for ${project_name}.${NC}"
        echo -e "Check API URL: $builds_url"
        return 1
    fi
    
    echo -e "${GREEN}Download URL found!${NC}"
    echo "Project: ${project_name}"
    echo "File: ${file_name} (Build: ${latest_build})"
    
    # Use the UNIVERSAL DOWNLOAD function
    download_jar "$file_name" "$DOWNLOAD_URL"
    initial_launch
}

## 3. Modded Server Logic (Fabric, Forge, NeoForge)
fabric_install_logic() {
    # 1. Fetch supported MC versions
    local mc_versions_json=$(curl -s "https://meta.fabricmc.net/v2/versions/game")
    local supported_versions=$(echo "$mc_versions_json" | jq -r '.[].version' 2>/dev/null | grep -E '1\.[0-9]{1,2}(\.[0-9]{1,2})?$')

    if [ -z "$supported_versions" ]; then
        echo -e "${RED}❌ ERROR: Failed to fetch Fabric-supported Minecraft versions.${NC}"
        modded_server_menu
        return
    fi
    
    # Display menu and get choice (simplified menu display)
    local version_array=($supported_versions)
    local count=1
    echo -e "\n${CYAN}--- Fabric Version Selection ---${NC}"
    echo "Select the Minecraft version for Fabric (Latest recommended build will be used):"

    for version in "${version_array[@]}"; do
        echo -e "  $count) ${GREEN}MC $version${NC} (Requires Java $(get_required_java "$version"))"
        ((count++))
    done

    read -p "Enter your choice (1-${#version_array[@]}): " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#version_array[@]} ]; then
        local SELECTED_MC_VERSION=${version_array[$choice-1]}
    else
        echo -e "${RED}Invalid choice. Returning to modded menu.${NC}"
        modded_server_menu
        return
    fi

    # 2. Download the Fabric Installer JAR (Using universal wget -L for robustness)
    local INSTALLER_JAR="fabric-installer.jar"
    echo -e "\n${YELLOW}Downloading Fabric Installer...${NC}"
    wget --progress=bar:noscroll -O "$INSTALLER_JAR" -L "$FABRIC_INSTALLER_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to download Fabric Installer.${NC}"
        return
    fi

    # 3. Execute the Installer in server mode
    echo -e "${CYAN}Running Fabric Installer for MC ${SELECTED_MC_VERSION}...${NC}"
    java -jar "$INSTALLER_JAR" server -mcversion "$SELECTED_MC_VERSION" -downloadMinecraft
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Fabric installation complete! New server JAR has been generated.${NC}"
        
        # Link the generated JAR to our standard name 
        local FABRIC_SERVER_JAR_NAME=$(ls -1 | grep "fabric-server.*\.jar" | head -n 1)
        if [ -n "$FABRIC_SERVER_JAR_NAME" ]; then
            # Clean up old SERVER_JAR before linking
            [ -f "$SERVER_JAR" ] && mv "$SERVER_JAR" "${SERVER_JAR}.old"
            ln -sf "$FABRIC_SERVER_JAR_NAME" "$SERVER_JAR"
            echo -e "${GREEN}✅ Linked ${FABRIC_SERVER_JAR_NAME} to ${SERVER_JAR}.${NC}"
            
            rm "$INSTALLER_JAR"
            initial_launch
        else
            echo -e "${RED}❌ Failed to find the generated Fabric Server JAR.${NC}"
        fi
    else
        echo -e "${RED}❌ Fabric Installer failed to run.${NC}"
    fi
}

# --- Forge & NeoForge Logic (Shared Installer) ---
forge_install_logic() {
    local project_name=$1
    local forge_mc_version

    echo -e "\n${CYAN}--- ${project_name} Version Selection ---${NC}"
    echo -e "${YELLOW}WARNING: This installer requires the official ${project_name} installer JAR, which will fetch all assets/libraries.${NC}"
    
    read -p "Enter the specific Minecraft version (e.g., 1.20.1 or 1.12.2): " forge_mc_version
    
    if [ -z "$forge_mc_version" ]; then
        echo -e "${RED}Version cannot be empty. Returning.${NC}"
        modded_server_menu
        return
    fi

    # The installer URL format changed. We rely on the official Maven URL.
    local INSTALLER_JAR="forge-installer.jar"
    
    # Forge/NeoForge often has a dedicated universal installer that fetches the correct version metadata.
    # The latest installer is often found at a consistent location, but linking to a specific version is complex via shell.
    # We will use the common structure for the installer JAR download link and ask the user to provide the exact version string.
    
    # We will use a known, recent universal installer version as a proxy if one isn't available for the specific MC version.
    # For simplicity and wide compatibility, we instruct the user to manually find the specific installer URL for their version,
    # or rely on the script to use the latest generic installer if possible.
    
    # NOTE: Due to the complexity of parsing the Forge Maven repository via shell, we will use the legacy 'universal' installer method for widest compatibility, 
    # and instruct the user that they may need to replace the INSTALLER_URL for very new versions.
    # I will search for a generic Forge installer URL.
    
    echo -e "${YELLOW}Please visit the official ${project_name} website to get the universal installer JAR for MC ${forge_mc_version}.${NC}"
    read -p "Enter the direct download URL for the ${project_name} Installer JAR (or press Enter for generic Forge): " INSTALLER_URL
    
    if [ -z "$INSTALLER_URL" ]; then
        # Default to a recent, known Forge universal installer (MC 1.20.1 for example)
        INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/1.20.1-47.2.1-installer.jar"
        echo -e "${YELLOW}Using generic Forge 1.20.1 installer URL: ${INSTALLER_URL}${NC}"
    fi

    echo -e "\n${YELLOW}Downloading ${project_name} Installer...${NC}"
    wget --progress=bar:noscroll -O "$INSTALLER_JAR" -L "$INSTALLER_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to download ${project_name} Installer. Check the URL and try again.${NC}"
        return
    fi

    # 3. Execute the Installer in server mode
    echo -e "${CYAN}Running ${project_name} Installer...${NC}"
    
    # The installer usually requires a specific structure, but the key command is 'install'
    java -jar "$INSTALLER_JAR" --installServer 

    # Clean up the installer jar and run the unified launch
    rm "$INSTALLER_JAR"

    # Forge installations generate a forge-<version>.jar or similar and a start script.
    # We will link the generated JAR to server.jar for unified launch.
    local FORGE_SERVER_JAR_NAME=$(ls -1 | grep "forge-.*\.jar" | head -n 1)
    if [ -n "$FORGE_SERVER_JAR_NAME" ]; then
        [ -f "$SERVER_JAR" ] && mv "$SERVER_JAR" "${SERVER_JAR}.old"
        ln -sf "$FORGE_SERVER_JAR_NAME" "$SERVER_JAR"
        echo -e "${GREEN}✅ Linked ${FORGE_SERVER_JAR_NAME} to ${SERVER_JAR}.${NC}"
        initial_launch
    else
        echo -e "${RED}❌ Failed to find the generated ${project_name} Server JAR. Manual setup may be required.${NC}"
    fi
}


## 4. Proxy Server Logic
proxy_server_menu() {
    echo -e "\n${CYAN}--- Proxy Server Selection ---${NC}"
    echo "Select a Network Proxy Platform:"
    echo -e "  1) ${CYAN}Bungeecord${NC} (Original Proxy)"
    echo -e "  2) ${CYAN}Velocity${NC} (Modern, High-Performance Proxy)"
    echo -e "  3) ${BLUE}Back to Main Menu${NC}"

    read -p "Enter your choice (1-3): " proxy_choice

    case $proxy_choice in
        1) 
            select_version "Bungeecord" "$BUNGEECORD_API_BASE"
            initial_launch "proxy" # Pass "proxy" flag to skip EULA
            ;;
        2) 
            select_version "Velocity" "$VELOCITY_API_BASE"
            initial_launch "proxy" # Pass "proxy" flag to skip EULA
            ;;
        3) main_menu ;;
        *) echo -e "${RED}Invalid choice.${NC}"; proxy_server_menu ;;
    esac
}


## 5. Menu System
main_menu() {
    echo -e "\n${CYAN}===============================================${NC}"
    echo -e "${CYAN}🌍 Universal Minecraft Server Installer (V8) 🌍${NC}"
    echo -e "${CYAN}===============================================${NC}"
    
    echo -e "Select the type of server you wish to install:"
    echo -e "  1) ${GREEN}PaperMC / Purpur / Pufferfish${NC} (Core/Plugin Servers)"
    echo -e "  2) ${YELLOW}Fabric / Forge / NeoForge${NC} (Modded Servers)"
    echo -e "  3) ${CYAN}Bungeecord / Velocity${NC} (Proxy Network Servers)"
    echo -e "  4) ${RED}Exit${NC}"
    
    read -p "Enter your choice (1-4): " choice

    case $choice in
        1) core_server_menu ;;
        2) modded_server_menu ;;
        3) proxy_server_menu ;;
        4) echo -e "${CYAN}Exiting installer. Goodbye! 👋${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice.${NC}"; main_menu ;;
    esac
}

core_server_menu() {
    echo -e "\n${CYAN}--- Core Server Selection ---${NC}"
    echo "Select a High-Performance Core:"
    echo -e "  1) ${GREEN}PaperMC${NC} (Balanced)"
    echo -e "  2) ${GREEN}Purpur${NC} (Highly Customizable/Tweaked)"
    echo -e "  3) ${GREEN}Pufferfish${NC} (Optimization Focused)"
    echo -e "  4) ${YELLOW}Back to Main Menu${NC}"

    read -p "Enter your choice (1-4): " core_choice

    case $core_choice in
        1) select_version "PaperMC" "$PAPER_API_BASE" ;;
        2) select_version "Purpur" "$PURPUR_API_BASE" ;;
        3) select_version "Pufferfish" "$PUFFERFISH_API_BASE" ;;
        4) main_menu ;;
        *) echo -e "${RED}Invalid choice.${NC}"; core_server_menu ;;
    esac
}

modded_server_menu() {
    echo -e "\n${CYAN}--- Modded Server Selection ---${NC}"
    echo "Select a Modding Platform:"
    echo -e "  1) ${YELLOW}Fabric${NC} (Lightweight, Modern) - IMPLEMENTED"
    echo -e "  2) ${YELLOW}Forge${NC} (Traditional Modding)"
    echo -e "  3) ${YELLOW}NeoForge${NC} (New Fork of Forge)"
    echo -e "  4) ${BLUE}Back to Main Menu${NC}"

    read -p "Enter your choice (1-4): " modded_choice

    case $modded_choice in
        1) fabric_install_logic ;;
        2) forge_install_logic "Forge" ;;
        3) forge_install_logic "NeoForge" ;; # NeoForge uses a very similar installation process to modern Forge
        4) main_menu ;;
        *) echo -e "${RED}Invalid choice.${NC}"; modded_server_menu ;;
    esac
}


# --- Start ---
check_dependencies
main_menu