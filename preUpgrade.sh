#!/bin/sh
# SAVE AS: /usr/local/preUpgrade.sh

# Force Fork branch instead of querying cyberpanel.net
BRANCH_NAME="v2.4.5"
FORK_USER="joeyboli"

echo "Bootstrapping Upgrade from Fork: ${FORK_USER} ${BRANCH_NAME}..."

rm -f /usr/local/cyberpanel_upgrade.sh
wget -O /usr/local/cyberpanel_upgrade.sh https://raw.githubusercontent.com/${FORK_USER}/cyberpanel/v2.4.5/cyberpanel_upgrade.sh
chmod 700 /usr/local/cyberpanel_upgrade.sh
/usr/local/cyberpanel_upgrade.sh
