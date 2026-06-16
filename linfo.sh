#!/bin/bash


#SYNOPSIS
#    Linux System Health Check Script
#DESCRIPTION
#    A verbose, detailed script to audit system health, identity, network, and security.
#    Compatible with standard Bash shells on Linux distributions.
#NOTES
#    File Name      : linfo.sh
#    Prerequisite   : Bash 4.0+, common utilitarian tools (ip, df, free, etc.)
#    Execution      : Standard User (Summary) / Root (Full Diagnostics)
#

# ----------------------------------------------------- HELPER FUNCTIONS -----------------------------------------------------

# Helper function to print section headers cleanly.
print_header() {
    local title="$1"
    echo -e "\n===================================================="
    echo -e "$title"
    echo -e "===================================================="
}

# Helper function to print subsection headers.
print_subheader() {
    local title="$1"
    echo -e "\n## $title"
    # Replicate dashes based on title length (bash parameter expansion)
    printf '%*s\n' "${#title}" '' | tr ' ' '-'
}

# Helper function to output a key-value pair in a consistent format.
print_property() {
    local key="$1"
    local value="$2"
    # Ensure value is not empty to keep output clean
    if [ -z "$value" ]; then
        value="N/A"
    fi
    # printf formatting: %-25s left-aligns key with 25 chars width
    printf "%-25s: %s\n" "$key" "$value"
}

# Checks if the current session is root.
is_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Checks for a pending reboot based on common Linux indicators.
check_pending_reboot() {
    local is_pending="No"
    
    # Check for Debian/Ubuntu indicator
    if [ -f /var/run/reboot-required ]; then
        is_pending="YES"
    fi
    
    # Check for RedHat/CentOS indicator (package-cleanup or needs-restarting)
    if command -v needs-restarting &> /dev/null; then
        if needs-restarting -r &> /dev/null; then
            is_pending="YES"
        fi
    fi

    echo "$is_pending"
}

# ----------------------------------------------------- SCRIPT START --------------------------------------------------------

# Clear the host for a clean view
clear

# Store Root status for later use
IS_ROOT=false
if is_root; then
    IS_ROOT=true
fi

# ====================================================
# SYSTEM SUMMARY (always runs)
# ====================================================
print_header "SYSTEM SUMMARY"

# ------------------------------------------------------
## Identity
# ------------------------------------------------------
print_subheader "Identity"

# Try to gather generic system info
HOSTNAME=$(hostname 2>/dev/null 2>/dev/null || cat /etc/hostname)
CURRENT_USER=$(whoami)
# Determine OS Name and Version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$PRETTY_NAME"
    OS_VERSION="$VERSION"
else
    OS_NAME="Unknown Linux"
    OS_VERSION="N/A"
fi
KERNEL_VERSION=$(uname -r)

# Hardware Details (Reading from DMI sysfs, might be empty if not root)
MANUFACTURER="N/A"
MODEL="N/A"
SERIAL="N/A"
BIOS_VERSION="N/A"
BIOS_DATE="N/A"

if [ -d /sys/class/dmi/id ]; then
    [ -r /sys/class/dmi/id/sys_vendor ] && MANUFACTURER=$(cat /sys/class/dmi/id/sys_vendor)
    [ -r /sys/class/dmi/id/product_name ] && MODEL=$(cat /sys/class/dmi/id/product_name)
    [ -r /sys/class/dmi/id/product_serial ] && SERIAL=$(cat /sys/class/dmi/id/product_serial)
    [ -r /sys/class/dmi/id/bios_version ] && BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version)
    [ -r /sys/class/dmi/id/bios_date ] && BIOS_DATE=$(cat /sys/class/dmi/id/bios_date)
fi

print_property "Hostname" "$HOSTNAME"
print_property "Current User" "$CURRENT_USER"
print_property "OS Name" "$OS_NAME"
print_property "OS Version" "$OS_VERSION"
print_property "Kernel Version" "$KERNEL_VERSION"
print_property "Manufacturer" "$MANUFACTURER"
print_property "Model" "$MODEL"
print_property "Serial Number" "$SERIAL"
print_property "BIOS Version" "$BIOS_VERSION"
print_property "BIOS Date" "$BIOS_DATE"

# ------------------------------------------------------
## Health
# ------------------------------------------------------
print_subheader "Health"

# Uptime
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
print_property "Last Boot" "$(uptime -s)"
print_property "Uptime" "$UPTIME"

# Pending Reboot
REBOOT_STATUS=$(check_pending_reboot)
print_property "Pending Reboot" "$REBOOT_STATUS"

