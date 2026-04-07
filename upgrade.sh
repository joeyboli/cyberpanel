#!/bin/bash
## Script to clear caches after static file changes. Useful for development and testing.
## All credit belongs to Usman Nasir
## To use make it executable
## chmod +x /usr/local/CyberCP/upgrade.sh
## Then run it like below.
## /usr/local/CyberCP/upgrade.sh

# Check if virtual environment exists
if [[ ! -f /usr/local/CyberCP/bin/python ]]; then
    echo "Error: CyberPanel virtual environment not found at /usr/local/CyberCP/bin/python"
    echo "Please ensure CyberPanel is properly installed."
    exit 1
fi

cd /usr/local/CyberCP && /usr/local/CyberCP/bin/python manage.py collectstatic --no-input || echo "Warning: collectstatic failed"
rm -rf /usr/local/CyberCP/public/static/*
mkdir -p /usr/local/CyberCP/public/static
cp -R  /usr/local/CyberCP/static/* /usr/local/CyberCP/public/static/
# CSF support removed - discontinued on August 31, 2025
# mkdir /usr/local/CyberCP/public/static/csf/
find /usr/local/CyberCP -type d -exec chmod 0755 {} \;
find /usr/local/CyberCP -type f -exec chmod 0644 {} \;
chmod -R 755 /usr/local/CyberCP/bin
chown -R root:root /usr/local/CyberCP
# Ensure specific directories have correct ownership after global root chown
chown -R lscpd:lscpd /usr/local/CyberCP/public/phpmyadmin/tmp
chown -R cyberpanel:cyberpanel /usr/local/CyberCP/static
chown -R cyberpanel:cyberpanel /usr/local/CyberCP/public/static

# Ensure .env file exists before restarting lscpd (fixes Django 500 error)
ENV_FILE="/usr/local/CyberCP/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[upgrade.sh] Creating missing .env file..."
    
    # Read database password from credential files
    if [[ -f /etc/cyberpanel/cyberpaneldb ]]; then
        DB_PASSWORD=$(cat /etc/cyberpanel/cyberpaneldb)
    elif [[ -f /etc/cyberpanel/mysqlPassword ]]; then
        DB_PASSWORD=$(cat /etc/cyberpanel/mysqlPassword)
    else
        DB_PASSWORD=""
    fi
    
    # Read MySQL root password
    if [[ -f /etc/cyberpanel/mysqlPassword ]]; then
        ROOT_DB_PASSWORD=$(cat /etc/cyberpanel/mysqlPassword)
    else
        ROOT_DB_PASSWORD=""
    fi
    
    # Generate SECRET_KEY if not available
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || echo "changeme_secret_key_$(date +%s)")
    
    # Create .env file
    cat > "$ENV_FILE" << ENVEOF
DB_PASSWORD=${DB_PASSWORD}
ROOT_DB_PASSWORD=${ROOT_DB_PASSWORD}
SECRET_KEY=${SECRET_KEY}
ALLOWED_HOSTS=*
ENVEOF
    
    chmod 600 "$ENV_FILE"
    echo "[upgrade.sh] .env file created at $ENV_FILE"
fi

systemctl restart lscpd
