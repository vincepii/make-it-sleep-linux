#! /bin/bash

set -e

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SYSTEMD_PATH=/etc/systemd/system/
SYSTEMD_UNIT_NAME=disable-wakeup

# Check that we have sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script requires root privileges (use sudo).${NC}"
    exit 1
fi

# Function to print a list of items with better formatting
print_list() {
  local IFS=$'\n'
  echo -e "\t- $@"
}

# Get all the currently enabled wakeup signals
enabled_signals=$(cat /proc/acpi/wakeup | grep ' *enabled' | awk '{print $1}')

echo "Currently enabled wake-up signals:"
print_list $enabled_signals

# Default to disabling XHC (USB) wake-up, as it's a common cause of unwanted wake-ups
disable_defaults=("XHC")
to_disable=()

echo -n "Do you want to disable (${disable_defaults[*]}) wake up signal? "
echo -n "Press y to confirm or N to provide a list of wake-up signals to disable (y/N) "
read -n 1 -s response
echo

if [[ "$response" == "y" || "$response" == "Y" ]]; then
    to_disable=("${disable_defaults[@]}")
else
    echo "Enter space-separated wake-up signals to disable (leave empty for none):"
    read -ra custom_disable
    to_disable=("${custom_disable[@]}")
fi

if [[ ${#to_disable[@]} -gt 0 ]]; then
    echo "The following wake-up signals will be disabled:"
    print_list "${to_disable[@]}"

    # Construct the ExecStart command
    exec_start_commands=""
    for signal in "${to_disable[@]}"; do
        exec_start_commands+="echo '$signal' > /proc/acpi/wakeup && "
    done
    # Remove the trailing " && "
    exec_start_commands="${exec_start_commands% && }"

    echo -n "Proceed with creating and enabling a systemd unit to disable these at boot? (y/N) "
    read -n 1 -s proceed
    echo

    if [[ "$proceed" == "y" || "$proceed" == "Y" ]]; then
        echo -e "${GREEN}Installing systemd unit...${NC}"

        cat <<EOF > "${SYSTEMD_PATH}/${SYSTEMD_UNIT_NAME}.service"
[Unit]
Description=Disable specified ACPI wake-up signals

[Service]
Type=oneshot
ExecStart=/bin/sh -c "$exec_start_commands"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable "${SYSTEMD_UNIT_NAME}.service"
        systemctl start "${SYSTEMD_UNIT_NAME}.service"
        echo -e "${GREEN}Systemd unit '${SYSTEMD_UNIT_NAME}.service' installed and started.${NC}"
        echo "To undo these changes:"
        echo -e "\tsudo systemctl disable \"${SYSTEMD_UNIT_NAME}.service\""
        echo -e "\tsudo systemctl stop \"${SYSTEMD_UNIT_NAME}.service\""
        echo -e "\tsudo rm \"${SYSTEMD_PATH}/${SYSTEMD_UNIT_NAME}.service\""
        echo -e "\tsudo systemctl daemon-reload"

    else
        echo "Exiting (no changes made)."
        exit 0
    fi
else
    echo "No wake-up signals selected to disable. Exiting."
    exit 0
fi

exit 0