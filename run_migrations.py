#!/usr/bin/env python3
"""
Script to run database migrations with proper .env loading
"""
import os
import sys
import subprocess
from pathlib import Path
from urllib.parse import urlparse, unquote

# Add paths
sys.path.insert(0, '/opt/message_broker')
sys.path.insert(0, '/opt/message_broker/main_server')

from dotenv import load_dotenv

# Load .env file
env_path = '/opt/message_broker/.env'
if os.path.exists(env_path):
    load_dotenv(env_path)
else:
    alt_path = '/opt/message_broker/main_server/.env'
    if os.path.exists(alt_path):
        load_dotenv(alt_path)

# Get DATABASE_URL
database_url = os.getenv('DATABASE_URL')
if not database_url:
    print("ERROR: DATABASE_URL not found in environment")
    sys.exit(1)

print(f"DEBUG: DATABASE_URL = {database_url[:50]}...")  # Show first 50 chars for debugging

# Parse DATABASE_URL
# Format: mysql+pymysql://user:password@host:port/database
# Handle special characters in password by manually parsing
try:
    # Remove the scheme prefix
    if '://' in database_url:
        url_part = database_url.split('://', 1)[1]
    else:
        url_part = database_url
    
    # Split at @ to separate credentials from host
    if '@' in url_part:
        creds_part, host_part = url_part.split('@', 1)
        
        # Split credentials
        if ':' in creds_part:
            db_user, db_password = creds_part.split(':', 1)
            db_user = unquote(db_user)
            db_password = unquote(db_password)
        else:
            db_user = unquote(creds_part)
            db_password = ''
    else:
        print(f"ERROR: Could not parse DATABASE_URL (no @ found)")
        sys.exit(1)
    
    # Parse host part
    if '/' in host_part:
        host_port, db_name = host_part.split('/', 1)
        db_name = db_name.split('?')[0]  # Remove query params
    else:
        host_port = host_part
        db_name = 'message_system'
    
    # Parse host and port
    if ':' in host_port:
        db_host, db_port_str = host_port.split(':', 1)
        try:
            db_port = int(db_port_str)
        except ValueError:
            db_port = 3306
    else:
        db_host = host_port
        db_port = 3306
    
    if not db_host:
        db_host = 'localhost'
    
    # Set environment variables for alembic
    os.environ['DB_USER'] = db_user
    os.environ['DB_PASSWORD'] = db_password
    os.environ['DB_HOST'] = db_host
    os.environ['DB_PORT'] = str(db_port)
    os.environ['DB_NAME'] = db_name
    
    # Set PYTHONPATH
    os.environ['PYTHONPATH'] = '/opt/message_broker'
    
    # Change to main_server directory
    os.chdir('/opt/message_broker/main_server')
    
    # Run alembic
    print("Running database migrations...")
    result = subprocess.run(['alembic', 'upgrade', 'head'], check=False)
    
    if result.returncode == 0:
        print("✓ Migrations completed successfully")
        sys.exit(0)
    else:
        print("✗ Migrations failed")
        sys.exit(1)
        
except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

