#!/bin/bash

# --- ANSI Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuration for JDK Downloads ---
INSTALL_DIR="/opt/java"
declare -A JAVA_VERSIONS
JAVA_VERSIONS=(
    [8]="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u431-b07/OpenJDK8U-jdk_x64_linux_hotspot_8u431b07.tar.gz"
    [17]="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.11_9.tar.gz"
    [21]="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.3_9.tar.gz"
    [25]="https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.1%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.1_8.tar.gz"
)

# --- UTILITY FUNCTIONS ---

## 1. Dependency Check (Hotfix for $PATH Issue)
check_dependencies() {
    echo -e "${CYAN}--- Checking Dependencies (wget, tar) ---${NC}"
    
    # HOTFIX: Check for binaries in the standard location directly.
    # If they exist, add /usr/bin to the PATH for this script's session only.
    if [ -f /usr/bin/wget ] && [ -f /usr/bin/tar ]; then
        export PATH="/usr/bin:$PATH"
        echo -e "${GREEN}✅ wget and tar found in /usr/bin/. Path adjusted.${NC}"
    elif command -v wget &>/dev/null && command -v tar &>/dev/null; then
        echo -e "${GREEN}✅ wget and tar found via \$PATH.${NC}"
    else
        echo -e "${RED}❌ ERROR: 'wget' or 'tar' not found. ${NC}"
        echo -e "Please install them: '${YELLOW}sudo apt update && sudo apt install wget tar${NC}'"
        exit 1
    fi
}

## 2. Java Installation Core Logic
install_java() {
    VERSION=$1
    URL=${JAVA_VERSIONS[$VERSION]}
    EXTRACT_NAME="jdk-$VERSION"
    FILE_NAME=$(basename "$URL")
    TEMP_FILE="/tmp/$FILE_NAME"
    TEMP_EXTRACT_DIR="/tmp/$EXTRACT_NAME-extract"
    JAVA_HOME_PATH="$INSTALL_DIR/$EXTRACT_NAME"
    
    if [ -z "$URL" ]; then
        echo -e "${RED}❌ ERROR: Invalid version selected or URL missing.${NC}"
        return 1
    fi
    
    echo -e "\n${CYAN}--- Installing Java $VERSION ---${NC}"
    sudo mkdir -p "$INSTALL_DIR"
    
    # --- Download ---
    echo -e "${YELLOW}Downloading $FILE_NAME...${NC}"
    sudo wget -q --show-progress -L -O "$TEMP_FILE" "$URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Download failed! Check URL or network connection.${NC}"
        return 1
    fi

    # --- Extraction and Move ---
    echo -e "${YELLOW}Extracting and preparing Java environment...${NC}"
    sudo rm -rf "$TEMP_EXTRACT_DIR" 2>/dev/null
    sudo mkdir -p "$TEMP_EXTRACT_DIR"
    
    sudo tar -xzf "$TEMP_FILE" -C "$TEMP_EXTRACT_DIR"
    
    # Find the top-level directory inside the tarball
    EXTRACTED_DIR=$(sudo find "$TEMP_EXTRACT_DIR" -maxdepth 1 -mindepth 1 -type d | head -n 1)
    
    if [ -z "$EXTRACTED_DIR" ]; then
        echo -e "${RED}❌ ERROR: Failed to find extracted JDK directory.${NC}"
        sudo rm "$TEMP_FILE"
        sudo rm -rf "$TEMP_EXTRACT_DIR"
        return 1
    fi
    
    sudo rm -rf "$JAVA_HOME_PATH" 2>/dev/null
    
    # Move extracted content to the final standardized location: /opt/java/jdk-VERSION
    sudo mv "$EXTRACTED_DIR" "$JAVA_HOME_PATH"

    echo -e "${GREEN}✅ Installation path: $JAVA_HOME_PATH${NC}"
    
    # --- Register with update-alternatives ---
    echo -e "${YELLOW}Registering with update-alternatives...${NC}"
    BIN_PATH="$JAVA_HOME_PATH/bin/java"
    JAVAC_PATH="$JAVA_HOME_PATH/bin/javac"
    PRIORITY=$((VERSION * 10)) 
    
    sudo update-alternatives --remove java "$BIN_PATH" 2>/dev/null
    sudo update-alternatives --remove javac "$JAVAC_PATH" 2>/dev/null

    sudo update-alternatives --install "/usr/bin/java" "java" "$BIN_PATH" $PRIORITY
    sudo update-alternatives --install "/usr/bin/javac" "javac" "$JAVAC_PATH" $PRIORITY

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Java $VERSION registered successfully.${NC}"
    else
        echo -e "${RED}❌ ERROR: Failed to register Java $VERSION alternative.${NC}"
    fi

    # --- Cleanup ---
    sudo rm "$TEMP_FILE"
    sudo rm -rf "$TEMP_EXTRACT_DIR" 2>/dev/null 
    echo -e "${CYAN}Temporary files cleaned up.${NC}"
}

