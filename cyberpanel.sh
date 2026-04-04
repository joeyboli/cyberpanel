#!/bin/bash

#set -e -o pipefail
#set -x
#set -u

# Logging setup
LOG_DIR="/var/log/cyberpanel"
LOG_FILE="$LOG_DIR/cyberpanel_install_$(date +%Y%m%d_%H%M%S).log"
DEBUG_LOG_FILE="$LOG_DIR/cyberpanel_install_debug_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR" 2>/dev/null || {
    LOG_DIR="/tmp/cyberpanel_logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/cyberpanel_install_$(date +%Y%m%d_%H%M%S).log"
    DEBUG_LOG_FILE="$LOG_DIR/cyberpanel_install_debug_$(date +%Y%m%d_%H%M%S).log"
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [INFO] $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [ERROR] $message" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [WARNING] $message" | tee -a "$LOG_FILE"
}

log_debug() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [DEBUG] $message" >> "$DEBUG_LOG_FILE"
}

log_command() {
    local command="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [COMMAND] Executing: $command" >> "$DEBUG_LOG_FILE"
    local output
    local exit_code
    output=$($command 2>&1)
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "[$timestamp] [COMMAND] Success: $command" >> "$DEBUG_LOG_FILE"
        [ -n "$output" ] && echo "[$timestamp] [OUTPUT] $output" >> "$DEBUG_LOG_FILE"
    else
        echo "[$timestamp] [COMMAND] Failed (exit code: $exit_code): $command" >> "$DEBUG_LOG_FILE"
        [ -n "$output" ] && echo "[$timestamp] [ERROR OUTPUT] $output" >> "$DEBUG_LOG_FILE"
    fi
    return $exit_code
}

log_function_start() {
    local function_name="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [FUNCTION] Starting: $function_name" | tee -a "$LOG_FILE"
    echo "[$timestamp] [FUNCTION] Starting: $function_name with args: ${@:2}" >> "$DEBUG_LOG_FILE"
}

log_function_end() {
    local function_name="$1"
    local exit_code="${2:-0}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ $exit_code -eq 0 ]; then
        echo "[$timestamp] [FUNCTION] Completed: $function_name" >> "$DEBUG_LOG_FILE"
    else
        echo "[$timestamp] [FUNCTION] Failed: $function_name (exit code: $exit_code)" | tee -a "$LOG_FILE"
    fi
}

log_info "CyberPanel installation started"
log_info "Log file: $LOG_FILE"
log_info "Debug log file: $DEBUG_LOG_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# FORK CONFIGURATION
# All git operations point to joeyboli/cyberpanel on the stable branch.
# ─────────────────────────────────────────────────────────────────────────────
FORK_USER="joeyboli"
FORK_BRANCH="v2.4.5"
FORK_CLONE_URL="https://github.com/${FORK_USER}/cyberpanel.git"
FORK_CONTENT_URL="https://raw.githubusercontent.com/${FORK_USER}/cyberpanel"

# ─────────────────────────────────────────────────────────────────────────────

Sudo_Test=$(set)

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

install_package() {
    local package="$1"
    case "$Server_OS" in
        "CentOS"|"openEuler")
            if [[ "$Server_OS_Version" -ge 8 ]]; then
                dnf install -y "$package"
            else
                yum install -y "$package"
            fi
            ;;
        "Ubuntu")
            DEBIAN_FRONTEND=noninteractive apt install -y "$package"
            ;;
    esac
}

manage_service() {
    local service="$1"
    local action="$2"
    systemctl "$action" "$service"
}

install_dev_tools() {
    case "$Server_OS" in
        "CentOS"|"openEuler")
            yum groupinstall "Development Tools" -y
            yum install autoconf automake zlib-devel openssl-devel expat-devel \
                pcre-devel libmemcached-devel cyrus-sasl* -y
            ;;
        "Ubuntu")
            DEBIAN_FRONTEND=noninteractive apt install build-essential zlib1g-dev \
                libexpat1-dev openssl libssl-dev libsasl2-dev libpcre3-dev git -y
            ;;
    esac
}

install_php_packages() {
    local php_extension="$1"
    case "$Server_OS" in
        "CentOS"|"openEuler")
            install_package "lsphp??-${php_extension} lsphp??-pecl-${php_extension}"
            ;;
        "Ubuntu")
            install_package "lsphp*-${php_extension}"
            ;;
    esac
}

configure_memcached() {
    if [[ "$Server_OS" = "CentOS" ]] || [[ "$Server_OS" = "openEuler" ]]; then
        sed -i 's|OPTIONS=""|OPTIONS="-l 127.0.0.1 -U 0"|g' /etc/sysconfig/memcached
    fi
}

setup_epel_repo() {
    case "$Server_OS_Version" in
        "7")
            rpm --import https://cyberpanel.sh/dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7
            yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            Check_Return "yum repo" "no_exit"
            ;;
        "8")
            rpm --import https://cyberpanel.sh/dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8
            yum install -y https://cyberpanel.sh/dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
            Check_Return "yum repo" "no_exit"
            ;;
        "9")
            yum install -y https://cyberpanel.sh/dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
            Check_Return "yum repo" "no_exit"
            ;;
        "10")
            yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
            Check_Return "yum repo" "no_exit"
            ;;
    esac
}

setup_mariadb_repo() {
    if [[ "$Server_OS_Version" = "7" ]]; then
        cat <<EOF >/etc/yum.repos.d/MariaDB.repo
[mariadb]
name     = MariaDB 10.4 — CentOS 7
baseurl  = http://yum.mariadb.org/10.4/centos7-amd64
gpgkey   = https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck = 1
EOF
    elif [[ "$Server_OS_Version" = "8" ]]; then
        cat <<EOF >/etc/yum.repos.d/MariaDB.repo
[mariadb]
name            = MariaDB 10.11 — RHEL 8
baseurl         = http://yum.mariadb.org/10.11/rhel8-amd64
module_hotfixes = 1
gpgkey          = https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck        = 1
EOF
    elif [[ "$Server_OS_Version" = "9" ]] && uname -m | grep -q 'x86_64'; then
        cat <<EOF >/etc/yum.repos.d/MariaDB.repo
[mariadb]
name     = MariaDB 10.11 — RHEL 9
baseurl  = http://yum.mariadb.org/10.11/rhel9-amd64/
gpgkey   = https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
enabled  = 1
gpgcheck = 1
EOF
    elif [[ "$Server_OS_Version" = "10" ]] && uname -m | grep -q 'x86_64'; then
        cat <<EOF >/etc/yum.repos.d/MariaDB.repo
[mariadb]
name            = MariaDB 10.11 — RHEL 10 / AlmaLinux 10
baseurl         = http://yum.mariadb.org/10.11/rhel10-amd64/
module_hotfixes = 1
gpgkey          = https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
enabled         = 1
gpgcheck        = 1
EOF
    fi
}

configure_php_timezone() {
    local php_version="$1"
    local php_ini_path=$(find "$php_version" -name php.ini)

    "${php_version}/bin/phpize"
    ./configure --with-php-config="${php_version}/bin/php-config"
    make
    make install

    if [[ "$Server_OS" = "CentOS" ]] || [[ "$Server_OS" = "openEuler" ]]; then
        if [[ ! -d "${php_version}/tmp" ]]; then
            mkdir "${php_version}/tmp"
        fi
        "${php_version}/bin/pecl" channel-update pecl.php.net
        "${php_version}/bin/pear" config-set temp_dir "${php_version}/tmp"
        echo "extension=timezonedb.so" > "${php_version}/etc/php.d/20-timezone.ini"
    else
        echo "extension=timezonedb.so" > \
            "/usr/local/lsws/${php_version:16:7}/etc/php/${php_version:21:1}.${php_version:22:1}/mods-available/20-timezone.ini"
    fi

    make clean
    sed -i 's|expose_php = On|expose_php = Off|g'                 "$php_ini_path"
    sed -i 's|mail.add_x_header = On|mail.add_x_header = Off|g'  "$php_ini_path"
}

Debug_Log() {
    echo -e "\n${1}=${2}\n" >> "/var/log/cyberpanel_debug_$(date +"%Y-%m-%d")_${Random_Log_Name}.log"
}

Debug_Log2() {
    Check_Server_IP "$@" >/dev/null 2>&1
    echo -e "\n${1}" >> /var/log/installLogs.txt
    curl --max-time 20 \
        -d '{"ipAddress": "'"$Server_IP"'", "InstallCyberPanelStatus": "'"$1"'"}' \
        -H "Content-Type: application/json" \
        -X POST https://cloud.cyberpanel.net/servers/RecvData >/dev/null 2>&1
}

Branch_Check() {
    local branch_input="${1//[[:space:]]/}"
    if [[ "$branch_input" = *.*.* ]]; then
        Output=$(awk -v num1="$Base_Number" -v num2="$branch_input" \
            'BEGIN { print "num1", (num1 < num2 ? "<" : ">="), "num2" }')
        if [[ $Output = *">="* ]]; then
            echo -e "\nVersion must be higher than 1.9.4"
            exit
        else
            if [[ "$branch_input" == v* ]]; then
                Branch_Name="$branch_input"
            else
                Branch_Name="v$branch_input"
            fi
            echo -e "\nBranch set to $Branch_Name..."
        fi
    else
        echo -e "\nInvalid version format."
        exit
    fi
}