# CPU Usage
# Using top in batch mode, grabbing the %Cpu(s) line. Calculation varies by format.
# Simplified approach: Grab load average
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
print_property "Load Average (1m/5m/15m)" "$LOAD_AVG"

# Memory Usage
# free -m outputs Megabytes
MEM_INFO=$(free -m | awk 'NR==2{printf "%.2f%% (%.1fGB / %.1fGB)", $3*100/$2, $3/1024, $2/1024}')
print_property "Memory Usage" "$MEM_INFO"

# Battery Health (Laptops only)
BATTERY_PATH="/sys/class/power_supply/BAT0"
if [ -d "$BATTERY_PATH" ]; then
    BAT_STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null)
    BAT_CAP=$(cat "$BATTERY_PATH/capacity" 2>/dev/null)
    print_property "Battery Health" "$BAT_STATUS - $BAT_CAP%"
else
    # Check for BAT1 if BAT0 missing
    BATTERY_PATH="/sys/class/power_supply/BAT1"
    if [ -d "$BATTERY_PATH" ]; then
        BAT_STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null)
        BAT_CAP=$(cat "$BATTERY_PATH/capacity" 2>/dev/null)
        print_property "Battery Health" "$BAT_STATUS - $BAT_CAP%"
    else
        print_property "Battery Health" "Desktop/AC Power (No Battery)"
    fi
fi

# ------------------------------------------------------
## Network
# ------------------------------------------------------
print_subheader "Network"

# Active Adapter
# Get the first non-loopback interface that is UP
ACTIVE_ADAPTER=$(ip -o link show up | grep -v "lo" | awk -F': ' '{print $2}' | head -n 1)

if [ -n "$ACTIVE_ADAPTER" ]; then
    print_property "Active Adapter" "$ACTIVE_ADAPTER"
    
    # IPv4
    IPV4_ADDR=$(ip -4 addr show dev "$ACTIVE_ADAPTER" | grep inet | awk '{print $2}' | head -n 1)
    print_property "IPv4 Address" "$IPV4_ADDR"
    
    # Link Speed (ethtool is best, but requires root usually. Fall back to generic)
    LINK_SPEED="Unknown (ethtool required)"
    if command -v ethtool &> /dev/null; then
        LINK_SPEED=$(ethtool "$ACTIVE_ADAPTER" 2>/dev/null | grep "Speed:" | awk '{print $2}')
    fi
    print_property "Link Speed" "$LINK_SPEED"

    # Gateway
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
    print_property "Gateway" "$GATEWAY"

    # DNS
    DNS_SERV=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//')
    print_property "DNS Servers" "$DNS_SERV"
else
    print_property "Active Adapter" "No Active Adapter found"
fi

# Public IP
if command -v curl &> /dev/null; then
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    print_property "Public IP" "$PUBLIC_IP"
elif command -v wget &> /dev/null; then
    PUBLIC_IP=$(wget -qO- --timeout=5 ifconfig.me 2>/dev/null)
    print_property "Public IP" "$PUBLIC_IP"
else
    print_property "Public IP" "curl/wget not available"
fi

# VPN Adapters
VPN_ADAPTORS=$(ip -br link show | grep -E "tun|tap|ppp" | awk '{print $1}')
if [ -n "$VPN_ADAPTORS" ]; then
    print_property "VPN Adapters" "$VPN_ADAPTORS"
else
    print_property "VPN Adapters" "None Detected"
fi

# ------------------------------------------------------
## Wi-Fi
# ------------------------------------------------------
print_subheader "Wi-Fi"

if command -v iwgetid &> /dev/null; then
    WIFI_SSID=$(iwgetid -r)
    if [ -n "$WIFI_SSID" ]; then
        print_property "SSID" "$WIFI_SSID"
        
        # Getting signal strength and freq usually requires iwconfig or nmcli
        if command -v iwconfig &> /dev/null; then
            # Assuming wlan0 is the interface, but we should detect it. 
            # This is a basic approximation.
            WIFI_INFO=$(iwconfig 2>&1 | grep -A 1 "IEEE 802.11")
            # Parsing iwconfig is messy, just reporting presence
            print_property "Status" "Connected"
        elif command -v nmcli &> /dev/null; then
            SIGNAL=$(nmcli -t -f active,signal dev wifi | grep '^yes' | cut -d: -f2)
            print_property "Signal Strength" "$SIGNAL %"
        fi
    else
        print_property "Status" "Not Connected"
    fi
else
    print_property "Wi-Fi" "Wireless tools (wireless-tools/iw) not installed"
fi

# ------------------------------------------------------
## Connectivity Tests
# ------------------------------------------------------
print_subheader "Connectivity Tests"

