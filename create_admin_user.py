#!/usr/bin/env python3
"""
Script to create an admin user for the message broker system
"""

import os
import sys
from pathlib import Path

# Add main_server to path
sys.path.insert(0, str(Path(__file__).parent / "main_server"))

from sqlalchemy.orm import Session
import bcrypt

def get_password_hash(password: str) -> str:
    """Generate password hash (bcrypt has 72 byte limit) - matches api.py"""
    # Truncate password to 72 bytes for bcrypt compatibility
    password_bytes = password.encode('utf-8')[:72]
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

# Database URL
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+pymysql://systemuser:StrongPass123!@localhost/message_system"
)

# Import after path is set
from main_server.database import DatabaseManager
from main_server.models import User, UserRole

def create_admin_user(email: str = "admin@example.com", password: str = "AdminPass123!"):
    """Create an admin user"""
    try:
        # Initialize database
        db_manager = DatabaseManager(DATABASE_URL)
        
        with db_manager.get_session() as db:
            # Check if user already exists
            existing = db.query(User).filter(User.email == email).first()
            if existing:
                print(f"[WARN] User {email} already exists!")
                print(f"      User ID: {existing.id}")
                print(f"      Role: {existing.role.value}")
                print(f"      Active: {existing.is_active}")
                
                # Update password
                print(f"[INFO] Resetting password for existing user...")
                existing.password_hash = get_password_hash(password)
                existing.is_active = True
                db.commit()
                print(f"[OK] Password reset for {email}")
                print(f"\nYou can now login to the portal with:")
                print(f"     Email: {email}")
                print(f"     Password: {password}")
                return
            
            # Create new admin user
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
            print(f"     User ID: {user.id}")
            print(f"     Role: {user.role.value}")
            print(f"\nYou can now login to the portal with:")
            print(f"     Email: {email}")
            print(f"     Password: {password}")
            
    except Exception as e:
        print(f"[ERROR] Failed to create admin user: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Create admin user for message broker")
    parser.add_argument("--email", default="admin@example.com", help="Admin email")
    parser.add_argument("--password", default="AdminPass123!", help="Admin password")
    
    args = parser.parse_args()
    
    exit_code = create_admin_user(args.email, args.password)
    sys.exit(exit_code)

