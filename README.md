# linfo - Linux System Health Check Script

This Bash script provides a rapid snapshot of a Linux machine's health and configuration. It generates a two-part report: a System Summary for general info, and Admin Diagnostics (if run with root privileges) for deep-dive troubleshooting.

## Key Features
* Identity & Health: OS distro name, version, uptime, pending reboots, and live CPU/Memory usage.
* Network Status: IPv4/IPv6, Gateway, Public IP, DNS, and connectivity tests.
* Hardware & Storage: Drive space, disk health, displays, and connected peripherals.
* Security Posture: Firewall profiles, SELinux, Endpoint Protection information.
* Advanced Diagnostics: Failed services, pending updates, critical system events, and listening ports.

## Prerequisites
* Bash 4.0+ (Zsh compatible)
* common utilitarian tools (ip, df, free, etc.)

### Optional prerequisites:
* iw (for WiFi info)
* CUPS (for printer info)
* smartctl (for HDD info)


## Usage
The program can be run in one of two ways: locally or over the internet.

### Local usage
Download linfo.sh and run, preferably with sudo.

## License
MIT
