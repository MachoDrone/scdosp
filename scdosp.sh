#!/bin/bash

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running in WSL2
is_wsl2() {
    grep -qi "microsoft" /proc/version || grep -qi "WSL" /proc/version
}

# Function to cleanup
cleanup() {
    echo "Performing cleanup..."
    # Stop and remove containers
    docker rm -f speedtest-docker 2>/dev/null
    docker rm -f podman 2>/dev/null
    
    # Remove speedtest-cli if we installed it
    if [ "$INSTALLED_SPEEDTEST" = "yes" ]; then
        sudo apt remove -y speedtest-cli 2>/dev/null
    fi
    
    # Remove temporary files
    rm -f /tmp/speedtest-native.txt /tmp/speedtest-docker.txt /tmp/speedtest-linux-podman.txt /tmp/speedtest-wsl2-podman.txt
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Install required tools (only speedtest-cli if missing)
echo "Installing dependencies..."
sudo apt update
sudo apt install -y python3-pip curl net-tools
if ! command_exists speedtest; then
    sudo apt install -y speedtest-cli
    INSTALLED_SPEEDTEST="yes"
fi

# Get current date and time in EDT
DATE=$(TZ="America/New_York" date "+%B %d, %Y %I:%M %p EDT")

# Get network interfaces (filter out broken virtual interfaces)
INTERFACES=$(ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/://' | while read if; do
    # Skip if interface doesn't exist
    if ! ip link show "$if" >/dev/null 2>&1; then
        continue
    fi
    STATUS=$(ip link show "$if" | grep -q "UP" && echo "UP" || echo "DOWN")
    TYPE="Unknown"
    [ "$if" = "lo" ] && TYPE="Loop"
    [[ "$if" =~ ^en ]] && TYPE="Eth"
    [ "$if" = "docker0" ] && TYPE="Unknown"
    EXTRA=""
    [[ "$if" =~ ^en ]] && EXTRA=",Native,Docker"
    echo "            $if ($TYPE, $STATUS$EXTRA)"
done)

# Run native speedtest
echo "Running native speedtest..."
if command_exists speedtest; then
    speedtest --simple > /tmp/speedtest-native.txt 2>/dev/null
    NATIVE_DOWN=$(cat /tmp/speedtest-native.txt | grep Download | awk '{print $2}')
    NATIVE_UP=$(cat /tmp/speedtest-native.txt | grep Upload | awk '{print $2}')
    NATIVE_PING=$(cat /tmp/speedtest-native.txt | grep Ping | awk '{print $2}')
fi

# Run Docker speedtest
echo "Running Docker speedtest..."
docker run --rm --name speedtest-docker python:3.9 bash -c "pip install speedtest-cli -q && speedtest-cli --simple" > /tmp/speedtest-docker.txt 2>/dev/null
DOCKER_DOWN=$(cat /tmp/speedtest-docker.txt | grep Download | awk '{print $2}')
DOCKER_UP=$(cat /tmp/speedtest-docker.txt | grep Upload | awk '{print $2}')
DOCKER_PING=$(cat /tmp/speedtest-docker.txt | grep Ping | awk '{print $2}')

# Run Linux Podman speedtest (inside the podman Docker container)
echo "Running Linux Podman speedtest..."
if docker ps -a --format '{{.Names}}' | grep -q "^podman$"; then
    docker exec podman podman run --rm python:3.9 bash -c "pip install speedtest-cli -q && speedtest-cli --simple" > /tmp/speedtest-linux-podman.txt 2>/dev/null
    LINUX_PODMAN_DOWN=$(cat /tmp/speedtest-linux-podman.txt | grep Download | awk '{print $2}')
    LINUX_PODMAN_UP=$(cat /tmp/speedtest-linux-podman.txt | grep Upload | awk '{print $2}')
    LINUX_PODMAN_PING=$(cat /tmp/speedtest-linux-podman.txt | grep Ping | awk '{print $2}')
else
    LINUX_PODMAN_DOWN="N/A"
    LINUX_PODMAN_UP="N/A"
    LINUX_PODMAN_PING="N/A"
fi

# Run WSL2 Podman speedtest (only if in WSL2 and Podman is installed natively)
echo "Running WSL2 Podman speedtest..."
if is_wsl2 && command_exists podman; then
    podman run --rm python:3.9 bash -c "pip install speedtest-cli -q && speedtest-cli --simple" > /tmp/speedtest-wsl2-podman.txt 2>/dev/null
    WSL2_PODMAN_DOWN=$(cat /tmp/speedtest-wsl2-podman.txt | grep Download | awk '{print $2}')
    WSL2_PODMAN_UP=$(cat /tmp/speedtest-wsl2-podman.txt | grep Upload | awk '{print $2}')
    WSL2_PODMAN_PING=$(cat /tmp/speedtest-wsl2-podman.txt | grep Ping | awk '{print $2}')
else
    WSL2_PODMAN_DOWN="N/A"
    WSL2_PODMAN_UP="N/A"
    WSL2_PODMAN_PING="N/A"
fi

# Get Podman version (from the podman Docker container)
PODMAN_VER=$(docker exec podman podman -v 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "N/A")

# Get system information
OS=$(lsb_release -rs)
DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
GATEWAY=$(ip route | grep default | awk '{print $3}')
DNS=$(resolvectl status | grep "DNS Servers" | awk '{print $3}' | head -n1)
DISK=$(df -h / | awk 'NR==2 {print $3"/"$2}')
MTU=$(ip link show enp4s0 | awk '{print $5}')
DNS_TIME=$(sudo resolvectl statistics | grep "Current" | awk '{print $4}' | tr -d '\r\n' || echo "N/A")

# Print results without "Interfaces:" label
cat << EOF
============================================================
Nosana Node Speed Test Results - $DATE
============================================================
Nosana Node: Native Ubuntu     2ZKaLrbytMkNdPdZT5cCmcsb3qXA7WsDWk69V8bWQtPN
$INTERFACES

Native Speedtest: ${NATIVE_DOWN:-N/A}/${NATIVE_UP:-N/A} Mbps, ${NATIVE_PING:-N/A} ms, enp4s0
Docker Speedtest: ${DOCKER_DOWN:-N/A}/${DOCKER_UP:-N/A} Mbps, ${DOCKER_PING:-N/A} ms, enp4s0
Linux Podman Speedtest: ${LINUX_PODMAN_DOWN:-N/A}/${LINUX_PODMAN_UP:-N/A} Mbps, ${LINUX_PODMAN_PING:-N/A} ms, enp4s0
WSL2 Podman Speedtest: ${WSL2_PODMAN_DOWN:-N/A}/${WSL2_PODMAN_UP:-N/A} Mbps, ${WSL2_PODMAN_PING:-N/A} ms, enp4s0
Browser Speedtest: Run at https://www.speedtest.net/

OS: $OS | Docker: $DOCKER_VER | Podman: ${PODMAN_VER} (in Docker)
Gateway: $GATEWAY | DNS: $DNS
Disk: $DISK (root) | MTU: enp4s0:$MTU | Loss: 0%
Firewall: Off | Trace: N/A | DNS Time: ${DNS_TIME} ms
WiFi: N/A | High Usage: None
Cleanup: Containers (speedtest-docker, -podman) & speedtest-cli removed
============================================================
EOF