## 3. Installation Menu
install_java_menu() {
    echo -e "\n${CYAN}--- Java Installation Menu ---${NC}"
    echo -e "Which version of Java would you like to ${GREEN}install${NC}?"
    echo "  1) Java 8  - Older MC (e.g., 1.12.2)"
    echo "  2) Java 17 - Modern MC (e.g., 1.18 - 1.20.5)"
    echo "  3) Java 21 - Latest MC (e.g., 1.20.6+)"
    echo "  4) Java 25 - Newest LTS (For future server versions)"
    echo -e "  5) ${YELLOW}Back to Main Menu${NC}"

    read -p "Enter your choice (1-5): " install_choice

    case $install_choice in
        1) install_java 8 ;;
        2) install_java 17 ;;
        3) install_java 21 ;;
        4) install_java 25 ;;
        5) return ;;
        *) echo -e "${RED}Invalid choice. Returning to installation menu.${NC}"; install_java_menu ;;
    esac
}

## 4. Switching Core Logic
set_alternative() {
    PATH_TO_SET=$1
    
    echo -e "${YELLOW}Switching default Java version... (requires sudo)${NC}"
    
    sudo update-alternatives --set java "$PATH_TO_SET"
    
    JAVAC_PATH=$(echo "$PATH_TO_SET" | sed 's/bin\/java/bin\/javac/')
    sudo update-alternatives --set javac "$JAVAC_PATH" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully switched default Java version.${NC}"
    else
        echo -e "${RED}❌ ERROR: Failed to switch Java version.${NC}"
    fi
}

## 5. Switching Menu (Refined path detection)
switch_java_menu() {
    echo -e "\n${CYAN}--- Java Switching Menu ---${NC}"
    
    mapfile -t JAVA_LIST < <(update-alternatives --query java 2>/dev/null | awk '/^Alternative:/ {print $2}')
    
    if [ ${#JAVA_LIST[@]} -eq 0 ]; then
        echo -e "${RED}❌ ERROR: No Java alternatives found. Did you install any versions?${NC}"
        return
    fi
    
    COUNTER=1
    echo "--- Available Java Versions ---"
    SELECTION_PATHS=()
    
    for path in "${JAVA_LIST[@]}"; do
        VERSION_NAME="Unknown"
        
        # Determine a friendly name for the version
        if [[ $path == *"/opt/java/jdk-"* ]]; then
            VERSION_NUM=$(echo "$path" | grep -oP 'jdk-\d+' | tr -d 'jdk-')
            VERSION_NAME="Java $VERSION_NUM (Custom Install)"
        elif [[ $path == *"/lib/jvm/"* ]]; then
            VERSION_NAME=$(basename "$(dirname "$path")" | sed 's/java-//' | sed 's/-openjdk//')
            VERSION_NAME="Java $VERSION_NAME (System)"
        fi
        
        STATUS=""
        if [[ $(readlink -f /etc/alternatives/java) == "$path" ]]; then
            STATUS=" ${GREEN}(Currently Active)${NC}"
        fi

        echo -e "  $COUNTER) ${CYAN}${VERSION_NAME}${NC}${STATUS}"
        SELECTION_PATHS+=("$path")
        ((COUNTER++))
    done

    echo -e "  $COUNTER) ${YELLOW}Back to Main Menu${NC}"

    read -p "Enter your choice (1-$COUNTER): " switch_choice

    if [[ "$switch_choice" -eq "$COUNTER" ]]; then
        return
    elif [[ "$switch_choice" -ge 1 && "$switch_choice" -lt "$COUNTER" ]]; then
        SELECTED_PATH=${SELECTION_PATHS[$switch_choice-1]}
        set_alternative "$SELECTED_PATH"
    else
        echo -e "${RED}Invalid choice. Returning to switching menu.${NC}"
        switch_java_menu
    fi
}

## 6. Main Menu
main_menu() {
    # Loop until user chooses to exit
    while true; do
        echo -e "\n${CYAN}===========================================${NC}"
        echo -e "${CYAN}🚀 Minecraft Java Version Manager 🚀${NC}"
        echo -e "${CYAN}===========================================${NC}"
        
        echo -e "Current Java Version: "
        if command -v java &>/dev/null; then
             java -version 2>&1 | head -n 1 | grep 'version' | awk '{print $3}' | tr -d '"' | sed 's/p$/+/g'
        else
            echo -e "${YELLOW}No default Java version found or active.${NC}"
        fi
        
        echo -e "Please select an action:"
        echo -e "  1) ${GREEN}Install a new Java Version ${NC}"
        echo -e "  2) ${YELLOW}Switch (Update) the current Java Version${NC}"
        echo -e "  3) ${RED}Exit${NC}"

        read -p "Enter your choice (1-3): " main_choice

        case $main_choice in
            1) install_java_menu ;;
            2) switch_java_menu ;;
            3) echo -e "${CYAN}Exiting Java Manager. Happy Server Hosting! ${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}" ;;
        esac
    done
} # <--- THIS IS THE MISSING CLOSURE

# --- Start the script ---
echo -e "\n${RED}!!! NOTE: Always run this script using 'bash java.sh' to avoid syntax errors !!!${NC}\n"
check_dependencies
main_menu