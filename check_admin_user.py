#!/usr/bin/env python3
"""
Script to check if admin user exists in the database
"""
import sys
import os

# Add the main_server directory to the path
sys.path.insert(0, '/opt/message_broker')
sys.path.insert(0, '/opt/message_broker/main_server')

try:
    from dotenv import load_dotenv
    from main_server.database import DatabaseManager
    from main_server.models import User
    
    # Load environment variables
    env_path = '/opt/message_broker/main_server/.env'
    if os.path.exists(env_path):
        load_dotenv(env_path)
    else:
        # Try alternative locations
        for alt_path in ['/opt/message_broker/.env', '/opt/message_broker/main_server/.env']:
            if os.path.exists(alt_path):
                load_dotenv(alt_path)
                break
    
    # Get database URL from environment
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        print("ERROR: DATABASE_URL not found in environment")
        sys.exit(1)
    
    # Create database manager
    db_manager = DatabaseManager(database_url)
    
    # Query for admin users
    with db_manager.get_session() as session:
        admin_users = session.query(User).filter(
            (User.role == 'ADMIN') | (User.email == 'admin@example.com')
        ).all()
        
        if admin_users:
            print(f"✓ Found {len(admin_users)} admin user(s):")
            print("")
            for user in admin_users:
                print(f"  ID: {user.id}")
                print(f"  Email: {user.email}")
                print(f"  Role: {user.role}")
                print(f"  Active: {user.is_active}")
                print(f"  Created: {user.created_at}")
                print("")
        else:
            print("✗ No admin users found")
            sys.exit(1)
            
except ImportError as e:
    print(f"ERROR: Import failed: {e}")
    print("Make sure you're running this from the server with the virtual environment activated")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

