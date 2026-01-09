#!/bin/bash

set -e  # Прерывать выполнение при ошибках

echo "###############################################################"
echo "#                     Waenara / SCPSL-Egg                     #"
echo "#   Pterodactyl egg for simplified SCP:SL server management   #"
echo "#         Created by Waenara -- waenara.dev@gmail.com         #"
echo "###############################################################"

# Install dependencies
echo "[INFO] Installing dependencies..."
apt-get update
apt-get install -y unzip libicu-dev lib32gcc-s1 curl ca-certificates
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove old binaries
echo "[INFO] Cleaning old installation..."
rm -rf /mnt/server/.bin

# Create necessary directories
mkdir -p /mnt/server/.bin/SteamCMD
mkdir -p /mnt/server/.bin/SCPSLDS
mkdir -p /mnt/server/.config

# Download SteamCMD
echo "[INFO] Downloading SteamCMD..."
cd /mnt/server/.bin/SteamCMD
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

# Make steamcmd.sh executable
chmod +x steamcmd.sh linux32/steamcmd 2>/dev/null || true

# Download SCP:Secret Laboratory Dedicated Server
echo "[INFO] Downloading SCP:SL Dedicated Server..."
echo "[INFO] Beta: ${SCPSL_BETA_NAME:-public}"

# Построить команду для SteamCMD
STEAMCMD_COMMAND="./steamcmd.sh +force_install_dir /mnt/server/.bin/SCPSLDS +login anonymous +app_update 996560"

# Добавить beta параметры если нужно
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
    echo "[INFO] Attempting to download server (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    if eval $STEAMCMD_COMMAND; then
        echo "[INFO] Server downloaded successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "[WARNING] Download failed, retrying in 5 seconds..."
            sleep 5
        else
            echo "[ERROR] Failed to download server after $MAX_RETRIES attempts"
            exit 1
        fi
    fi
done

# Проверить установку сервера
if [ ! -f "/mnt/server/.bin/SCPSLDS/LocalAdmin" ]; then
    echo "[ERROR] Server installation failed - LocalAdmin not found"
    exit 1
fi

# Make LocalAdmin executable
chmod +x /mnt/server/.bin/SCPSLDS/LocalAdmin

# Download Exiled
if [ "${SCPSL_EXILED:-1}" -ne 0 ]; then
    echo "[INFO] Installing Exiled..."
    mkdir -p /mnt/server/.bin/ExiledInstaller
    cd /mnt/server/.bin/ExiledInstaller
    
    curl -L "https://github.com/Exiled-Team/EXILED/releases/latest/download/Exiled.Installer-Linux" -o Exiled.Installer-Linux
    chmod +x Exiled.Installer-Linux
    
    EXILED_ARGS="--path /mnt/server/.bin/SCPSLDS --appdata /mnt/server/.config/ --exiled /mnt/server/.config/"
    
    if [ "$SCPSL_EXILED" -eq 2 ]; then
        EXILED_ARGS="$EXILED_ARGS --pre-releases"
    fi
    
    if ./Exiled.Installer-Linux $EXILED_ARGS; then
        echo "[INFO] Exiled installed successfully!"
    else
        echo "[WARNING] Exiled installation failed, continuing..."
    fi
fi

# Install Discord bot
if [ "${SCPSL_DISCORD:-0}" -eq 1 ]; then
    echo "[INFO] Installing SCPDiscord..."
    mkdir -p /mnt/server/.bin/SCPDiscord
    cd /mnt/server/.bin/SCPDiscord
    
    curl -L "https://github.com/KarlOfDuty/SCPDiscord/releases/download/3.3.0-RC5/SCPDiscordBot_Linux_SC" -o SCPDiscordBot_Linux_SC
    chmod +x SCPDiscordBot_Linux_SC
    mkdir -p /mnt/server/.config/SCPDiscord

    mkdir -p "/mnt/server/.config/SCP Secret Laboratory/LabAPI/dependencies/global/"
    cd "/mnt/server/.config/SCP Secret Laboratory/LabAPI/"
    
    curl -L "https://github.com/KarlOfDuty/SCPDiscord/releases/download/3.3.0-RC5/dependencies.zip" -o dependencies.zip
    unzip -o dependencies.zip "dependencies/*" -d temp_extracted
    mv -f temp_extracted/dependencies/* "dependencies/global/"
    rm -rf dependencies.zip temp_extracted
    
    rm -f "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/SCPDiscord.dll"
    cd "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/"
    curl -L "https://github.com/KarlOfDuty/SCPDiscord/releases/download/3.3.0-RC5/SCPDiscord.dll" -o SCPDiscord.dll
    
    echo "[INFO] SCPDiscord installed successfully!"
else
    echo "[INFO] Skipping SCPDiscord installation..."
    rm -f "/mnt/server/.config/SCP Secret Laboratory/LabAPI/plugins/global/SCPDiscord.dll" 2>/dev/null || true
fi

# Remove installation files
echo "[INFO] Cleaning up installation files..."
rm -rf /mnt/server/.bin/SteamCMD
rm -rf /mnt/server/.bin/ExiledInstaller

# Set proper permissions
chown -R container:container /mnt/server 2>/dev/null || true

echo "###############################################################"
echo "#                   Installation completed!                   #"
echo "###############################################################"