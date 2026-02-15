#!/usr/bin/env python3
"""
Create the missing audit_log table
"""
import sys
import os

# Add paths
sys.path.insert(0, '/opt/message_broker')
sys.path.insert(0, '/opt/message_broker/main_server')

from dotenv import load_dotenv
from main_server.database import DatabaseManager
from sqlalchemy import text

# Load .env file
env_path = '/opt/message_broker/.env'
if os.path.exists(env_path):
    load_dotenv(env_path)
else:
    alt_path = '/opt/message_broker/main_server/.env'
    if os.path.exists(alt_path):
        load_dotenv(alt_path)

# Get database URL
database_url = os.getenv('DATABASE_URL')
if not database_url:
    print("ERROR: DATABASE_URL not found in environment")
    sys.exit(1)

# Create database manager
db_manager = DatabaseManager(database_url)

# SQL to create audit_log table
create_audit_log_sql = """
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER NOT NULL AUTO_INCREMENT,
    event_type VARCHAR(100) NOT NULL,
    user_id INTEGER,
    client_id VARCHAR(255),
    ip_address VARCHAR(45),
    event_data TEXT,
    severity ENUM('INFO', 'WARNING', 'ERROR', 'CRITICAL') NOT NULL DEFAULT 'INFO',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_event_type (event_type),
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='Audit log for system events' CHARSET=utf8mb4 COLLATE utf8mb4_unicode_ci;
"""

try:
    with db_manager.get_session() as db:
        # Check if table exists
        result = db.execute(text("SHOW TABLES LIKE 'audit_log'"))
        if result.fetchone():
            print("✓ audit_log table already exists")
        else:
            print("Creating audit_log table...")
            db.execute(text(create_audit_log_sql))
            db.commit()
            print("✓ audit_log table created successfully")
            
except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

