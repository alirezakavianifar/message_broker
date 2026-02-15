#!/bin/bash
# Script to create admin user with proper .env loading

cd /opt/message_broker/main_server
source ../venv/bin/activate

# Load .env file
export $(cat ../.env | grep -v '^#' | xargs)

# Truncate password to 72 bytes if needed (bcrypt limit)
PASSWORD="$2"
PASSWORD_LEN=${#PASSWORD}
if [ $PASSWORD_LEN -gt 72 ]; then
    echo "Warning: Password longer than 72 bytes, truncating..."
    PASSWORD="${PASSWORD:0:72}"
fi

# Run admin_cli.py
python3 admin_cli.py user create "$1" --role admin --password "$PASSWORD"