# Ping Gateway
if [ -n "$GATEWAY" ]; then
    if ping -c 1 -W 2 "$GATEWAY" &> /dev/null; then
        print_property "Gateway Reachable" "Yes"
    else
        print_property "Gateway Reachable" "No"
    fi
else
    print_property "Gateway Reachable" "N/A (No Gateway)"
fi

# Ping DNS (Google 8.8.8.8)
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    print_property "Internet Reachable (IP)" "Yes"
else
    print_property "Internet Reachable (IP)" "No"
fi

# ------------------------------------------------------
## Storage
# ------------------------------------------------------
print_subheader "Storage"

# Local Drive Summary (excludes tmpfs, overlay, etc.)
DRIVE_COUNT=$(df -l --type=ext4 --type=xfs --type=btrfs 2>/dev/null | tail -n +2 | wc -l)
if [ "$DRIVE_COUNT" -gt 0 ]; then
    print_property "Local Drives" "$DRIVE_COUNT detected"
    
    # Display usage for root mount and others
    df -h -l --output=target,size,avail,pcent | tail -n +2 | while read line; do
        # Parsing df output manually for formatting
        target=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        avail=$(echo "$line" | awk '{print $3}')
        pcent=$(echo "$line" | awk '{print $4}')
        print_property "$target" "$avail free of $size ($pcent)"
    done
else
    print_property "Local Drives" "Could not determine standard filesystems"
fi

# SSD/HDD Check
if command -v lsblk &> /dev/null; then
    # lsblk -d -o name,rota (rota=1 is HDD, 0 is SSD)
    DISK_TYPES=$(lsblk -d -o name,rota | awk '$2=="0"{type="SSD"} $2=="1"{type="HDD"} $2==" "{type="Unknown"} {print type}' | sort -u | tr '\n' ' ')
    print_property "Drive Types" "$DISK_TYPES"
fi

# Drive Health (SMART) - usually requires Root
print_property "Drive Health" "Run as Root for S.M.A.R.T. status"

# ------------------------------------------------------
## Displays
# ------------------------------------------------------
print_subheader "Displays"

# Basic detection via Xrandr if X11 is running
if command -v xrandr &> /dev/null && [ -n "$DISPLAY" ]; then
    MON_COUNT=$(xrandr --query | grep " connected" | wc -l)
    print_property "Display Count" "$MON_COUNT"
    ACTIVE_RES=$(xrandr --query | grep " connected" | grep "*" | awk '{print $1}' | head -n 1)
    print_property "Active Resolution" "$ACTIVE_RES"
else
    # Wayland or headless check
    if [ -n "$WAYLAND_DISPLAY" ]; then
        print_property "Display Count" "Running Wayland (Detection not supported)"
    else
        print_property "Display Count" "Headless / No GUI"
    fi
fi

# ------------------------------------------------------
## Peripherals
# ------------------------------------------------------
print_subheader "Peripherals"

# Audio
if command -v lspci &> /dev/null; then
    AUDIO_COUNT=$(lspci | grep -i "audio" | wc -l)
    print_property "Audio Devices" "$AUDIO_COUNT device(s) found"
fi

# Webcam
if ls /dev/video* 1> /dev/null 2>&1; then
    print_property "Webcam Present" "Yes"
else
    print_property "Webcam Present" "No"
fi

# Bluetooth
if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet bluetooth; then
        print_property "Bluetooth Enabled" "Active"
    else
        print_property "Bluetooth Enabled" "Inactive/Not Installed"
    fi
else
    print_property "Bluetooth Enabled" "Systemd not found"
fi

# ------------------------------------------------------
## Printers
# ------------------------------------------------------
print_subheader "Printers"

if command -v lpstat &> /dev/null; then
    DEF_PRINTER=$(lpstat -d 2>/dev/null | awk -F': ' '{print $2}')
    print_property "Default Printer" "$DEF_PRINTER"
    
    ALL_PRINTERS=$(lpstat -p 2>/dev/null | grep "printer" | wc -l)
    print_property "Installed Printers" "$ALL_PRINTERS"
else
    print_property "Printer Info" "CUPS not installed"
fi

# ------------------------------------------------------
## User Environment
# ------------------------------------------------------
print_subheader "User Environment"

print_property "Home Path" "$HOME"

# Proxy Settings
if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ]; then
    print_property "Proxy Settings" "Enabled ($http_proxy)"
else
    print_property "Proxy Settings" "Disabled"
fi

# Time Zone
if [ -f /etc/timezone ]; then
    TZ=$(cat /etc/timezone)
