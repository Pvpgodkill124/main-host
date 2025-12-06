#!/bin/bash

# --- Configuration ---
MIN_RAM="16G"
MAX_RAM="24G"
SERVER_JAR="server.jar"

# --- ANSI Color Codes for Output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Function to check for Java ---
check_java() {
    echo -e "${CYAN}--- Checking Java Installation ---${NC}"
    if command -v java &>/dev/null; then
        echo -e "${GREEN}✅ Java is installed and ready.${NC}"
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        echo -e "${CYAN}   Version Detected: ${JAVA_VERSION}${NC}"
    else
        echo -e "${RED}❌ ERROR: Java is not found! Please install Java (JRE/JDK).${NC}"
        exit 1
    fi
}

# --- Function for Plugin Verification (Basic Check) ---
verify_plugins() {
    echo -e "${CYAN}--- Verifying Plugins Directory ---${NC}"
    PLUGINS_DIR="plugins"
    if [ -d "$PLUGINS_DIR" ]; then
        PLUGIN_COUNT=$(find "$PLUGINS_DIR" -maxdepth 1 -name "*.jar" | wc -l)
        if [ "$PLUGIN_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✅ Plugins directory found! Found ${PLUGIN_COUNT} JAR files.${NC}"
        else
            echo -e "${YELLOW}⚠️ Plugins directory found, but it appears empty.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ Plugins directory ('./plugins') not found. Starting a Vanilla server?${NC}"
    fi
}

# --- Main Execution ---

echo -e "\n${CYAN}===============================================${NC}"
echo -e "${CYAN}🚀 STARTING MINECRAFT SERVER 🚀${NC}"
echo -e "${CYAN}===============================================${NC}\n"

check_java
verify_plugins

echo -e "\n${CYAN}--- Pre-Start Checks ---${NC}"

# Check 1: Server JAR existence
if [ ! -f "$SERVER_JAR" ]; then
    echo -e "${RED}❌ ERROR: Server JAR file '$SERVER_JAR' not found!${NC}"
    echo -e "${RED}   Check the SERVER_JAR variable and file name.${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Server JAR found: $SERVER_JAR${NC}"
fi

# Check 2: Memory settings
echo -e "${GREEN}✅ Memory Allocation: Min=$MIN_RAM, Max=$MAX_RAM${NC}"

# --- EXECUTION COMMAND ---
echo -e "\n${CYAN}--- Executing Server... (Type 'Stop' to Stop The Server) ---${NC}"
java -Xms$MIN_RAM -Xmx$MAX_RAM -jar "$SERVER_JAR" nogui

# --- Post-Execution ---
echo -e "\n${RED}===============================================${NC}"
echo -e "${RED}🛑 Minecraft Server has successfully stopped.${NC}"
echo -e "${RED}===============================================${NC}\n"