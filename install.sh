#!/bin/sh
# CyberPanel Launcher - Fixed for Fork v2.4.5

OUTPUT=$(cat /etc/*release)
if echo $OUTPUT | grep -q -E "Ubuntu 22.04|Ubuntu 24.04" ; then
    echo "Detecting Ubuntu 22/24..."
    apt install -y -qq wget curl
    SERVER_OS="Ubuntu"
elif echo $OUTPUT | grep -q -E "AlmaLinux 8|AlmaLinux 9|AlmaLinux 10" ; then
    echo "Detecting AlmaLinux..."
    yum install curl wget -y 1> /dev/null
    SERVER_OS="CentOS8"
else
    echo "OS not specifically optimized, continuing with defaults..."
fi

rm -f cyberpanel.sh
# Forced to joeyboli fork v2.4.5 to ensure Ubuntu 24.04 compatibility
curl --silent -o cyberpanel.sh "https://raw.githubusercontent.com/joeyboli/cyberpanel/v2.4.5/cyberpanel.sh"
chmod +x cyberpanel.sh
./cyberpanel.sh $@