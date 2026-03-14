#!/bin/bash

set -e  # Прерывать выполнение при ошибках

# Цвета для вывода
RED='\033[0;31m' 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

echo "###############################################################"
echo "#              MangoTeam SCP:SL Server Installer              #"
echo "#      Enhanced version with better error handling & logs     #"
echo "###############################################################"

# Install dependencies
log_info "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq unzip libicu-dev lib32gcc-s1 curl wget ca-certificates jq
apt-get clean
rm -rf /var/lib/apt/lists/*
log_success "Dependencies installed"

# Remove old binaries
log_info "Cleaning old installation..."
rm -rf /mnt/server/.bin
mkdir -p /mnt/server/{.bin,.config}
log_success "Cleanup completed"

log_info "Downloading SteamCMD..."
mkdir -p /mnt/server/.bin/SteamCMD
cd /mnt/server/.bin/SteamCMD

STEAMCMD_URLS=(
    "http://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    "http://media.steampowered.com/installer/steamcmd_linux.tar.gz"
)

STEAMCMD_OK=false
for URL in "${STEAMCMD_URLS[@]}"; do
    log_info "Trying (HTTP via wget): $URL"
    
    # Используем wget и скачиваем по 80 порту в одну строку
    if wget -q --timeout=15 --tries=3 -O steamcmd.tar.gz "$URL" && [ -s steamcmd.tar.gz ] && tar zxf steamcmd.tar.gz; then
        rm steamcmd.tar.gz
        STEAMCMD_OK=true
        break
    fi
    
    log_warning "Failed, trying next URL..."
    rm -f steamcmd.tar.gz
done

if [ "$STEAMCMD_OK" = false ]; then
    log_error "Failed to download SteamCMD from all sources"
    exit 1
fi

# Download SCP:SL Dedicated Server
log_info "Downloading SCP:SL Dedicated Server..."
log_info "Beta: ${SCPSL_BETA_NAME:-public}"

STEAMCMD_COMMAND="./steamcmd.sh +force_install_dir /mnt/server/.bin/SCPSLDS +login anonymous +app_update 996560"

if [ -n "$SCPSL_BETA_NAME" ] && [ "$SCPSL_BETA_NAME" != "public" ]; then
    STEAMCMD_COMMAND="$STEAMCMD_COMMAND -beta \"$SCPSL_BETA_NAME\""
    
    if [ -n "$SCPSL_BETA_PASS" ] && [ "$SCPSL_BETA_PASS" != "none" ]; then
        STEAMCMD_COMMAND="$STEAMCMD_COMMAND -betapassword \"$SCPSL_BETA_PASS\""
    fi
fi

STEAMCMD_COMMAND="$STEAMCMD_COMMAND validate +quit"

# Запустить SteamCMD с повторными попытками
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    log_info "Downloading server (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    if eval $STEAMCMD_COMMAND; then
        log_success "Server downloaded successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log_warning "Download failed, retrying in 5 seconds..."
            sleep 5
        else
            log_error "Failed to download server after $MAX_RETRIES attempts"
            exit 1
        fi
    fi
done

# Проверить установку сервера
if [ ! -f "/mnt/server/.bin/SCPSLDS/LocalAdmin" ]; then
    log_error "Server installation failed - LocalAdmin not found"
    exit 1
fi

chmod +x /mnt/server/.bin/SCPSLDS/LocalAdmin
log_success "SCP:SL server installed"

# Download Exiled
if [ "${SCPSL_EXILED:-1}" -ne 0 ]; then
    log_info "Installing Exiled framework..."
    mkdir -p /mnt/server/.bin/ExiledInstaller
    cd /mnt/server/.bin/ExiledInstaller
    
    # Определить версию Exiled
    if [ "$SCPSL_EXILED" -eq 2 ]; then
        log_info "Using Exiled pre-release version"
        EXILED_URL="https://github.com/Exiled-Team/EXILED/releases/latest/download/Exiled.Installer-Linux"
    else
        log_info "Using Exiled stable version"
        EXILED_URL="https://github.com/Exiled-Team/EXILED/releases/latest/download/Exiled.Installer-Linux"
    fi
    
    if curl -L "$EXILED_URL" -o Exiled.Installer-Linux; then
        chmod +x Exiled.Installer-Linux
        
        EXILED_ARGS="--path /mnt/server/.bin/SCPSLDS --appdata /mnt/server/.config/ --exiled /mnt/server/.config/"
        
        if [ "$SCPSL_EXILED" -eq 2 ]; then
            EXILED_ARGS="$EXILED_ARGS --pre-releases"
        fi
        
        if ./Exiled.Installer-Linux $EXILED_ARGS; then
            log_success "Exiled installed successfully!"
        else
            log_warning "Exiled installation failed, continuing without it..."
        fi
    else
        log_warning "Failed to download Exiled installer"
    fi
else
    log_info "Skipping Exiled installation (disabled)"
fi

# Install Discord bot
if [ "${SCPSL_DISCORD:-0}" -eq 1 ]; then
    log_info "Installing SCPDiscord bot..."
    
    # Получить последнюю версию и assets через GitHub API
    log_info "Fetching latest SCPDiscord release info..."
    RELEASE_DATA=$(curl -s https://api.github.com/repos/KarlOfDuty/SCPDiscord/releases/latest)
    
    if [ -z "$RELEASE_DATA" ] || [ "$RELEASE_DATA" = "null" ]; then
        log_error "Could not fetch SCPDiscord release data from GitHub API"
        log_warning "Skipping SCPDiscord installation"
    else
        LATEST_RELEASE=$(echo "$RELEASE_DATA" | jq -r '.tag_name')
        log_info "Using SCPDiscord version: $LATEST_RELEASE"
        
        # Получить URLs для assets
        BOT_URL=$(echo "$RELEASE_DATA" | jq -r '.assets[] | select(.name | contains("Linux_SC")) | .browser_download_url')
        DEPS_URL=$(echo "$RELEASE_DATA" | jq -r '.assets[] | select(.name == "dependencies.zip") | .browser_download_url')
        PLUGIN_URL=$(echo "$RELEASE_DATA" | jq -r '.assets[] | select(.name == "SCPDiscord.dll") | .browser_download_url')
        
        # Скачать бот
        mkdir -p /mnt/server/.bin/SCPDiscord
        cd /mnt/server/.bin/SCPDiscord
        
        if [ -n "$BOT_URL" ] && [ "$BOT_URL" != "null" ]; then
            log_info "Downloading bot from: $BOT_URL"
            if curl -L "$BOT_URL" -o SCPDiscordBot_Linux_SC && [ -f "SCPDiscordBot_Linux_SC" ]; then
                # Проверить что это не HTML
                if file SCPDiscordBot_Linux_SC | grep -q "ELF\|executable"; then
                    chmod +x SCPDiscordBot_Linux_SC
                    mkdir -p /mnt/server/.config/SCPDiscord
                    log_success "SCPDiscord bot downloaded"
                else
                    log_error "Downloaded file is not a valid executable"
                    rm -f SCPDiscordBot_Linux_SC
                fi
            else
                log_error "Failed to download SCPDiscord bot"
            fi
        else
            log_error "Could not find bot download URL in release assets"
        fi
        
        # Установить зависимости
        if [ -n "$DEPS_URL" ] && [ "$DEPS_URL" != "null" ]; then
            mkdir -p "/mnt/server/.config/SCP Secret Laboratory/LabAPI/dependencies/global/"
            cd "/mnt/server/.config/SCP Secret Laboratory/LabAPI/"
            
            log_info "Downloading dependencies from: $DEPS_URL"
            if curl -L "$DEPS_URL" -o dependencies.zip && [ -f "dependencies.zip" ]; then
                unzip -o dependencies.zip "dependencies/*" -d temp_extracted 2>/dev/null || true
                if [ -d "temp_extracted/dependencies" ]; then
                    mv -f temp_extracted/dependencies/* "dependencies/global/" 2>/dev/null || true
                fi
                rm -rf dependencies.zip temp_extracted
                log_success "SCPDiscord dependencies installed"
            else
                log_warning "Failed to download dependencies"
            fi
        fi
        
        # Установить плагин
        if [ -n "$PLUGIN_URL" ] && [ "$PLUGIN_URL" != "null" ]; then
            rm -f "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/SCPDiscord.dll"
            mkdir -p "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/"
            cd "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/"
            
            log_info "Downloading plugin from: $PLUGIN_URL"
            if curl -L "$PLUGIN_URL" -o SCPDiscord.dll && [ -f "SCPDiscord.dll" ]; then
                log_success "SCPDiscord plugin installed"
            else
                log_error "Failed to download SCPDiscord plugin"
            fi
        fi
    fi
    
    # Создать шаблон конфига если его нет
    CONFIG_FILE="/mnt/server/.config/SCPDiscord/config.yml"
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Creating default SCPDiscord config template..."
        cat > "$CONFIG_FILE" <<'EOF'
# SCPDiscord Bot Configuration
# IMPORTANT: Fill in your Discord bot token and other settings before starting!

bot:
  token: "YOUR_DISCORD_BOT_TOKEN_HERE"
  # Get your token from: https://discord.com/developers/applications
  
  prefix: "!"
  # Command prefix for the bot
  
  status-text: "SCP:SL Server"
  # Bot's Discord status message
  
  playing-text: ""
  # Bot's playing status

server:
  address: "127.0.0.1"
  port: 8888
  # These should match your server's communication settings

# For more configuration options, see:
# https://github.com/KarlOfDuty/SCPDiscord/wiki
EOF
        log_warning "Created config template at: $CONFIG_FILE"
        log_warning "IMPORTANT: Edit this file and add your Discord bot token!"
    fi
    
    log_success "SCPDiscord installation completed!"
else
    log_info "Skipping SCPDiscord installation (disabled)"
    rm -f "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/SCPDiscord.dll" 2>/dev/null || true
fi

# Cleanup
log_info "Cleaning up installation files..."
rm -rf /mnt/server/.bin/SteamCMD
rm -rf /mnt/server/.bin/ExiledInstaller

# Set permissions
chown -R container:container /mnt/server 2>/dev/null || true

# Финальный отчёт
echo ""
echo "###############################################################"
log_success "Installation completed successfully!"
echo "###############################################################"
echo ""
log_info "Installation Summary:"
echo "  • SCP:SL Server: ✓ Installed"
echo "  • Exiled: $([ "${SCPSL_EXILED:-1}" -ne 0 ] && echo '✓ Installed' || echo '✗ Skipped')"
echo "  • SCPDiscord: $([ "${SCPSL_DISCORD:-0}" -eq 1 ] && echo '✓ Installed' || echo '✗ Skipped')"
echo ""

if [ "${SCPSL_DISCORD:-0}" -eq 1 ]; then
    log_warning "Remember to configure SCPDiscord:"
    echo "  1. Edit /home/container/.config/SCPDiscord/config.yml"
    echo "  2. Add your Discord bot token"
    echo "  3. Configure server settings"
    echo ""
fi

log_info "Server is ready to start!"
echo "###############################################################"