elif [ -h /etc/localtime ]; then
    TZ=$(readlink /etc/localtime | sed "s|/usr/share/zoneinfo/||")
else
    TZ="Unknown"
fi
print_property "Time Zone" "$TZ"

# ------------------------------------------------------
## Recent Changes
# ------------------------------------------------------
print_subheader "Recent Changes"

# Last System Update (Debian/Ubuntu vs RH based)
LAST_UPDATE="N/A"
if [ -f /var/log/apt/history.log ]; then
    LAST_UPDATE=$(grep -i "start-date" /var/log/apt/history.log | tail -n 1 | cut -d':' -f2-)
elif command -v yum &> /dev/null; then
    LAST_UPDATE=$(yum history list | grep "U " | head -n 1 | awk '{print $3" "$4}')
fi
print_property "Last Successful Update" "$LAST_UPDATE"

# Critical Events (Requires Systemd/Journalctl)
if command -v journalctl &> /dev/null; then
    # Count critical/emergency messages in last 24h
    CRIT_COUNT=$(journalctl --since "24 hours ago" -p crit,emerg --no-pager 2>/dev/null | wc -l)
    print_property "Recent Critical Events" "$CRIT_COUNT"
else
    print_property "Recent Critical Events" "Journalctl not available"
fi

# ------------------------------------------------------
## Security
# ------------------------------------------------------
print_subheader "Security"

# Firewall
FW_STATUS="Unknown"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status | head -n 1)
    FW_STATUS="UFW: $UFW_STATUS"
elif command -v firewall-cmd &> /dev/null; then
    if firewall-cmd --state &> /dev/null; then
        FW_STATUS="Firewalld: Running"
    else
        FW_STATUS="Firewalld: Not Running"
    fi
fi
print_property "Firewall Status" "$FW_STATUS"

# SELinux
if [ -f /etc/selinux/config ]; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || sestatus 2>/dev/null | grep "Current mode" | awk '{print $3}')
    print_property "SELinux" "$SELINUX_STATUS"
else
    print_property "SELinux" "Not Installed"
fi

# Antivirus (Check for common Linux AV processes)
AV_STATUS="None Detected"
if pgrep -x "clamd" > /dev/null || pgrep -x "fsavd" > /dev/null || pgrep -x "savscand" > /dev/null; then
    AV_STATUS="Active Process Detected"
fi
print_property "Antivirus" "$AV_STATUS"


# ====================================================
# ADMIN DIAGNOSTICS (only runs if run as root)
# ====================================================

if [ "$IS_ROOT" = true ]; then
    print_header "ADMIN DIAGNOSTICS"

    # ------------------------------------------------------
    ## Disk Health (SMART)
    # ------------------------------------------------------
    print_subheader "Disk Health (S.M.A.R.T.)"
    
    if command -v smartctl &> /dev/null; then
        # Get list of devices
        DEVICES=$(lsblk -d -n -o name | grep -E "sd|nvme|vd")
        for DEV in $DEVICES; do
            echo -e "--- /dev/$DEV ---"
            smartctl -H "/dev/$DEV" | grep "SMART overall-health"
        done
    else
        print_property "S.M.A.R.T." "smartctl not installed"
    fi

    # ------------------------------------------------------
    ## Failed Services
    # ------------------------------------------------------
    print_subheader "Failed Services"
    
    if command -v systemctl &> /dev/null; then
        FAILED_UNITS=$(systemctl list-units --state=failed --no-pager --plain | grep ".service" | wc -l)
        print_property "Failed Services" "$FAILED_UNITS"
        if [ "$FAILED_UNITS" -gt 0 ]; then
            systemctl list-units --state=failed --no-pager | grep ".service"
        fi
    else
        print_property "Systemd" "Not found"
    fi

    # ------------------------------------------------------
    ## Listening Ports
    # ------------------------------------------------------
    print_subheader "Listening Ports"
    
    if command -v ss &> /dev/null; then
        ss -tulpen | head -n 10
    elif command -v netstat &> /dev/null; then
        netstat -tulpen | head -n 10
    else
        print_property "Network Info" "ss/netstat not found"
    fi

    # ------------------------------------------------------
    ## System Logs
    # ------------------------------------------------------
    print_subheader "Recent System Errors"
    
    if command -v journalctl &> /dev/null; then
        echo "Last 5 Error Logs:"
        journalctl --since "1 hour ago" -p err --no-pager -n 5
    fi

else
    print_header "ADMIN DIAGNOSTICS"
    echo -e "Script was not run as Root. Skipping admin-only diagnostics."
    echo -e "Please re-run with sudo to see Disk Health, Failed Services, and detailed logs."
fi

# End of script