License_Check() {
    License_Key="$1"
    echo -e "\nChecking LiteSpeed Enterprise license key..."
    if echo "$License_Key" | grep -q "^....-....-....-....$" && [[ ${#License_Key} = "19" ]]; then
        echo -e "\nLicense key set...\n"
    elif [[ ${License_Key,,} = "trial" ]]; then
        echo -e "\nTrial license set..."
        License_Key="Trial"
    else
        echo -e "\nLicense key seems incorrect, please verify (check for extra spaces).\n"
        exit
    fi
}

Check_Return() {
    local exit_code=$?
    if [[ $exit_code != "0" ]]; then
        log_error "Previous command failed with exit code: $exit_code"
        if [[ -n "$1" ]]; then
            echo -e "\n\n\n$1"
        fi
        echo -e "Above command failed..."
        Debug_Log2 "command failed, exiting. For more information read /var/log/installLogs.txt [404]"
        if [[ "$2" = "no_exit" ]]; then
            echo -e "\nRetrying..."
        else
            exit
        fi
    fi
}

Retry_Command() {
    local command="$1"
    log_debug "Starting retry command: $command"
    for i in {1..50}; do
        if [[ "$i" = "50" ]]; then
            echo "Command $1 failed 50 times, exiting..."
            log_error "Command failed after 50 retries: $1"
            exit 2
        else
            eval "$1" && break || {
                echo -e "\n$1 has failed $i times\nWaiting and retrying...\n"
                log_warning "Command failed, retry $i/50: $1"
                if [[ $i -le 4 ]]; then
                    sleep $((2**($i-1)))
                else
                    sleep 10
                fi
            }
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# SET DEFAULT VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

Set_Default_Variables() {
    log_function_start "Set_Default_Variables"

    echo -e "Fetching latest data from CyberPanel server...\n"
    echo -e "This may take a few seconds..."
    log_info "Fetching latest data from CyberPanel server"

    Silent="Off"
    Server_Edition="OLS"
    Admin_Pass="1234567"
    Memcached="Off"
    Redis="Off"
    Postfix_Switch="On"
    PowerDNS_Switch="On"
    PureFTPd_Switch="On"
    Server_IP=""
    Server_Country="Unknow"
    Server_OS=""
    Server_OS_Version=""
    Server_Provider='Undefined'
    Watchdog="On"
    Redis_Hosting="No"

    # Fetch version info for display purposes only — branch is forced to stable
    Temp_Value=$(curl --silent --max-time 30 -4 https://cyberpanel.net/version.txt)
    Panel_Version=${Temp_Value:12:3}
    Panel_Build=${Temp_Value:25:1}

    # Force stable branch regardless of fetched version
    Branch_Name="${FORK_BRANCH}"
    echo -e "\nUsing fork: ${FORK_CLONE_URL}"
    echo -e "Branch forced to: ${Branch_Name}\n"
    log_info "Fork: ${FORK_CLONE_URL} | Branch: ${Branch_Name}"

    Base_Number="1.9.3"
    Total_RAM=$(free -m | awk '/Mem:/ { print $2 }')
    Remote_MySQL="Off"
    Final_Flags=()

    # Git URLs — always use the joeyboli fork (set here as defaults,
    # Pre_Install_Setup_Git_URL will also set these but fork values take priority)
    Git_User="${FORK_USER}"
    Git_Content_URL="${FORK_CONTENT_URL}"
    Git_Clone_URL="${FORK_CLONE_URL}"

    LSWS_Latest_URL="https://cyberpanel.sh/update.litespeedtech.com/ws/latest.php"
    LSWS_Tmp=$(curl --silent --max-time 30 -4 "$LSWS_Latest_URL")
    LSWS_Stable_Line=$(echo "$LSWS_Tmp" | grep "LSWS_STABLE")
    LSWS_Stable_Version=$(expr "$LSWS_Stable_Line" : '.*LSWS_STABLE=\(.*\) BUILD .*')

    Enterprise_Flag=""
    License_Key=""
    Debug_Log2 "Starting installation..,1"

    log_debug "Variables set — Edition: $Server_Edition | RAM: ${Total_RAM}MB | Fork: ${FORK_CLONE_URL} | Branch: ${Branch_Name}"
    log_function_end "Set_Default_Variables"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK ROOT
# ─────────────────────────────────────────────────────────────────────────────

Check_Root() {
    log_function_start "Check_Root"
    echo -e "\nChecking root privileges..."
    log_info "Checking root privileges"

    if echo "$Sudo_Test" | grep SUDO >/dev/null; then
        echo -e "\nYou are using SUDO, please run as root user."
        echo -e "\nRun: sudo su - (do NOT miss the -) then re-run the installer."
        log_error "Not running as root user - SUDO detected"
        log_function_end "Check_Root" 1
        exit
    fi

    if [[ $(id -u) != 0 ]] >/dev/null; then
        echo -e "\nYou must run as root to install CyberPanel.\n"
        echo -e 'Or run: sudo su -c "sh <(curl https://cyberpanel.sh || wget -O - https://cyberpanel.sh)"'
        log_error "Not running as root user - UID is not 0"
        log_function_end "Check_Root" 1
        exit 1
    else
        echo -e "\nRunning as root ✓\n"
        log_info "Root user verified"
    fi

    log_function_end "Check_Root"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK SERVER IP
# ─────────────────────────────────────────────────────────────────────────────

Check_Server_IP() {
    log_function_start "Check_Server_IP"
    log_debug "Fetching server IP address"

    Server_IP=$(curl --silent --max-time 30 -4 https://cyberpanel.sh/?ip)

    if [[ $Server_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "Valid IP detected: $Server_IP"
        log_info "Valid server IP detected: $Server_IP"
    else
        echo -e "Cannot detect IP, exiting..."
        Debug_Log2 "Can not detect IP. [404]"
        log_error "Failed to detect valid server IP address"
        log_function_end "Check_Server_IP" 1
        exit
    fi

    echo -e "\nChecking server location...\n"

    if [[ "$Server_Country" != "CN" ]]; then
        Server_Country=$(curl --silent --max-time 10 -4 https://cyberpanel.sh/?country)
        if [[ ${#Server_Country} != "2" ]]; then
            Server_Country="Unknow"
        fi
    fi

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Server_IP" "$Server_IP"
        Debug_Log "Server_Country" "$Server_Country"
    fi

    if [[ "$*" = *"--mirror"* ]]; then
        Server_Country="CN"
        echo -e "Forced CN mirror mode via --mirror flag.\n"
    fi

    if [[ "$Server_Country" = *"CN"* ]]; then
        Server_Country="CN"
        echo -e "CN server detected — using mirror servers.\n"
        log_info "Server country set to CN - will use mirror servers"
    fi

    log_debug "Server location: $Server_Country, IP: $Server_IP"
    log_function_end "Check_Server_IP"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK OS
# ─────────────────────────────────────────────────────────────────────────────

Check_OS() {
    log_function_start "Check_OS"

    if [[ ! -f /etc/os-release ]]; then
        log_error "Unable to detect OS - /etc/os-release not found"
        echo -e "Unable to detect the operating system.\n"
        log_function_end "Check_OS" 1
        exit
    fi

    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "$XDG_CURRENT_DESKTOP detected — CyberPanel requires a server OS."
        exit
    fi

    if ! uname -m | grep -qE 'x86_64|aarch64'; then
        echo -e "x86_64 or ARM (aarch64) required.\n"
        exit
    fi

    if   grep -q -E "CentOS Linux 7|CentOS Linux 8|CentOS Stream"  /etc/os-release; then Server_OS="CentOS"
    elif grep -q "Red Hat Enterprise Linux"                          /etc/os-release; then Server_OS="RedHat"
    elif grep -q "AlmaLinux-8"                                       /etc/os-release; then Server_OS="AlmaLinux"
    elif grep -q "AlmaLinux-9"                                       /etc/os-release; then Server_OS="AlmaLinux"
    elif grep -q "AlmaLinux-10"                                      /etc/os-release; then Server_OS="AlmaLinux"
    elif grep -q -E "CloudLinux 7|CloudLinux 8"                      /etc/os-release; then Server_OS="CloudLinux"
    elif grep -q -E "Rocky Linux"                                    /etc/os-release; then Server_OS="RockyLinux"
    elif grep -q -E "Ubuntu 18.04|Ubuntu 20.04|Ubuntu 20.10|Ubuntu 22.04|Ubuntu 24.04" /etc/os-release; then Server_OS="Ubuntu"
    elif grep -q -E "Debian GNU/Linux 11|Debian GNU/Linux 12|Debian GNU/Linux 13"       /etc/os-release; then Server_OS="Debian"
    elif grep -q -E "openEuler 20.03|openEuler 22.03"               /etc/os-release; then Server_OS="openEuler"
    else
        echo -e "Unsupported OS detected. See cyberpanel.net for supported systems."
        Debug_Log2 "Unsupported OS [404]"
        exit
    fi

    Server_OS_Version=$(grep VERSION_ID /etc/os-release | awk -F[=,] '{print $2}' | tr -d '"' | head -c2 | tr -d .)

    echo -e "System: $Server_OS $Server_OS_Version detected.\n"
    log_info "Operating system detected: $Server_OS $Server_OS_Version"

    # Normalize OS family
    if [[ $Server_OS = "CloudLinux" ]] || [[ "$Server_OS" = "AlmaLinux" ]] \
    || [[ "$Server_OS" = "RockyLinux" ]] || [[ "$Server_OS" = "RedHat" ]]; then
        Server_OS="CentOS"
    elif [[ "$Server_OS" = "Debian" ]]; then
        Server_OS="Ubuntu"
    fi

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Server_OS" "$Server_OS $Server_OS_Version"
    fi

    log_function_end "Check_OS"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK VIRTUALIZATION
# ─────────────────────────────────────────────────────────────────────────────

Check_Virtualization() {
    log_function_start "Check_Virtualization"
    echo -e "Checking virtualization type..."
    log_info "Checking virtualization type"

    if hostnamectl | grep -q "Virtualization: openvz"; then
        echo -e "OpenVZ detected — applying service overrides.\n"
        log_info "OpenVZ detected"

        if [[ ! -d /etc/systemd/system/pure-ftpd.service.d ]]; then
            mkdir /etc/systemd/system/pure-ftpd.service.d
            printf '[Service]\nPIDFile=/run/pure-ftpd.pid\n' \
                > /etc/systemd/system/pure-ftpd.service.d/override.conf
            echo -e "PureFTPd service file modified for OpenVZ."
        fi

        if [[ ! -d /etc/systemd/system/lshttpd.service.d ]]; then
            mkdir /etc/systemd/system/lshttpd.service.d
            printf '[Service]\nPIDFile=/tmp/lshttpd/lshttpd.pid\n' \
                > /etc/systemd/system/lshttpd.service.d/override.conf
            echo -e "LiteSpeed service file modified for OpenVZ."
        fi

        if [[ ! -d /etc/systemd/system/spamassassin.service.d ]]; then
            mkdir /etc/systemd/system/spamassassin.service.d
            printf '[Service]\nPIDFile=/run/spamassassin.pid\n' \
                > /etc/systemd/system/spamassassin.service.d/override.conf
            echo -e "SpamAssassin service file modified for OpenVZ."
        fi
    fi

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Server_Virtualization" "$(hostnamectl | grep "Virtualization")"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK EXISTING PANEL
# ─────────────────────────────────────────────────────────────────────────────

Check_Panel() {
    log_function_start "Check_Panel"
    log_info "Checking for existing control panels"

    if [[ -d /usr/local/cpanel ]]; then
        echo -e "\ncPanel detected — aborting.\n"
        Debug_Log2 "cPanel detected...exit... [404]"
        exit
    elif [[ -d /usr/local/directadmin ]]; then
        echo -e "\nDirectAdmin detected — aborting.\n"
        Debug_Log2 "DirectAdmin detected...exit... [404]"
        exit
    elif [[ -d /etc/httpd/conf/plesk.conf.d/ ]] || [[ -d /etc/apache2/plesk.conf.d/ ]]; then
        echo -e "\nPlesk detected — aborting.\n"
        Debug_Log2 "Plesk detected...exit... [404]"
        exit
    elif [[ -d /usr/local/panel/ ]]; then
        echo -e "\nOpenPanel detected — aborting.\n"
        Debug_Log2 "OpenPanel detected...exit... [404]"
        exit
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK CONFLICTING PROCESSES
# ─────────────────────────────────────────────────────────────────────────────

Check_Process() {
    log_function_start "Check_Process"
    log_info "Checking for conflicting processes"

    local services=("httpd" "apache2" "named" "exim")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            manage_service "$service" "stop"
            manage_service "$service" "disable"
            manage_service "$service" "mask"
            echo -e "\n$service detected and disabled.\n"
            log_warning "$service process detected and disabled"
        fi
    done

    log_function_end "Check_Process"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK PROVIDER
# ─────────────────────────────────────────────────────────────────────────────

Check_Provider() {
    log_function_start "Check_Provider"
    log_info "Detecting server provider"

    if hash dmidecode >/dev/null 2>&1; then
        if   [[ "$(dmidecode -s bios-vendor)" = "Google" ]];                              then Server_Provider="Google Cloud Platform"
        elif [[ "$(dmidecode -s bios-vendor)" = "DigitalOcean" ]];                        then Server_Provider="Digital Ocean"
        elif [[ "$(dmidecode -s system-product-name | cut -c 1-7)" = "Alibaba" ]];        then Server_Provider="Alibaba Cloud"
        elif [[ "$(dmidecode -s system-manufacturer)" = "Microsoft Corporation" ]];       then Server_Provider="Microsoft Azure"
        elif [[ -d /usr/local/qcloud ]];                                                   then Server_Provider="Tencent Cloud"
        else Server_Provider="Undefined"
        fi
    else
        Server_Provider='Undefined'
    fi

    if [[ -f /sys/devices/virtual/dmi/id/product_uuid ]]; then
        if [[ "$(cut -c 1-3 /sys/devices/virtual/dmi/id/product_uuid)" = 'EC2' ]] \
        && [[ -d /home/ubuntu ]]; then
            Server_Provider='Amazon Web Service'
        fi
    fi

    log_info "Provider detected: $Server_Provider"

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Server_Provider" "$Server_Provider"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────

Show_Help() {
    echo -e "\nCyberPanel Installer — Fork: ${FORK_CLONE_URL} | Branch: ${FORK_BRANCH}\n"
    echo -e "Usage: sh <(curl cyberpanel.sh) [OPTIONS]\n"
    echo -e "  -v, --version  ols | TRIAL | SERIAL   Web server edition (default: ols)"
    echo -e "  -p, --password d | r | <password>      Admin password"
    echo -e "                   d = default (1234567)"
    echo -e "                   r = random 16-char"
    echo -e "  -m, --minimal  [postfix|pureftpd|powerdns]  Skip optional components"
    echo -e "  -a, --addons                           Install Memcached + Redis"
    echo -e "  -b, --branch   X.Y.Z                  Install specific version"
    echo -e "      --mirror                           Force CN mirror servers\n"
    echo -e "Examples:"
    echo -e "  sh <(curl cyberpanel.sh) -v ols -p r"
    echo -e "  sh <(curl cyberpanel.sh) -v MY-LIC-KEY -a -p mypassword\n"
}

Check_Argument() {
    log_function_start "Check_Argument" "$@"

    if [[ "$#" = "0" ]] || [[ "$#" = "1" && "$1" = "--debug" ]] \
    || [[ "$#" = "1" && "$1" = "--mirror" ]]; then
        echo -e "\nInitialized (interactive mode).\n"
    else
        if [[ $1 = "help" ]]; then
            Show_Help
            exit
        elif [[ $1 = "default" ]]; then
            echo -e "\nStarting default installation...\n"
            Silent="On"
            Postfix_Switch="On"
            PowerDNS_Switch="On"
            PureFTPd_Switch="On"
            Server_Edition="OLS"
            Admin_Pass="1234567"
            Memcached="On"
            Redis="On"
        else
            while [[ -n "${1}" ]]; do
                case $1 in
                    -v | --version)
                        shift
                        if [[ "${1}" = "" ]]; then
                            Show_Help; exit
                        elif [[ "${1^^}" = "OLS" ]]; then
                            Server_Edition="OLS"
                            Silent="On"
                            echo -e "\nSet to OpenLiteSpeed."
                        else
                            Server_Edition="Enterprise"
                            License_Key="${1}"
                            Silent="On"
                            echo -e "\nSet to LiteSpeed Enterprise with key ${1}."
                        fi
                        ;;
                    -p | --password)
                        shift
                        if [[ ${1} = "" || ${1} = "d" ]]; then
                            Admin_Pass="1234567"
                        elif [[ ${1} = "r" ]] || [[ $1 = "random" ]]; then
                            Admin_Pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16; echo '')
                        else
                            if [[ ${#1} -lt 8 ]]; then
                                echo -e "\nPassword too short (minimum 8 characters).\n"
                                exit
                            fi
                            Admin_Pass="${1}"
                        fi
                        echo -e "\nPassword configured."
                        ;;
                    -b | --branch)
                        shift
                        Branch_Check "${1}"
                        ;;
                    -m | --minimal)
                        if ! echo "$@" | grep -q -i "postfix\|pureftpd\|powerdns"; then
                            Postfix_Switch="Off"
                            PowerDNS_Switch="Off"
                            PureFTPd_Switch="Off"
                            echo -e "\nMinimal installation selected."
                        else
                            [[ "${*^^}" = *"POSTFIX"*  ]] && Postfix_Switch="On"  && echo -e "\nPostfix enabled."
                            [[ "${*^^}" = *"PUREFTPD"* ]] && PureFTPd_Switch="On" && echo -e "\nPureFTPd enabled."
                            [[ "${*^^}" = *"POWERDNS"* ]] && PowerDNS_Switch="On" && echo -e "\nPowerDNS enabled."
                        fi
                        ;;
                    -a | --addons)
                        Memcached="On"
                        Redis="On"
                        echo -e "\nAddons (Memcached + Redis) enabled."
                        ;;
                    -h | --help)
                        Show_Help; exit
                        ;;
                    --debug)
                        echo -e "\nDebug logging enabled.\n"
                        ;;
                    --mirror)
                        echo -e "\nForced CN mirror mode.\n"
                        ;;
                    *)
                        if [[ "${1^^}" != *"POSTFIX"* ]] && [[ "${1^^}" != *"PUREFTPD"* ]] \
                        && [[ "${1^^}" != *"POWERDNS"* ]]; then
                            echo -e "\nUnknown argument: $1\n"
                            Show_Help; exit
                        fi
                        ;;
                esac
                shift
            done
        fi
    fi

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Arguments" "${@}"
    fi

    Debug_Log2 "Initialization completed..,2"
}

Argument_Mode() {
    if [[ "${Server_Edition^^}" = "OLS" ]]; then
        Server_Edition="OLS"
        echo -e "\nOpenLiteSpeed selected."
    else
        License_Check "$License_Key"
    fi

    if [[ $Admin_Pass = "d" ]]; then
        Admin_Pass="1234567"
        echo -e "\nAdmin password: $Admin_Pass"
    elif [[ $Admin_Pass = "r" ]]; then
        Admin_Pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16; echo '')
        echo -e "\nAdmin password (random): $Admin_Pass"
    else
        echo -e "\nAdmin password: $Admin_Pass"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE MODE
# ─────────────────────────────────────────────────────────────────────────────

Interactive_Mode() {
    echo -e "\n\tCyberPanel Installer"
    echo -e "\tFork   : ${FORK_CLONE_URL}"
    echo -e "\tBranch : ${FORK_BRANCH}\n"
    echo -e "1. Install CyberPanel."
    echo -e "2. Exit.\n"
    read -r -p "  Please enter the number [1-2]: " Input_Number
    echo ""
    case "$Input_Number" in
        1) Interactive_Mode_Set_Parameter ;;
        2) exit ;;
        *) echo -e "Invalid choice.\n"; exit ;;
    esac
}

Interactive_Mode_Set_Parameter() {
    echo -e "\n\tCyberPanel Installer"
    echo -e "\tFork   : ${FORK_CLONE_URL}"
    echo -e "\tBranch : ${FORK_BRANCH}"
    echo -e "\n\tRAM  : $(free -m | awk 'NR==2{printf "%s/%s MB (%.2f%%)", $3,$2,$3*100/$2}')"
    echo -e "\tDisk : $(df -h | awk '$NF=="/"{printf "%d/%d GB (%s)", $3,$2,$5}') (min 10 GB free)\n"
    echo -e "1. Install CyberPanel with OpenLiteSpeed."
    echo -e "2. Install CyberPanel with LiteSpeed Enterprise."
    echo -e "3. Exit.\n"

    read -r -p "  Please enter the number [1-3]: " Input_Number
    echo ""
    case "$Input_Number" in
        1) Server_Edition="OLS" ;;
        2) Interactive_Mode_License_Input ;;
        3) exit ;;
        *) echo -e "Invalid choice."; exit ;;
    esac

    # Full vs minimal
    echo -e "\nInstall full service? (PowerDNS + Postfix + Pure-FTPd)"
    printf "%s" "Full installation [Y/n]: "
    read -r Tmp_Input
    if [[ $(expr "x$Tmp_Input" : 'x[Yy]') -gt 1 ]] || [[ $Tmp_Input = "" ]]; then
        echo -e "\nFull installation selected."
        Postfix_Switch="On"; PowerDNS_Switch="On"; PureFTPd_Switch="On"
    else
        printf "\nInstall Postfix?   [Y/n]: "; read -r Tmp_Input
        [[ $Tmp_Input =~ ^(no|n|N) ]] && Postfix_Switch="Off"  || Postfix_Switch="On"

        printf "Install PowerDNS?  [Y/n]: "; read -r Tmp_Input
        [[ $Tmp_Input =~ ^(no|n|N) ]] && PowerDNS_Switch="Off" || PowerDNS_Switch="On"

        printf "Install PureFTPd?  [Y/n]: "; read -r Tmp_Input
        [[ $Tmp_Input =~ ^(no|n|N) ]] && PureFTPd_Switch="Off" || PureFTPd_Switch="On"
    fi

    # Remote MySQL
    echo -e "\nSetup Remote MySQL? (skips local MySQL install)"
    printf "%s" "(Default = No) Remote MySQL [y/N]: "
    read -r Tmp_Input
    if [[ $(expr "x$Tmp_Input" : 'x[Yy]') -gt 1 ]]; then
        Remote_MySQL="On"
        printf "Remote MySQL Hostname: ";  read -r MySQL_Host
        printf "Remote MySQL Database: ";  read -r MySQL_DB
        printf "Remote MySQL Username: ";  read -r MySQL_User
        read -r -s -p "Remote MySQL Password: " MySQL_Password; echo
        printf "Remote MySQL Port: ";      read -r MySQL_Port
    else
        echo -e "\nLocal MySQL selected."
    fi

    # Branch — note: we are already forcing stable, but allow override via input
    echo -e "\nPress Enter to use the forced branch (${FORK_BRANCH}), or type a specific version:"
    printf "%s" ""
    read -r Tmp_Input
    if [[ $Tmp_Input = "" ]]; then
        echo -e "Branch: ${Branch_Name}"
    else
        Branch_Check "$Tmp_Input"
    fi

    # Password — default to random
    Admin_Pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16; echo '')
    echo -e "\nAdmin password will be displayed at the end of installation.\n"

    # Addons
    echo -e "\nInstall Memcached + PHP extension?"
    printf "%s" "Please select [Y/n]: "
    read -r Tmp_Input
    [[ $Tmp_Input =~ ^(no|n|N) ]] && Memcached="Off" || { Memcached="On"; echo -e "\nMemcached: On\n"; }

    echo -e "\nInstall Redis + PHP extension?"
    printf "%s" "Please select [Y/n]: "
    read -r Tmp_Input
    [[ $Tmp_Input =~ ^(no|n|N) ]] && Redis="Off" || { Redis="On"; echo -e "\nRedis: On\n"; }

    # Watchdog
    echo -e "\nInstall WatchDog (beta) for web + database services?"
    echo -e "Type Yes or no (capital Y, default Yes):"
    read -r Tmp_Input
    if [[ $Tmp_Input = "Yes" ]] || [[ $Tmp_Input = "" ]]; then
        Watchdog="On"
        echo -e "\nWatchdog: On\n"
    else
        Watchdog="Off"
    fi
}

Interactive_Mode_License_Input() {
    Server_Edition="Enterprise"
    echo -e "\nServer RAM: ${Total_RAM} MB"
    echo -e "Type TRIAL for a trial license, or enter your LiteSpeed serial number.\n"
    printf "%s" "Serial number: "
    read -r License_Key
    if [[ -z "$License_Key" ]]; then
        echo -e "\nLicense key required.\n"; exit
    fi
    echo -e "Serial entered: $License_Key\n"
    printf "%s" "Confirm? [y/N]: "
    read -r Tmp_Input
    if [[ -z "$Tmp_Input" ]]; then
        echo -e "\nPlease type y to confirm.\n"; exit
    fi
    License_Check "$License_Key"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-INSTALL: SETUP REPOSITORIES
# ─────────────────────────────────────────────────────────────────────────────

Pre_Install_Setup_Repository() {
    log_function_start "Pre_Install_Setup_Repository"
    log_info "Setting up package repositories for $Server_OS $Server_OS_Version"

    if [[ $Server_OS = "CentOS" ]]; then
        log_debug "Importing LiteSpeed GPG key"
        rpm --import https://cyberpanel.sh/rpms.litespeedtech.com/centos/RPM-GPG-KEY-litespeed || \
            rpm --import https://rpms.litespeedtech.com/centos/RPM-GPG-KEY-litespeed

        yum clean all
        yum autoremove -y epel-release
        rm -f /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.rpmsave

        setup_epel_repo
        setup_mariadb_repo

        if [[ "$Server_OS_Version" = "9" ]] || [[ "$Server_OS_Version" = "10" ]]; then
            if uname -m | grep -q 'aarch64'; then
                /usr/bin/crb enable
                curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
                dnf install libxcrypt-compat -y
            fi

            if grep -q -E "AlmaLinux|Rocky Linux" /etc/os-release; then
                rpm -q dnf-plugins-core >/dev/null 2>&1 || dnf install -y dnf-plugins-core
                dnf config-manager --set-enabled crb >/dev/null 2>&1
            else
                dnf config-manager --set-enabled crb
            fi

            [[ "$Server_OS_Version" = "9"  ]] && yum install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm
            [[ "$Server_OS_Version" = "10" ]] && yum install -y https://rpms.remirepo.net/enterprise/remi-release-10.rpm
            Check_Return "yum repo" "no_exit"
        fi

        if [[ "$Server_OS_Version" = "8" ]]; then
            rpm --import https://cyberpanel.sh/www.centos.org/keys/RPM-GPG-KEY-CentOS-Official
            sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* >/dev/null 2>&1
            sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
                /etc/yum.repos.d/CentOS-* >/dev/null 2>&1
            dnf config-manager --set-enabled PowerTools >/dev/null 2>&1
            dnf config-manager --set-enabled powertools >/dev/null 2>&1
        fi

        if [[ "$Server_OS_Version" = "7" ]]; then
            rpm --import https://cyberpanel.sh/dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7
            yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            Check_Return "yum repo" "no_exit"
            yum install -y yum-plugin-copr
            Check_Return "yum repo" "no_exit"
            yum copr enable -y copart/restic
            Check_Return "yum repo" "no_exit"
            yum install -y yum-plugin-priorities
            Check_Return "yum repo" "no_exit"
            curl -o /etc/yum.repos.d/powerdns-auth-43.repo \
                https://cyberpanel.sh/repo.powerdns.com/repo-files/centos-auth-43.repo
            Check_Return "yum repo" "no_exit"
            yum install --nogpg -y \
                https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/gf-release-latest.gf.el7.noarch.rpm
            Check_Return "yum repo" "no_exit"
            rpm -ivh https://cyberpanel.sh/repo.iotti.biz/CentOS/7/noarch/lux-release-7-1.noarch.rpm
            Check_Return "yum repo" "no_exit"
            rpm -ivh https://cyberpanel.sh/repo.ius.io/ius-release-el7.rpm
            Check_Return "yum repo" "no_exit"
        fi
    fi

    if [[ $Server_OS = "openEuler" ]]; then
        rpm --import https://cyberpanel.sh/rpms.litespeedtech.com/centos/RPM-GPG-KEY-litespeed
        yum clean all
        sed -i "s|gpgcheck=1|gpgcheck=0|g"                              /etc/yum.repos.d/openEuler.repo
        sed -i "s|repo.openeuler.org|mirror.efaith.com.hk/openeuler|g"  /etc/yum.repos.d/openEuler.repo

        [[ "$Server_OS_Version" = "20" ]] && \
            dnf install --nogpg -y https://repo.yaro.ee/yaro-release-20.03LTS-latest.oe1.noarch.rpm
        [[ "$Server_OS_Version" = "22" ]] && \
            dnf install --nogpg -y https://repo.yaro.ee/yaro-release-22.03LTS-latest.oe2203.noarch.rpm
        Check_Return "yum repo" "no_exit"
    fi

    Debug_Log2 "Setting up repositories...,1"

    if [[ "$Server_Country" = "CN" ]]; then
        Pre_Install_Setup_CN_Repository
        Debug_Log2 "Setting up repositories for CN server...,1"
    fi

    if [[ "$Server_Country" = "CN" ]] || [[ "$Server_Provider" = "Alibaba Cloud" ]] \
    || [[ "$Server_Provider" = "Tencent Cloud" ]]; then
        Setup_Pip
    fi
}

Setup_Pip() {
    rm -rf /root/.pip && mkdir -p /root/.pip
    cat <<EOF >/root/.pip/pip.conf
[global]
index-url = https://cyberpanel.sh/pip-repo/pypi/simple/
EOF
    if [[ "$Server_Provider" = "Alibaba Cloud" ]]; then
        sed -i 's|https://cyberpanel.sh/pip-repo/pypi/simple/|http://mirrors.cloud.aliyuncs.com/pypi/simple/|g' \
            /root/.pip/pip.conf
        echo "trusted-host = mirrors.cloud.aliyuncs.com" >> /root/.pip/pip.conf
    fi
    if [[ "$Server_Provider" = "Tencent Cloud" ]]; then
        sed -i 's|https://cyberpanel.sh/pip-repo/pypi/simple/|https://mirrors.cloud.tencent.com/pypi/simple/|g' \
            /root/.pip/pip.conf
    fi
    Debug_Log2 "Setting up PIP repo...,3"
    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Pip Source" "$(grep "index-url" /root/.pip/pip.conf)"
    fi
}

Pre_Install_Setup_CN_Repository() {
    if [[ "$Server_OS" = "CentOS" ]] && [[ "$Server_OS_Version" = "7" ]]; then
        sed -i 's|http://yum.mariadb.org|https://cyberpanel.sh/yum.mariadb.org|g' \
            /etc/yum.repos.d/MariaDB.repo
        sed -i 's|https://yum.mariadb.org/RPM-GPG-KEY-MariaDB|https://cyberpanel.sh/yum.mariadb.org/RPM-GPG-KEY-MariaDB|g' \
            /etc/yum.repos.d/MariaDB.repo
        sed -i 's|https://download.copr.fedorainfracloud.org|https://cyberpanel.sh/download.copr.fedorainfracloud.org|g' \
            /etc/yum.repos.d/_copr_copart-restic.repo
        sed -i 's|http://repo.iotti.biz|https://cyberpanel.sh/repo.iotti.biz|g' /etc/yum.repos.d/frank.repo
        sed -i "s|mirrorlist=http://mirrorlist.ghettoforge.org/el/7/gf/\$basearch/mirrorlist|baseurl=https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/el/7/gf/x86_64/|g" \
            /etc/yum.repos.d/gf.repo
        sed -i "s|mirrorlist=http://mirrorlist.ghettoforge.org/el/7/plus/\$basearch/mirrorlist|baseurl=https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/el/7/plus/x86_64/|g" \
            /etc/yum.repos.d/gf.repo
        sed -i 's|https://repo.ius.io|https://cyberpanel.sh/repo.ius.io|g' /etc/yum.repos.d/ius.repo
        sed -i 's|http://repo.iotti.biz|https://cyberpanel.sh/repo.iotti.biz|g' /etc/yum.repos.d/lux.repo
        sed -i 's|http://repo.powerdns.com|https://cyberpanel.sh/repo.powerdns.com|g' \
            /etc/yum.repos.d/powerdns-auth-43.repo
        sed -i 's|https://repo.powerdns.com|https://cyberpanel.sh/repo.powerdns.com|g' \
            /etc/yum.repos.d/powerdns-auth-43.repo
    fi
    Debug_Log2 "Setting up repositories for CN server...,1"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-INSTALL: GIT URL SETUP
# Always uses the joeyboli fork. CN servers also use GitHub (not Gitee)
# since this is a personal fork not mirrored on Gitee.
# ─────────────────────────────────────────────────────────────────────────────

Pre_Install_Setup_Git_URL() {
    Git_User="${FORK_USER}"
    Git_Content_URL="${FORK_CONTENT_URL}"
    Git_Clone_URL="${FORK_CLONE_URL}"

    echo -e "\nGit source: ${Git_Clone_URL}"
    echo -e "Branch:     ${Branch_Name}\n"
    log_info "Git URL: ${Git_Clone_URL} | Branch: ${Branch_Name}"

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Git_URL" "$Git_Content_URL"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-INSTALL: DOWNLOAD REQUIREMENTS
# ─────────────────────────────────────────────────────────────────────────────

Download_Requirement() {
    for i in {1..50}; do
        if [[ "$Server_OS_Version" = "22" ]] || [[ "$Server_OS_Version" = "24" ]] \
        || [[ "$Server_OS_Version" = "9"  ]] || [[ "$Server_OS_Version" = "10" ]]; then
            wget -O /usr/local/requirments.txt "${Git_Content_URL}/v2.4.5/requirments.txt"
        else
            wget -O /usr/local/requirments.txt "${Git_Content_URL}/v2.4.5/requirments-old.txt"
        fi

        if grep -q "Django==" /usr/local/requirments.txt; then
            break
        else
            echo -e "\nRequirements download failed (attempt $i/50). Retrying in 5s...\n"
            sleep 5
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-INSTALL: REQUIRED COMPONENTS
# ─────────────────────────────────────────────────────────────────────────────

Pre_Install_Required_Components() {
    log_function_start "Pre_Install_Required_Components"
    Debug_Log2 "Installing necessary components..,3"
    log_info "Installing required system components and dependencies"

    if [[ "$Server_OS" = "CentOS" ]] || [[ "$Server_OS" = "openEuler" ]]; then
        yum update -y
        if [[ "$Server_OS_Version" = "7" ]]; then
            yum install -y wget strace net-tools curl which bc telnet htop libevent-devel \
                gcc libattr-devel xz-devel gpgme-devel curl-devel git socat openssl-devel \
                MariaDB-shared mariadb-devel yum-utils python36u python36u-pip python36u-devel \
                zip unzip bind-utils
            Check_Return
            yum -y groupinstall development
            Check_Return
        elif [[ "$Server_OS_Version" = "8" ]]; then
            dnf install -y libnsl zip wget strace net-tools curl which bc telnet htop \
                libevent-devel gcc libattr-devel xz-devel mariadb-devel curl-devel git \
                platform-python-devel tar socat python3 zip unzip bind-utils gpgme-devel
            Check_Return
        elif [[ "$Server_OS_Version" = "9" ]] || [[ "$Server_OS_Version" = "10" ]]; then
            dnf install -y libnsl zip wget strace net-tools curl which bc telnet htop \
                libevent-devel gcc libattr-devel xz-devel MariaDB-server MariaDB-client \
                MariaDB-devel curl-devel git platform-python-devel tar socat python3 \
                zip unzip bind-utils gpgme-devel openssl-devel boost-devel boost-program-options
            Check_Return

            # AlmaLinux 10: boost symlink for galera-4 compatibility
            if [[ "$Server_OS_Version" = "10" ]]; then
                if [ ! -f /usr/lib64/libboost_program_options.so.1.75.0 ]; then
                    BOOST_VERSION=$(find /usr/lib64 -name "libboost_program_options.so.*" | head -1 \
                        | sed 's/.*libboost_program_options\.so\.//')
                    if [ -n "$BOOST_VERSION" ]; then
                        ln -sf /usr/lib64/libboost_program_options.so.$BOOST_VERSION \
                                /usr/lib64/libboost_program_options.so.1.75.0
                        log_info "Boost symlink created: $BOOST_VERSION → 1.75.0"
                    fi
                fi
            fi
        elif [[ "$Server_OS_Version" = "20" ]] || [[ "$Server_OS_Version" = "22" ]] \
          || [[ "$Server_OS_Version" = "24" ]]; then
            dnf install -y libnsl zip wget strace net-tools curl which bc telnet htop \
                libevent-devel gcc libattr-devel xz-devel mariadb-devel curl-devel git \
                python3-devel tar socat python3 zip unzip bind-utils gpgme-devel
            Check_Return
        fi
        ln -s /usr/bin/pip3 /usr/bin/pip
    else
        apt update -y
        DEBIAN_FRONTEND=noninteractive apt upgrade -y \
            -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

        if [[ "$Server_Provider" = "Alibaba Cloud" ]]; then
            apt install -y --allow-downgrades libgnutls30=3.6.13-2ubuntu1.3
        fi

        if [[ "$Server_OS_Version" = "22" ]] || [[ "$Server_OS_Version" = "24" ]]; then
            DEBIAN_FRONTEND=noninteractive apt install -y dnsutils net-tools htop telnet \
                libcurl4-gnutls-dev libgnutls28-dev libgcrypt20-dev libattr1 libattr1-dev \
                liblzma-dev libgpgme-dev libssl-dev nghttp2 libnghttp2-dev idn2 libidn2-dev \
                libidn2-0-dev librtmp-dev libpsl-dev nettle-dev libldap2-dev libgssapi-krb5-2 \
                libk5crypto3 libkrb5-dev libcomerr2 virtualenv git socat vim unzip zip \
                libmariadb-dev-compat libmariadb-dev
            Check_Return
        else
            DEBIAN_FRONTEND=noninteractive apt install -y dnsutils net-tools htop telnet \
                libcurl4-gnutls-dev libgnutls28-dev libgcrypt20-dev libattr1 libattr1-dev \
                liblzma-dev libgpgme-dev libmariadbclient-dev libssl-dev nghttp2 libnghttp2-dev \
                idn2 libidn2-dev libidn2-0-dev librtmp-dev libpsl-dev nettle-dev libldap2-dev \
                libgssapi-krb5-2 libk5crypto3 libkrb5-dev libcomerr2 virtualenv git socat vim \
                unzip zip
            Check_Return
        fi

        DEBIAN_FRONTEND=noninteractive apt install -y python3-pip build-essential libssl-dev \
            libffi-dev python3-dev python3-venv cron inetutils-ping
        Check_Return

        ln -s /usr/bin/pip3 /usr/bin/pip3.6
        ln -s /usr/bin/pip3.6 /usr/bin/pip

        DEBIAN_FRONTEND=noninteractive apt install -y locales
        locale-gen "en_US.UTF-8"
        update-locale LC_ALL="en_US.UTF-8"
    fi

    Debug_Log2 "Installing required virtual environment,3"
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    # Install virtualenv
    if [[ "$Server_OS" = "Ubuntu" ]]; then
        if [[ "$Server_OS_Version" = "24" ]]; then
            echo -e "Ubuntu 24.04 — using built-in python3-venv."
        else
            Retry_Command "DEBIAN_FRONTEND=noninteractive apt-get update"
            Retry_Command "DEBIAN_FRONTEND=noninteractive apt-get install -y python3-virtualenv"
        fi
    else
        Retry_Command "pip install --default-timeout=3600 virtualenv"
    fi

    Download_Requirement

    echo -e "\nCreating CyberPanel virtual environment..."
    mkdir -p /usr/local/CyberPanel

    if [[ "$Server_OS" = "Ubuntu" ]] && ([[ "$Server_OS_Version" = "22" ]] || [[ "$Server_OS_Version" = "24" ]]); then
        echo -e "Ubuntu 22/24 — using python3 -m venv."
        if python3 -m venv /usr/local/CyberPanel 2>&1; then
            echo -e "Virtual environment created ✓"
        else
            echo -e "python3 -m venv failed, falling back to virtualenv..."
            if [[ "$Server_OS_Version" = "24" ]]; then
                Retry_Command "DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv"
            else
                Retry_Command "DEBIAN_FRONTEND=noninteractive apt-get install -y python3-virtualenv"
            fi
            virtualenv -p /usr/bin/python3 /usr/local/CyberPanel
        fi
    else
        virtualenv -p /usr/bin/python3 /usr/local/CyberPanel
    fi

    if [[ ! -f /usr/local/CyberPanel/bin/activate ]]; then
        echo -e "ERROR: Virtual environment creation failed!"
        exit 1
    fi

    [[ "$Server_OS" = "Ubuntu" ]] \
        && . /usr/local/CyberPanel/bin/activate \
        || source /usr/local/CyberPanel/bin/activate

    Debug_Log2 "Installing requirements..,3"
    Retry_Command "pip install --default-timeout=3600 -r /usr/local/requirments.txt"
    Check_Return "requirements" "no_exit"

    rm -rf cyberpanel
    echo -e "\nCloning from ${Git_Clone_URL} (branch: ${Branch_Name})...\n"
    Debug_Log2 "Getting CyberPanel code..,4"

    Retry_Command "git clone -b ${Branch_Name} --single-branch ${Git_Clone_URL}"
    Check_Return "git clone ${Git_Clone_URL}"

    echo -e "\nSource code downloaded ✓\n"

    cp -r cyberpanel /usr/local/cyberpanel
    cd cyberpanel/install || exit

    Debug_Log2 "Necessary components installed..,5"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-INSTALL: SYSTEM TWEAKS
# ─────────────────────────────────────────────────────────────────────────────

Pre_Install_System_Tweak() {
    log_function_start "Pre_Install_System_Tweak"
    Debug_Log2 "Setting up system tweak...,20"
    log_info "Applying system tweaks and optimizations"

    # Hostname in /etc/hosts
    Line_Number=$(grep -n "127.0.0.1" /etc/hosts | cut -d: -f 1)
    My_Hostname=$(hostname)
    if [[ -n $Line_Number ]]; then
        for Line_Number2 in $Line_Number; do
            String=$(sed "${Line_Number2}q;d" /etc/hosts)
            if [[ $String != *"$My_Hostname"* ]]; then
                New_String="$String $My_Hostname"
                sed -i "${Line_Number2}s/.*/${New_String}/" /etc/hosts
            fi
        done
    else
        echo "127.0.0.1 $My_Hostname" >>/etc/hosts
    fi

    # SELinux (CentOS)
    if [[ "$Server_OS" = "CentOS" ]]; then
        setenforce 0 || true
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

        if [[ "$Server_OS_Version" = "8" ]]; then
            if grep -q -E "Rocky Linux" /etc/os-release; then
                if [[ "$Server_Country" = "CN" ]]; then
                    sed -i 's|rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el8.noarch.rpm|curl -o /etc/yum.repos.d/litespeed.repo https://cyberpanel.sh/litespeed/litespeed_cn.repo|g' install.py
                else
                    sed -i 's|rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el8.noarch.rpm|curl -o /etc/yum.repos.d/litespeed.repo https://cyberpanel.sh/litespeed/litespeed.repo|g' install.py
                fi
            fi
        fi
    elif [[ "$Server_OS" = "Ubuntu" ]]; then
        if [[ "$Server_OS_Version" = "20" ]]; then
            sed -i 's|ce-2.3-latest/ubuntu/bionic bionic main|ce-2.3-latest/ubuntu/focal focal main|g' install.py
        fi
    fi

    # Kernel / file limits
    if ! grep -q "pid_max" /etc/rc.local 2>/dev/null; then
        if [[ $Server_OS = "CentOS" ]] || [[ $Server_OS = "openEuler" ]]; then
            echo "echo 1000000 > /proc/sys/kernel/pid_max
echo 1 > /sys/kernel/mm/ksm/run" >>/etc/rc.d/rc.local
            chmod +x /etc/rc.d/rc.local
        else
            if [[ -f /etc/rc.local ]]; then
                echo -e "#!/bin/bash\n$(cat /etc/rc.local)" > /etc/rc.local
            else
                echo "#!/bin/bash" > /etc/rc.local
            fi
            echo "echo 1000000 > /proc/sys/kernel/pid_max
echo 1 > /sys/kernel/mm/ksm/run" >>/etc/rc.local
            chmod +x /etc/rc.local
            systemctl enable rc-local >/dev/null 2>&1
            systemctl start rc-local >/dev/null 2>&1
        fi

        if grep -q "nf_conntrack_max" /etc/sysctl.conf; then
            sysctl -w net.netfilter.nf_conntrack_max=2097152 >/dev/null
            sysctl -w net.nf_conntrack_max=2097152 >/dev/null
            echo "net.netfilter.nf_conntrack_max=2097152" >> /etc/sysctl.conf
            echo "net.nf_conntrack_max=2097152" >> /etc/sysctl.conf
        fi

        echo "fs.file-max = 65535" >>/etc/sysctl.conf
        sysctl -p >/dev/null

        cat >>/etc/security/limits.conf <<'EOF'
*    soft nofile 65535
*    hard nofile 65535
root soft nofile 65535
root hard nofile 65535
*    soft nproc  65535
*    hard nproc  65535
root soft nproc  65535
root hard nproc  65535
EOF
    fi

    # SWAP
    Total_SWAP=$(free -m | awk '/^Swap:/ { print $2 }')
    Set_SWAP=$((Total_RAM - Total_SWAP))
    SWAP_File=/cyberpanel.swap

    if [ ! -f $SWAP_File ]; then
        if [[ $Total_SWAP -gt $Total_RAM ]] || [[ $Total_SWAP -eq $Total_RAM ]]; then
            echo -e "SWAP already sufficient.\n"
        else
            [[ $Set_SWAP -gt "2049" ]] && Set_SWAP="2048"
            fallocate --length ${Set_SWAP}MiB $SWAP_File
            chmod 600 $SWAP_File
            mkswap $SWAP_File
            swapon $SWAP_File
            echo -e "${SWAP_File} swap swap sw 0 0" | tee -a /etc/fstab
            sysctl vm.swappiness=10
            echo -e "vm.swappiness = 10" >> /etc/sysctl.conf
            echo -e "\nSWAP set (${Set_SWAP} MB) ✓\n"
        fi
    fi

    # Cloud provider host entries
    [[ "$Server_Provider" = "Tencent Cloud" ]] && \
        echo "$(host mirrors.tencentyun.com | awk '{print $4}') mirrors.tencentyun.com" >> /etc/hosts
    [[ "$Server_Provider" = "Alibaba Cloud" ]] && \
        echo "$(host mirrors.cloud.aliyuncs.com | awk '{print $4}') mirrors.cloud.aliyuncs.com" >> /etc/hosts

    # DNS
    if grep -i -q "systemd-resolve" /etc/resolv.conf; then
        systemctl stop systemd-resolved    >/dev/null 2>&1
        systemctl disable systemd-resolved >/dev/null 2>&1
        systemctl mask systemd-resolved    >/dev/null 2>&1
    fi

    cp /etc/resolv.conf /etc/resolv.conf_bak
    rm -f /etc/resolv.conf

    if   [[ "$Server_Provider" = "Tencent Cloud" ]]; then
        printf "nameserver 183.60.83.19\nnameserver 183.60.82.98\n" > /etc/resolv.conf
    elif [[ "$Server_Provider" = "Alibaba Cloud" ]]; then
        printf "nameserver 100.100.2.136\nnameserver 100.100.2.138\n" > /etc/resolv.conf
    else
        printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
    fi

    systemctl restart systemd-networkd >/dev/null 2>&1
    for j in {1..6}; do
        sleep 0.5
        ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 || nslookup cyberpanel.sh >/dev/null 2>&1 && break
    done

    if ping -q -c 1 -W 1 cyberpanel.sh >/dev/null; then
        echo -e "\nNetwork up. Continuing installation.\n"
    else
        echo -e "\nNetwork issue detected — reverting DNS settings.\n"
        rm -f /etc/resolv.conf
        mv /etc/resolv.conf_bak /etc/resolv.conf
        systemctl restart systemd-networkd >/dev/null 2>&1
        sleep 1
    fi

    cp /etc/resolv.conf /etc/resolv.conf-tmp

    Line1="$(grep -n "f.write('nameserver 8.8.8.8')" installCyberPanel.py | head -n 1 | cut -d: -f1)"
    if [[ -n "$Line1" ]] && [[ "$Line1" =~ ^[0-9]+$ ]]; then
        sed -i "${Line1}i\                subprocess.call\(command, shell=True)" installCyberPanel.py
        sed -i "${Line1}i\                command = 'cat /etc/resolv.conf-tmp > /etc/resolv.conf'" installCyberPanel.py
    else
        echo "Warning: Could not find nameserver pattern in installCyberPanel.py — skipping DNS patch."
    fi

    log_debug "System tweaks completed"
    log_function_end "Pre_Install_System_Tweak"
}

# ─────────────────────────────────────────────────────────────────────────────
# LICENSE VALIDATION (Enterprise only)
# ─────────────────────────────────────────────────────────────────────────────

License_Validation() {
    log_function_start "License_Validation"
    Debug_Log2 "Validating LiteSpeed license...,40"
    log_info "Validating LiteSpeed Enterprise license"

    Current_Dir=$(pwd)
    rm -rf /root/cyberpanel-tmp
    mkdir /root/cyberpanel-tmp
    cd /root/cyberpanel-tmp || exit

    Retry_Command "wget https://cyberpanel.sh/www.litespeedtech.com/packages/${LSWS_Stable_Version:0:1}.0/lsws-$LSWS_Stable_Version-ent-x86_64-linux.tar.gz"
    tar xzvf "lsws-$LSWS_Stable_Version-ent-x86_64-linux.tar.gz" >/dev/null
    cd "/root/cyberpanel-tmp/lsws-$LSWS_Stable_Version/conf" || exit

    if [[ "$License_Key" = "Trial" ]]; then
        Retry_Command "wget -q https://cyberpanel.sh/license.litespeedtech.com/reseller/trial.key"
        sed -i "s|writeSerial = open('lsws-[0-9.]\+/serial.no', 'w')|command = 'wget -q --output-document=./lsws-$LSWS_Stable_Version/trial.key https://cyberpanel.sh/license.litespeedtech.com/reseller/trial.key'|g" \
            "$Current_Dir/installCyberPanel.py"
        sed -i 's|writeSerial.writelines(self.serial)|subprocess.call(command, shell=True)|g' \
            "$Current_Dir/installCyberPanel.py"
        sed -i 's|writeSerial.close()||g' "$Current_Dir/installCyberPanel.py"
    else
        echo "$License_Key" > serial.no
    fi

    cd "/root/cyberpanel-tmp/lsws-$LSWS_Stable_Version/bin" || exit

    if [[ "$License_Key" = "Trial" ]]; then
        License_Key="1111-2222-3333-4444"
    else
        ./lshttpd -r
    fi

    if ./lshttpd -V |& grep "ERROR" || ./lshttpd -V |& grep "expire in 0 days"; then
        echo -e "\n\nLicense issue detected — please check your key."
        Debug_Log2 "LiteSpeed license issue [404]"
        log_error "LiteSpeed license validation failed"
        log_function_end "License_Validation" 1
        exit
    fi

    echo -e "\nLicense valid ✓"
    log_info "LiteSpeed license validated"
    cd "$Current_Dir" || exit
    rm -rf /root/cyberpanel-tmp
    log_function_end "License_Validation"
}

# ─────────────────────────────────────────────────────────────────────────────
# CN REPLACEMENT (install.py / installCyberPanel.py URL patches)
# ─────────────────────────────────────────────────────────────────────────────

Pre_Install_CN_Replacement() {
    if [[ "$Server_OS" = "Ubuntu" ]]; then
        sed -i 's|wget http://rpms.litespeedtech.com/debian/|wget https://cyberpanel.sh/litespeed/|g' install.py
        sed -i 's|https://repo.dovecot.org/|https://cyberpanel.sh/repo.dovecot.org/|g' install.py
    fi

    if [[ "$Server_OS" = "CentOS" ]]; then
        sed -i 's|rpm -ivh http://rpms.litespeedtech.com/centos/litespeed-repo-1.2-1.el7.noarch.rpm|curl -o /etc/yum.repos.d/litespeed.repo https://cyberpanel.sh/litespeed/litespeed_cn.repo|g' install.py
        sed -i 's|rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el8.noarch.rpm|curl -o /etc/yum.repos.d/litespeed.repo https://cyberpanel.sh/litespeed/litespeed_cn.repo|g' install.py
        sed -i 's|https://mirror.ghettoforge.org/distributions|https://cyberpanel.sh/mirror.ghettoforge.net/distributions|g' install.py

        if [[ "$Server_OS_Version" = "8" ]]; then
            sed -i 's|dnf --nogpg install -y https://mirror.ghettoforge.org/distributions/gf/gf-release-latest.gf.el8.noarch.rpm|echo gf8|g' install.py
            sed -i 's|dnf --nogpg install -y https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/gf-release-latest.gf.el8.noarch.rpm|echo gf8|g' install.py
            Retry_Command "dnf --nogpg install -y https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/gf-release-latest.gf.el8.noarch.rpm"
            sed -i "s|mirrorlist=http://mirrorlist.ghettoforge.org/el/8/gf/\$basearch/mirrorlist|baseurl=https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/el/8/gf/x86_64/|g" /etc/yum.repos.d/gf.repo
            sed -i "s|mirrorlist=http://mirrorlist.ghettoforge.org/el/8/plus/\$basearch/mirrorlist|baseurl=https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/el/8/plus/x86_64/|g" /etc/yum.repos.d/gf.repo
        fi

        if [[ "$Server_OS_Version" = "9" ]] || [[ "$Server_OS_Version" = "10" ]]; then
            sed -i 's|rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el8.noarch.rpm|curl -o /etc/yum.repos.d/litespeed.repo https://rpms.litespeedtech.com/centos/litespeed.repo|g' install.py
            sed -i "s|mirrorlist=http://mirrorlist.ghettoforge.org/el/8/gf/\$basearch/mirrorlist|baseurl=https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/el/9/gf/x86_64/|g" /etc/yum.repos.d/gf.repo
            sed -i "s|mirrorlist=http://mirrorlist.ghettoforge.org/el/8/plus/\$basearch/mirrorlist|baseurl=https://cyberpanel.sh/mirror.ghettoforge.net/distributions/gf/el/9/plus/x86_64/|g" /etc/yum.repos.d/gf.repo
        fi
    fi

    sed -i "s|https://www.litespeedtech.com/|https://cyberpanel.sh/www.litespeedtech.com/|g" installCyberPanel.py
    sed -i 's|composer.sh|composer_cn.sh|g' install.py
    sed -i 's|./composer_cn.sh|COMPOSER_ALLOW_SUPERUSER=1 ./composer_cn.sh|g' install.py
    sed -i 's|http://www.litespeedtech.com|https://cyberpanel.sh/www.litespeedtech.com|g' install.py
    sed -i 's|https://snappymail.eu/repository/latest.tar.gz|https://cyberpanel.sh/www.snappymail.eu/repository/latest.tar.gz|g' install.py
    sed -i "s|rep.cyberpanel.net|cyberpanel.sh/rep.cyberpanel.net|g" installCyberPanel.py
    sed -i "s|rep.cyberpanel.net|cyberpanel.sh/rep.cyberpanel.net|g" install.py

    Debug_Log2 "Setting up URLs for CN server...,1"

    sed -i 's|wget -O -  https://get.acme.sh | sh|echo acme|g' install.py
    sed -i 's|/root/.acme.sh/acme.sh --upgrade --auto-upgrade|echo acme2|g' install.py

    Current_Dir=$(pwd)
    Retry_Command "git clone https://gitee.com/neilpang/acme.sh.git"
    cd acme.sh || exit
    ./acme.sh --install
    cd "$Current_Dir" || exit
    rm -rf acme.sh

    # shellcheck disable=SC2016
    sed -i 's|$PROJECT/archive/$BRANCH.tar.gz|https://cyberpanel.sh/codeload.github.com/acmesh-official/acme.sh/tar.gz/master|g' \
        /root/.acme.sh/acme.sh
    Retry_Command "/root/.acme.sh/acme.sh --upgrade --auto-upgrade"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN INSTALLATION
# ─────────────────────────────────────────────────────────────────────────────

Main_Installation() {
    log_function_start "Main_Installation"
    Debug_Log2 "Starting main installation..,30"
    log_info "Starting main CyberPanel installation"

    if [[ -d /usr/local/CyberCP ]]; then
        echo -e "\nCyberPanel already installed — exiting."
        Debug_Log2 "CyberPanel already installed [404]"
        exit
    fi

    if [[ $Server_Edition = "Enterprise" ]]; then
        echo -e "\nValidating license (this may take a minute)...\n"
        License_Validation
        sed -i "s|lsws-5.4.2|lsws-$LSWS_Stable_Version|g" installCyberPanel.py
        sed -i "s|lsws-5.3.5|lsws-$LSWS_Stable_Version|g" installCyberPanel.py
        sed -i "s|lsws-6.0|lsws-$LSWS_Stable_Version|g"   installCyberPanel.py
        Enterprise_Flag="--ent ent --serial "
    fi

    # Suppress re-clone inside install.py (we already cloned from the fork)
    sed -i 's|git clone https://github.com/usmannasir/cyberpanel|echo downloaded|g' install.py
    sed -i 's|mirror.cyberpanel.net|cyberpanel.sh|g' install.py

    # acme.sh setup
    if [[ $Server_Country = "CN" ]]; then
        Pre_Install_CN_Replacement
    else
        sed -i 's|wget -O -  https://get.acme.sh | sh|echo acme|g' install.py
        sed -i 's|/root/.acme.sh/acme.sh --upgrade --auto-upgrade|echo acme2|g' install.py

        Current_Dir=$(pwd)
        Retry_Command "git clone https://github.com/acmesh-official/acme.sh.git"
        cd acme.sh || exit
        ./acme.sh --install
        cd "$Current_Dir" || exit
        rm -rf acme.sh

        Retry_Command "/root/.acme.sh/acme.sh --upgrade --auto-upgrade"
    fi

    echo -e "\nPreparing installation flags...\n"

    Final_Flags=()
    Final_Flags+=("$Server_IP")
    Final_Flags+=(${Enterprise_Flag:+$Enterprise_Flag})
    Final_Flags+=(${License_Key:+$License_Key})
    Final_Flags+=(--postfix   "${Postfix_Switch^^}")
    Final_Flags+=(--powerdns  "${PowerDNS_Switch^^}")
    Final_Flags+=(--ftp       "${PureFTPd_Switch^^}")

    [[ "$Redis_Hosting" = "Yes" ]] && Final_Flags+=(--redis enable)

    if [[ "$Remote_MySQL" = "On" ]]; then
        Final_Flags+=(--remotemysql "${Remote_MySQL^^}")
        Final_Flags+=(--mysqlhost "$MySQL_Host")
        Final_Flags+=(--mysqldb "$MySQL_DB")
        Final_Flags+=(--mysqluser "$MySQL_User")
        Final_Flags+=(--mysqlpassword "$MySQL_Password")
        Final_Flags+=(--mysqlport "$MySQL_Port")
    else
        Final_Flags+=(--remotemysql "${Remote_MySQL^^}")
    fi

    if [[ "$Debug" = "On" ]]; then
        Debug_Log "Final_Flags" "${Final_Flags[@]}"
    fi

    /usr/local/CyberPanel/bin/python install.py "${Final_Flags[@]}"

    if grep "CyberPanel installation successfully completed" /var/log/installLogs.txt >/dev/null; then
        echo -e "\nCyberPanel installation completed successfully ✓\n"
        Debug_Log2 "Main installation completed..,70"
    else
        echo -e "\nSomething went wrong. Check /var/log/installLogs.txt"
        Debug_Log2 "Installation failed [404]"
        exit
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: MEMCACHED
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Addon_Mecached_LSMCD() {
    install_dev_tools
    wget -O lsmcd-master.zip https://cyberpanel.sh/codeload.github.com/litespeedtech/lsmcd/zip/master
    unzip lsmcd-master.zip
    Current_Dir=$(pwd)
    cd "$Current_Dir/lsmcd-master" || exit
    ./fixtimestamp.sh
    ./configure CFLAGS=" -O3" CXXFLAGS=" -O3"
    make && make install
    cd "$Current_Dir" || exit
    manage_service "lsmcd" "enable"
    manage_service "lsmcd" "start"
    log_info "LSMCD installation completed"
}

Post_Install_Addon_Memcached() {
    log_function_start "Post_Install_Addon_Memcached"
    log_info "Installing Memcached and PHP extension"
    install_php_packages "memcached"

    if [[ $Total_RAM -ge 2048 ]]; then
        Post_Install_Addon_Mecached_LSMCD
    else
        install_package "memcached"
        configure_memcached
        manage_service "memcached" "enable"
        manage_service "memcached" "start"
    fi

    pgrep "lsmcd"     && echo -e "\nLiteSpeed Memcached running ✓"
    pgrep "memcached" && echo -e "\nMemcached running ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: REDIS
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Addon_Redis() {
    log_function_start "Post_Install_Addon_Redis"
    log_info "Installing Redis server and PHP extension"
    install_php_packages "redis"

    if [[ "$Server_OS" = "CentOS" ]]; then
        if [[ "$Server_OS_Version" = "8" || "$Server_OS_Version" = "9" || "$Server_OS_Version" = "10" ]]; then
            install_package "redis"
        else
            yum -y install http://rpms.remirepo.net/enterprise/remi-release-7.rpm
            yum-config-manager --disable remi
            yum-config-manager --disable remi-safe
            yum -y --enablerepo=remi install redis
        fi
    elif [[ "$Server_OS" = "Ubuntu" ]]; then
        install_package "redis"
    elif [[ "$Server_OS" = "openEuler" ]]; then
        install_package "redis6"
    fi

    ifconfig -a | grep inet6 >/dev/null \
        && echo -e "\nIPv6 detected." \
        || sed -i 's|bind 127.0.0.1 ::1|bind 127.0.0.1|g' /etc/redis/redis.conf

    if [[ $Server_OS = "Ubuntu" ]]; then
        manage_service "redis-server" "stop"
        rm -f /var/run/redis/redis-server.pid
        manage_service "redis-server" "enable"
        manage_service "redis-server" "start"
    else
        manage_service "redis" "enable"
        manage_service "redis" "start"
    fi

    pgrep "redis" && echo -e "\nRedis running ✓" && touch /home/cyberpanel/redis
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: REQUIRED COMPONENTS
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Required_Components() {
    Debug_Log2 "Finalization..,80"
    echo -e "\nCreating CyberCP virtual environment..."
    mkdir -p /usr/local/CyberCP

    if [[ "$Server_OS" = "Ubuntu" ]] && ([[ "$Server_OS_Version" = "22" ]] || [[ "$Server_OS_Version" = "24" ]]); then
        echo -e "Ubuntu 22/24 — using python3 -m venv."
        python3 -m venv /usr/local/CyberCP 2>&1 \
            || { pip3 install --upgrade virtualenv; virtualenv -p /usr/bin/python3 /usr/local/CyberCP; }
    elif [[ "$Server_OS" = "CentOS" ]] && ([[ "$Server_OS_Version" = "9" ]] || [[ "$Server_OS_Version" = "10" ]]); then
        echo -e "AlmaLinux/Rocky 9/10 — using python3 -m venv."
        PYTHON_PATH=$(which python3 2>/dev/null || which python3.9 2>/dev/null || echo "/usr/bin/python3")
        python3 -m venv /usr/local/CyberCP 2>&1 \
            || { pip3 install --upgrade virtualenv; virtualenv -p "$PYTHON_PATH" /usr/local/CyberCP; }
    else
        virtualenv -p /usr/bin/python3 /usr/local/CyberCP
    fi

    if [[ ! -f /usr/local/CyberCP/bin/activate ]]; then
        echo -e "ERROR: Virtual environment creation failed!"
        exit 1
    fi

    if [[ "$Server_OS" = "Ubuntu" ]] && [[ "$Server_OS_Version" = "20" ]]; then
        . /usr/local/CyberCP/bin/activate
        Check_Return
    else
        source /usr/local/CyberCP/bin/activate
        Check_Return
    fi

    Retry_Command "pip install --default-timeout=3600 -r /usr/local/requirments.txt"
    Check_Return "requirements.txt" "no_exit"

    echo -e "\nVerifying Django installation..."
    if ! /usr/local/CyberCP/bin/python -c "import django" 2>/dev/null; then
        echo -e "Django not found — reinstalling requirements..."
        pip install --upgrade pip setuptools wheel packaging
        pip install --default-timeout=3600 --ignore-installed -r /usr/local/requirments.txt
    else
        echo -e "Django verified ✓"
    fi

    if [[ "$Server_OS" = "Ubuntu" ]] && ([[ "$Server_OS_Version" = "22" ]] || [[ "$Server_OS_Version" = "24" ]]); then
        cp /usr/bin/python3.10 /usr/local/CyberCP/bin/python3
    else
        if [[ "$Server_OS_Version" = "9" ]] || [[ "$Server_OS_Version" = "10" ]] \
        || [[ "$Server_OS_Version" = "8" ]] || [[ "$Server_OS_Version" = "20" ]] \
        || [[ "$Server_OS_Version" = "24" ]]; then
            echo "PYTHONHOME=/usr" > /usr/local/lscp/conf/pythonenv.conf
        fi
    fi

    chown -R cyberpanel:cyberpanel /usr/local/CyberCP/lib
    chown -R cyberpanel:cyberpanel /usr/local/CyberCP/lib64 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: PHP SESSION SETUP
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_PHP_Session_Setup() {
    log_function_start "Post_Install_PHP_Session_Setup"
    echo -e "\nSetting up PHP session storage path...\n"
    log_info "Setting up PHP session storage configuration"
    chmod +x /usr/local/CyberCP/CPScripts/setup_php_sessions.sh
    bash /usr/local/CyberCP/CPScripts/setup_php_sessions.sh
    Debug_Log2 "Setting up PHP session conf...,90"
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: PHP TIMEZONEDB
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_PHP_TimezoneDB() {
    log_function_start "Post_Install_PHP_TimezoneDB"
    log_info "Installing PHP TimezoneDB extension"

    Current_Dir="$(pwd)"
    rm -rf /usr/local/lsws/cyberpanel-tmp
    mkdir /usr/local/lsws/cyberpanel-tmp
    cd /usr/local/lsws/cyberpanel-tmp || exit

    wget -O timezonedb.tgz https://cyberpanel.sh/pecl.php.net/get/timezonedb
    if [ ! -f timezonedb.tgz ] || [ ! -s timezonedb.tgz ]; then
        log_info "WARNING: Failed to download timezonedb — skipping."
        cd "$Current_Dir" || exit
        rm -rf /usr/local/lsws/cyberpanel-tmp
        return 0
    fi

    tar xzvf timezonedb.tgz
    if [ ! -d timezonedb-* ]; then
        log_info "WARNING: Failed to extract timezonedb — skipping."
        cd "$Current_Dir" || exit
        rm -rf /usr/local/lsws/cyberpanel-tmp
        return 0
    fi

    cd timezonedb-* || { cd "$Current_Dir" || exit; rm -rf /usr/local/lsws/cyberpanel-tmp; return 0; }

    if [[ "$Server_OS" = "Ubuntu" ]]; then
        install_package "libmagickwand-dev pkg-config build-essential lsphp*-dev"
    else
        install_package "lsphp??-mysqlnd lsphp??-devel make gcc glibc-devel libmemcached-devel zlib-devel"
        yum remove -y lsphp??-mysql
    fi

    for PHP_Version in /usr/local/lsws/lsphp??; do
        configure_php_timezone "$PHP_Version"
    done

    rm -rf /usr/local/lsws/cyberpanel-tmp
    cd "$Current_Dir" || exit
    Debug_Log2 "TimezoneDB installed..,95"
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: REGENERATE SSL CERTS
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Regenerate_Cert() {
    log_function_start "Post_Install_Regenerate_Cert"
    log_info "Regenerating SSL certificates for control panel"

    cat <<EOF >/root/cyberpanel/cert_conf
[req]
prompt=no
distinguished_name=cyberpanel
[cyberpanel]
commonName             = www.example.com
countryName            = CP
localityName           = CyberPanel
organizationName       = CyberPanel
organizationalUnitName = CyberPanel
stateOrProvinceName    = CP
emailAddress           = mail@example.com
name                   = CyberPanel
surname                = CyberPanel
givenName              = CyberPanel
initials               = CP
dnQualifier            = CyberPanel
[server_exts]
extendedKeyUsage = 1.3.6.1.5.5.7.3.1
EOF

    openssl req -x509 -config /root/cyberpanel/cert_conf -extensions 'server_exts' \
        -nodes -days 820 -newkey rsa:2048 \
        -keyout /usr/local/lscp/conf/key.pem \
        -out    /usr/local/lscp/conf/cert.pem

    if [[ "$Server_Edition" = "OLS" ]]; then
        Key_Path="/usr/local/lsws/admin/conf/webadmin.key"
        Cert_Path="/usr/local/lsws/admin/conf/webadmin.crt"
    else
        Key_Path="/usr/local/lsws/admin/conf/cert/admin.key"
        Cert_Path="/usr/local/lsws/admin/conf/cert/admin.crt"
    fi

    openssl req -x509 -config /root/cyberpanel/cert_conf -extensions 'server_exts' \
        -nodes -days 820 -newkey rsa:2048 \
        -keyout "$Key_Path" \
        -out    "$Cert_Path"

    rm -f /root/cyberpanel/cert_conf
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: WEBADMIN PASSWORD
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Regenerate_Webadmin_Console_Passwd() {
    log_function_start "Post_Install_Regenerate_Webadmin_Console_Passwd"
    log_info "Regenerating WebAdmin console password"

    [[ "$Server_Edition" = "OLS" ]] && PHP_Command="admin_php" || PHP_Command="admin_php5"

    Webadmin_Pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16; echo '')
    Encrypt_string=$(/usr/local/lsws/admin/fcgi-bin/${PHP_Command} \
        /usr/local/lsws/admin/misc/htpasswd.php "${Webadmin_Pass}")

    echo ""                        > /usr/local/lsws/admin/conf/htpasswd
    echo "admin:$Encrypt_string"  >> /usr/local/lsws/admin/conf/htpasswd
    chown lsadm:lsadm /usr/local/lsws/admin/conf/htpasswd
    chmod 600 /usr/local/lsws/admin/conf/htpasswd

    echo "${Webadmin_Pass}" > /etc/cyberpanel/webadmin_passwd
    chmod 600 /etc/cyberpanel/webadmin_passwd

    log_info "WebAdmin console password regenerated"
    log_function_end "Post_Install_Regenerate_Webadmin_Console_Passwd"
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: WATCHDOG
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Setup_Watchdog() {
    log_function_start "Post_Install_Setup_Watchdog"
    if [[ "$Watchdog" = "On" ]]; then
        log_info "Setting up watchdog monitoring service"
        wget -O /etc/cyberpanel/watchdog.sh "${Git_Content_URL}/${FORK_BRANCH}/CPScripts/watchdog.sh"
        chmod 700 /etc/cyberpanel/watchdog.sh
        ln -s /etc/cyberpanel/watchdog.sh /usr/local/bin/watchdog

        pid=$(ps aux | grep "watchdog lsws" | grep -v grep | awk '{print $2}')
        [[ $pid = "" ]] && nohup watchdog lsws >/dev/null 2>&1 &

        echo -e "Checking MariaDB watchdog..."
        pid=$(ps aux | grep "watchdog mariadb" | grep -v grep | awk '{print $2}')
        [[ $pid = "" ]] && nohup watchdog mariadb >/dev/null 2>&1 &

        if [[ "$Server_OS" = "CentOS" ]] || [[ "$Server_OS" = "openEuler" ]]; then
            printf 'nohup watchdog lsws > /dev/null 2>&1 &\nnohup watchdog mariadb > /dev/null 2>&1 &\n' \
                >> /etc/rc.d/rc.local
        else
            printf 'nohup watchdog lsws > /dev/null 2>&1 &\nnohup watchdog mariadb > /dev/null 2>&1 &\n' \
                >> /etc/rc.local
        fi

        echo -e "\nWatchdog configured ✓"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: UTILITY
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Setup_Utility() {
    if [[ ! -f /usr/bin/cyberpanel_utility ]]; then
        wget -q -O /usr/bin/cyberpanel_utility https://cyberpanel.sh/misc/cyberpanel_utility.sh
        chmod 700 /usr/bin/cyberpanel_utility
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: TWEAKS
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Tweak() {
    log_function_start "Post_Install_Tweak"
    log_info "Applying post-installation tweaks"

    # PureFTPd hardening
    if [[ -d /etc/pure-ftpd/conf ]]; then
        echo "yes" > /etc/pure-ftpd/conf/ChrootEveryone
        systemctl restart pure-ftpd-mysql
    fi
    if [[ -f /etc/pure-ftpd/pure-ftpd.conf ]]; then
        sed -i 's|NoAnonymous no|NoAnonymous yes|g' /etc/pure-ftpd/pure-ftpd.conf
    fi

    # LiteSpeed version stamps
    for v in "lsws-5.3.8" "lsws-5.4.2" "lsws-5.3.5"; do
        sed -i "s|$v|lsws-$LSWS_Stable_Version|g" /usr/local/CyberCP/serverStatus/serverStatusUtil.py
    done

    # Utility script
    if [[ ! -f /usr/bin/cyberpanel_utility ]]; then
        wget -q -O /usr/bin/cyberpanel_utility https://cyberpanel.sh/misc/cyberpanel_utility.sh
        chmod 700 /usr/bin/cyberpanel_utility
    fi

    # Banner
    rm -rf /etc/profile.d/cyberpanel*
    curl --silent -o /etc/profile.d/cyberpanel.sh https://cyberpanel.sh/?banner 2>/dev/null
    chmod 700 /etc/profile.d/cyberpanel.sh

    # Admin password
    echo "$Admin_Pass" > /etc/cyberpanel/adminPass
    chmod 600 /etc/cyberpanel/adminPass
    /usr/local/CyberPanel/bin/python /usr/local/CyberCP/plogical/adminPass.py --password "$Admin_Pass"
    mkdir -p /etc/opendkim

    # adminPass CLI helper
    cat > /usr/bin/adminPass <<'EOFSCRIPT'
/usr/local/CyberPanel/bin/python /usr/local/CyberCP/plogical/adminPass.py --password "$@"
systemctl restart lscpd
echo $@ > /etc/cyberpanel/adminPass
EOFSCRIPT
    chmod 700 /usr/bin/adminPass

    # PHP symlink
    rm -f /usr/bin/php
    ln -s /usr/local/lsws/lsphp83/bin/php /usr/bin/php

    # OS-specific cron and php.ini fixes
    if [[ "$Server_OS" = "CentOS" ]]; then
        sed -i 's|error_reporting = E_ALL \&amp; ~E_DEPRECATED \&amp; ~E_STRICT|error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_STRICT|g' \
            /usr/local/lsws/{lsphp72,lsphp73}/etc/php.ini
        sed -i 's|/usr/local/lsws/bin/lswsctrl restart|systemctl restart lsws|g' /var/spool/cron/root

        if [[ "$Server_OS_Version" = "7" ]]; then
            if ! yum list installed lsphp74-devel; then
                yum install -y lsphp74-devel
            fi
            if [[ ! -f /usr/local/lsws/lsphp74/lib64/php/modules/zip.so ]]; then
                yum list installed libzip-devel >/dev/null 2>&1 && yum remove -y libzip-devel
                yum install -y https://cyberpanel.sh/misc/libzip-0.11.2-6.el7.psychotic.x86_64.rpm
                yum install -y https://cyberpanel.sh/misc/libzip-devel-0.11.2-6.el7.psychotic.x86_64.rpm
                yum install lsphp74-devel
                [[ ! -d /usr/local/lsws/lsphp74/tmp ]] && mkdir /usr/local/lsws/lsphp74/tmp
                /usr/local/lsws/lsphp74/bin/pecl channel-update pecl.php.net
                /usr/local/lsws/lsphp74/bin/pear config-set temp_dir /usr/local/lsws/lsphp74/tmp
                if /usr/local/lsws/lsphp74/bin/pecl install zip; then
                    echo "extension=zip.so" > /usr/local/lsws/lsphp74/etc/php.d/20-zip.ini
                    chmod 755 /usr/local/lsws/lsphp74/lib64/php/modules/zip.so
                else
                    echo -e "\nlsphp74-zip compilation failed."
                fi
            fi
        fi
    elif [[ "$Server_OS" = "Ubuntu" ]]; then
        sed -i 's|/usr/local/lsws/bin/lswsctrl restart|systemctl restart lsws|g' \
            /var/spool/cron/crontabs/root
        [[ ! -f /usr/sbin/ipset ]] && ln -s /sbin/ipset /usr/sbin/ipset
    elif [[ "$Server_OS" = "openEuler" ]]; then
        sed -i 's|error_reporting = E_ALL \&amp; ~E_DEPRECATED \&amp; ~E_STRICT|error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_STRICT|g' \
            /usr/local/lsws/{lsphp72,lsphp73}/etc/php.ini
        sed -i 's|/usr/local/lsws/bin/lswsctrl restart|systemctl restart lsws|g' /var/spool/cron/root
    fi

    # Edition word
    if [[ "$Server_Edition" = "OLS" ]]; then
        Word="OpenLiteSpeed"
    else
        Word="LiteSpeed Enterprise"
        sed -i 's|Include /usr/local/lsws/conf/rules.conf||g' /usr/local/lsws/conf/modsec.conf
    fi

    # Restart services
    systemctl restart lscpd >/dev/null 2>&1
    /usr/local/lsws/bin/lswsctrl stop >/dev/null 2>&1
    systemctl stop lsws  >/dev/null 2>&1
    systemctl start lsws >/dev/null 2>&1

    echo -e "\nFinalizing...\nCleaning up...\n"
    log_info "Cleaning up temporary installation files"
    rm -rf /root/cyberpanel

    [[ "$Server_Country" = "CN" ]] && Post_Install_CN_Replacement

    # Hostname SSL
    HostName=$(hostname --fqdn)
    [ -n "$(dig @1.1.1.1 +short "$HostName")" ] && {
        echo -e "$HostName resolves — setting up hostname SSL..."
        cyberpanel createWebsite --package Default --owner admin \
            --domainName "$HostName" --email root@localhost --php 7.4
        cyberpanel hostNameSSL --domainName "$HostName"
    }

# =====================================================================
# CRITICAL FIXES APPLIED DIRECTLY INTO MAIN_UPGRADE
# =====================================================================

# 5. Fix Systemd Service (Prevents SSH Kill)
echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] Applying systemd KillMode fix for lscpd..." | tee -a /var/log/cyberpanel_upgrade_debug.log
cat <<EOF > /etc/systemd/system/lscpd.service
[Unit]
Description=LSCPD Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/lscp/bin/lscpdctrl start
ExecStop=/usr/local/lscp/bin/lscpdctrl stop
PIDFile=/usr/local/lscp/logs/lscpd.pid
Restart=always
KillMode=control-group
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# 6. Fix Environment file (Prevents Django Error 500)
echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] Ensuring .env file is populated..." | tee -a /var/log/cyberpanel_upgrade_debug.log
DB_PASS=$(cat /etc/cyberpanel/cyberpaneldb 2>/dev/null || cat /etc/cyberpanel/mysqlPassword)
MYSQL_PASS=$(cat /etc/cyberpanel/mysqlPassword)
cat <<EOF > /usr/local/CyberCP/.env
DB_PASSWORD=${DB_PASS}
ROOT_DB_PASSWORD=${MYSQL_PASS}
DB_HOST=127.0.0.1
ROOT_DB_HOST=127.0.0.1
SECRET_KEY=$(openssl rand -base64 32)
ALLOWED_HOSTS=*
EOF
chmod 600 /usr/local/CyberCP/.env

# 7. Force Binary Integrity (Crucial for Ubuntu 24/22)
echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] Restoring correct lscpd binary..." | tee -a /var/log/cyberpanel_upgrade_debug.log
if [[ -f /usr/local/CyberCP/lscpd.0.4.0 ]]; then
    cp -f /usr/local/CyberCP/lscpd.0.4.0 /usr/local/lscp/bin/lscpd
    chmod 755 /usr/local/lscp/bin/lscpd
    chown root:root /usr/local/lscp/bin/lscpd
fi
}


Post_Install_CN_Replacement() {
    sed -i 's|wp core download|wp core download https://cyberpanel.sh/wordpress.org/latest.tar.gz|g' \
        /usr/local/CyberCP/plogical/applicationInstaller.py
    sed -i 's|https://raw.githubusercontent.com/|https://cyberpanel.sh/raw.githubusercontent.com/|g' \
        /usr/local/CyberCP/plogical/applicationInstaller.py
    sed -i 's|wp plugin install litespeed-cache|wp plugin install https://cyberpanel.sh/downloads.wordpress.org/plugin/litespeed-cache.zip|g' \
        /usr/local/CyberCP/plogical/applicationInstaller.py
    sed -i 's|https://www.litespeedtech.com/|https://cyberpanel.sh/www.litespeedtech.com/|g' \
        /usr/local/CyberCP/serverStatus/serverStatusUtil.py
    sed -i 's|http://license.litespeedtech.com/|https://cyberpanel.sh/license.litespeedtech.com/|g' \
        /usr/local/CyberCP/serverStatus/serverStatusUtil.py
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-INSTALL: FINAL INFO
# ─────────────────────────────────────────────────────────────────────────────

Post_Install_Display_Final_Info() {
    log_function_start "Post_Install_Display_Final_Info"
    log_info "Installation complete — displaying final info"

    local Elapsed_Time="$((SECONDS / 3600))h $(((SECONDS / 60) % 60))m $((SECONDS % 60))s"

    echo "###################################################################"
    echo "              CyberPanel Successfully Installed                    "
    echo "                                                                   "
    echo "  Fork        : ${FORK_CLONE_URL}                                 "
    echo "  Branch      : ${FORK_BRANCH}                                    "
    echo "                                                                   "
    echo "  Disk usage  : $(df -h | awk '$NF=="/"{printf "%d/%dGB (%s)", $3,$2,$5}')"
    echo "  RAM usage   : $(free -m | awk 'NR==2{printf "%s/%sMB (%.2f%%)", $3,$2,$3*100/$2}')"
    echo "  Install time: $Elapsed_Time                                      "
    echo "                                                                   "
    echo "  Visit       : https://$Server_IP:8090                           "
    echo "  Username    : admin                                              "
    if [[ "$Custom_Pass" = "True" ]]; then
        echo "  Password    : *****                                          "
    else
        echo "  Password    : $Admin_Pass                                    "
    fi
    echo "                                                                   "
    echo "  cyberpanel help     — FAQ & commands                            "
    echo "  cyberpanel upgrade  — upgrade to latest                         "
    echo "  cyberpanel utility  — handy tools                               "
    echo "                                                                   "
    echo "  Website : https://www.cyberpanel.net                            "
    echo "  Forums  : https://forums.cyberpanel.net                         "
    echo "  Docs    : https://cyberpanel.net/docs/                          "
    echo "###################################################################"

    if [[ "$Server_Provider" != "Undefined" ]]; then
        echo -e "\n$Server_Provider detected — this provider has a network-level firewall."
    else
        echo -e "\nIf your provider has a network-level firewall,"
    fi

    echo -e "Please ensure the following ports are open (in + out):"
    echo -e "  TCP 8090                         — CyberPanel UI"
    echo -e "  TCP 80, TCP 443, UDP 443         — Web server"
    echo -e "  TCP 21, TCP 40110-40210          — FTP"
    echo -e "  TCP 25, 587, 465, 110, 143, 993  — Mail"
    echo -e "  TCP 53, UDP 53                   — DNS"

    timeout 3 telnet mx.zoho.com 25 | grep "Escape" >/dev/null 2>&1 \
        || echo -e "\nWarning: Port 25 appears blocked — outbound email may not work."

    Debug_Log2 "Completed [200]"

    if [[ "$Silent" != "On" ]]; then
        printf "\nWould you like to restart your server now? [y/N]: "
        read -r Tmp_Input
        [[ "${Tmp_Input^^}" = *Y* ]] && reboot
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\nInitializing CyberPanel installer...\n"
echo -e "  Fork   : ${FORK_CLONE_URL}"
echo -e "  Branch : ${FORK_BRANCH}\n"

log_info "============================================="
log_info "CyberPanel installation script started"
log_info "Fork   : ${FORK_CLONE_URL}"
log_info "Branch : ${FORK_BRANCH}"
log_info "Args   : $*"
log_info "============================================="

if [[ "$*" = *"--debug"* ]]; then
    Debug="On"
    find /var/log -name 'cyberpanel_debug_*' -exec rm {} +
    Random_Log_Name=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
    echo -e "$(date)" > "/var/log/cyberpanel_debug_$(date +"%Y-%m-%d")_${Random_Log_Name}.log"
    chmod 600 "/var/log/cyberpanel_debug_$(date +"%Y-%m-%d")_${Random_Log_Name}.log"
fi

Set_Default_Variables
Check_Root
Check_Server_IP   "$@"
Check_OS
Check_Virtualization
Check_Panel
Check_Process
Check_Provider
Check_Argument    "$@"

[[ $Silent = "On" ]] && Argument_Mode || Interactive_Mode

Time_Count="0"

Pre_Install_Setup_Repository
Pre_Install_Setup_Git_URL
Pre_Install_Required_Components
Pre_Install_System_Tweak
Main_Installation

[[ "$Memcached" = "On" ]] && Post_Install_Addon_Memcached
[[ "$Redis"     = "On" ]] && Post_Install_Addon_Redis

Post_Install_Required_Components
Post_Install_PHP_Session_Setup
Post_Install_PHP_TimezoneDB
Post_Install_Regenerate_Cert
Post_Install_Regenerate_Webadmin_Console_Passwd
Post_Install_Setup_Watchdog
Post_Install_Setup_Utility
Post_Install_Tweak
Post_Install_Display_Final_Info