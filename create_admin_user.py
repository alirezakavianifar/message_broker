#!/usr/bin/env python3
"""
Script to create admin user using the same password hashing method as the API
"""
import sys
import os

# Add paths
sys.path.insert(0, '/opt/message_broker')
sys.path.insert(0, '/opt/message_broker/main_server')

from dotenv import load_dotenv
from main_server.database import DatabaseManager
from main_server.models import User, UserRole
import bcrypt

def get_password_hash(password: str) -> str:
    """Generate password hash (bcrypt has 72 byte limit) - same as API"""
    # Truncate password to 72 bytes for bcrypt compatibility
    password_bytes = password.encode('utf-8')[:72]
    # Use bcrypt directly to avoid passlib's length check
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

def create_admin_user(email: str, password: str):
    """Create an admin user"""
    # Load .env file
    env_path = '/opt/message_broker/.env'
    if os.path.exists(env_path):
        load_dotenv(env_path)
    else:
        # Try alternative location
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
    
    with db_manager.get_session() as db:
        # Check if user exists
        existing = db.query(User).filter(User.email == email).first()
        if existing:
            print(f"[X] User with email {email} already exists")
            print(f"    ID: {existing.id}, Role: {existing.role}, Active: {existing.is_active}")
            sys.exit(1)
        
        # Validate password length
        if len(password) < 8:
            print("[X] Password must be at least 8 characters")
            sys.exit(1)
        
        # Create user
        user = User(
            email=email,
            password_hash=get_password_hash(password),
            role=UserRole.ADMIN,
            is_active=True,
        )
        
        db.add(user)
        db.commit()
        db.refresh(user)
        
        print(f"[OK] Admin user created successfully!")
        print(f"     Email: {user.email}")
        print(f"     ID: {user.id}")
        print(f"     Role: {user.role.value}")
        print(f"     Active: {user.is_active}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 create_admin_user.py <email> <password>")
        sys.exit(1)
    
    email = sys.argv[1]
    password = sys.argv[2]
    
    create_admin_user(email, password)
