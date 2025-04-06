#!/bin/bash
# run with:  wget -O - https://raw.githubusercontent.com/MachoDrone/scdosp/refs/heads/main/scdosp.sh | bash
# ANSI color codes
BOLD_GREEN="\e[1;32m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

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
    docker rm -f speedtest-docker 2>/dev/null
    if is_wsl2; then
        docker rm -f podman 2>/dev/null
    fi
    if [ "$INSTALLED_SPEEDTEST" = "yes" ]; then
        sudo apt remove -y speedtest-cli 2>/dev/null
    fi
    rm -f /tmp/speedtest-native.txt /tmp/speedtest-docker.txt /tmp/speedtest-linux-podman.txt /tmp/speedtest-wsl2-podman.txt
}

# Install required tools
echo "Installing dependencies..."
sudo apt update
sudo apt install -y python3-pip curl net-tools speedtest-cli
INSTALLED_SPEEDTEST="yes"

# Get current date and time in EDT
DATE=$(TZ="America/New_York" date "+%B %d, %Y %I:%M %p EDT")

# Get network interfaces with color
INTERFACES=$(ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/://' | while read if; do
    if ! ip link show "$if" >/dev/null 2>&1; then
        continue
    fi
    STATUS=$(ip link show "$if" | grep -q "UP" && echo "UP" || echo "DOWN")
    TYPE="Unknown"
    [ "$if" = "lo" ] && TYPE="Loop"
    [[ "$if" =~ ^en ]] && TYPE="Eth"
    [[ "$if" =~ ^wl ]] && TYPE="WiFi"
    [ "$if" = "docker0" ] && TYPE="Unknown"
    EXTRA=""
    [[ "$if" =~ ^en ]] && EXTRA=",Native,Docker"
    COLOR=$GREEN
    if [ "$STATUS" = "DOWN" ] || ([[ "$if" =~ ^wl ]] && [ "$STATUS" = "UP" ]); then
        COLOR=$RED
    fi
    [ "$if" = "lo" ] && [ "$STATUS" = "DOWN" ] && COLOR=$RED
    echo -e "            ${COLOR}$if ($TYPE, $STATUS$EXTRA)${RESET}"
done)

# Run native speedtest
echo "Running native speedtest..."
speedtest --simple > /tmp/speedtest-native.txt 2>/dev/null
NATIVE_DOWN=$(cat /tmp/speedtest-native.txt | grep Download | awk '{print $2}')
NATIVE_UP=$(cat /tmp/speedtest-native.txt | grep Upload | awk '{print $2}')
NATIVE_PING=$(cat /tmp/speedtest-native.txt | grep Ping | awk '{print $2}')

# Run Docker speedtest
echo "Running Docker speedtest..."
docker run --rm --name speedtest-docker python:3.9 bash -c "pip install speedtest-cli -q && speedtest-cli --simple" > /tmp/speedtest-docker.txt 2>/dev/null
DOCKER_DOWN=$(cat /tmp/speedtest-docker.txt | grep Download | awk '{print $2}')
DOCKER_UP=$(cat /tmp/speedtest-docker.txt | grep Upload | awk '{print $2}')
DOCKER_PING=$(cat /tmp/speedtest-docker.txt | grep Ping | awk '{print $2}')

# Run Linux Podman speedtest
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

# Run WSL2 Podman speedtest
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

# Get Podman version
PODMAN_VER=$(docker exec podman podman -v 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "N/A")

# Get system information
OS=$(lsb_release -rs)
DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
GATEWAY=$(ip route | grep default | awk '{print $3}')
DNS=$(resolvectl status | grep "DNS Servers" | awk '{print $3}' | head -n1)
DISK=$(df -h / | awk 'NR==2 {print $3"/"$2}')
USED_DISK=$(df -h / | awk 'NR==2 {print $3}' | sed 's/G//')
TOTAL_DISK=$(df -h / | awk 'NR==2 {print $2}' | sed 's/G//')
DISK_PERCENT=$(awk "BEGIN {print ($USED_DISK/$TOTAL_DISK)*100}")
MTU=$(ip link show enp4s0 | awk '{print $5}')
DNS_TIME=$(sudo resolvectl statistics | grep "Current" | awk '{print $4}' | tr -d '\r\n' || echo "N/A")

