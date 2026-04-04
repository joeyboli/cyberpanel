#!/bin/sh
# CyberPanel Upgrade Bootstrap - Fixed for Fork

# FORCE BRANCH TO FORK VERSION
BRANCH_NAME="v2.4.5"
FORK_USER="joeyboli"

echo "Bootstrapping Upgrade from Fork: ${FORK_USER} ${BRANCH_NAME}..."

rm -f /usr/local/cyberpanel_upgrade.sh
# Pull the fixed upgrade script
wget -O /usr/local/cyberpanel_upgrade.sh https://raw.githubusercontent.com/${FORK_USER}/cyberpanel/${BRANCH_NAME}/cyberpanel_upgrade.sh
chmod 700 /usr/local/cyberpanel_upgrade.sh
/usr/local/cyberpanel_upgrade.sh