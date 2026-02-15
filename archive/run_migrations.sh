#!/bin/bash
# Script to run database migrations

cd /opt/message_broker/main_server
source ../venv/bin/activate

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Load .env file and extract DB variables
# Parse DATABASE_URL format: mysql+pymysql://user:password@host:port/database
if [ -f ../.env ]; then
    DATABASE_URL=$(grep DATABASE_URL ../.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    if [ -n "$DATABASE_URL" ]; then
        # Extract components from DATABASE_URL
        # Format: mysql+pymysql://user:password@host:port/database
        DB_USER=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
        DB_PASSWORD=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
        DB_HOST=$(echo "$DATABASE_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
        DB_PORT=$(echo "$DATABASE_URL" | sed -n 's/.*@[^:]*:\([^/]*\)\/.*/\1/p')
        DB_NAME=$(echo "$DATABASE_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')
        
        # URL decode password (handle % encoding)
        DB_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$DB_PASSWORD'))")
        
        export DB_USER DB_PASSWORD DB_HOST DB_PORT DB_NAME
    fi
fi

# Run migrations
alembic upgrade head