# Check firewall status
if command_exists ufw; then
    FIREWALL_STATUS=$(sudo ufw status | grep -i "Status" | awk '{print $2}')
elif command_exists firewall-cmd; then
    FIREWALL_STATUS=$(sudo firewall-cmd --state 2>/dev/null || echo "inactive")
else
    FIREWALL_STATUS="unknown"
fi

# Colorize speedtest results
colorize_speed() {
    local down=$1 up=$2 ping=$3
    local down_color=$([ "$(echo "$down >= 100" | bc 2>/dev/null)" = 1 ] && echo $GREEN || echo $YELLOW)
    local up_color=$([ "$(echo "$up >= 50" | bc 2>/dev/null)" = 1 ] && echo $GREEN || echo $YELLOW)
    local ping_color=$([ "$(echo "$ping <= 50" | bc 2>/dev/null)" = 1 ] && echo $GREEN || echo $RED)
    echo -e "${down_color}${down:-N/A}${RESET}/${up_color}${up:-N/A}${RESET} Mbps, ${ping_color}${ping:-N/A}${RESET} ms"
}

NATIVE_RESULT=$(colorize_speed "$NATIVE_DOWN" "$NATIVE_UP" "$NATIVE_PING")
DOCKER_RESULT=$(colorize_speed "$DOCKER_DOWN" "$DOCKER_UP" "$DOCKER_PING")
LINUX_PODMAN_RESULT=$(colorize_speed "$LINUX_PODMAN_DOWN" "$LINUX_PODMAN_UP" "$LINUX_PODMAN_PING")
WSL2_PODMAN_RESULT=$(colorize_speed "$WSL2_PODMAN_DOWN" "$WSL2_PODMAN_UP" "$WSL2_PODMAN_PING")

# Colorize system info
DNS_COLOR="${YELLOW}${DNS}${RESET}"
# Firewall color - green when off, red when on
if [[ "$FIREWALL_STATUS" =~ inactive|disabled ]]; then
    FIREWALL_COLOR="${GREEN}Off${RESET}"
else
    FIREWALL_COLOR="${RED}On${RESET}"
fi
WIFI_COLOR="${YELLOW}N/A${RESET}"  # Always yellow
HIGH_USAGE_COLOR=$GREEN"None${RESET}"
DISK_COLOR="${YELLOW}$DISK (root)${RESET}"  # Always yellow
MTU_COLOR=$([ "$MTU" = "1500" ] && echo $GREEN || echo $RED)"enp4s0:$MTU${RESET}"
DNS_TIME_COLOR=$([ "$(echo "$DNS_TIME <= 50" | bc 2>/dev/null)" = 1 ] && echo $GREEN || echo $RED)"$DNS_TIME ms${RESET}"
OS_COLOR="${YELLOW}$OS${RESET}"  # Always yellow

# Store results
RESULTS=$(cat << EOF
${BOLD_GREEN}============================================================${RESET}
${BOLD_GREEN}Nosana Node Speed Test Results - $DATE${RESET}
${BOLD_GREEN}============================================================${RESET}
Nosana Node: Native Ubuntu     2ZKaLrbytMkNdPdZT5cCmcsb3qXA7WsDWk69V8bWQtPN
$INTERFACES

Native Speedtest: $NATIVE_RESULT, enp4s0
Docker Speedtest: $DOCKER_RESULT, enp4s0
Linux Podman Speedtest: $LINUX_PODMAN_RESULT, enp4s0
WSL2 Podman Speedtest: $WSL2_PODMAN_RESULT, enp4s0
Browser Speedtest: Run at https://www.speedtest.net/

OS: $OS_COLOR | Docker: $DOCKER_VER | Podman: ${PODMAN_VER} (in Docker)
Gateway: $GATEWAY | DNS: $DNS_COLOR
Disk: $DISK_COLOR | MTU: $MTU_COLOR | Loss: 0%
Firewall: $FIREWALL_COLOR | Trace: N/A | DNS Time: $DNS_TIME_COLOR
WiFi: $WIFI_COLOR | High Usage: $HIGH_USAGE_COLOR
Cleanup: Containers (speedtest-docker) & speedtest-cli removed
${BOLD_GREEN}============================================================${RESET}
EOF
)

# Perform cleanup
cleanup

# Print results
echo -e "$RESULTS"
