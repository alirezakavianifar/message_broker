#!/usr/bin/env python3
"""
Message Broker Admin CLI

Command-line tool for administrative tasks:
- User management
- Certificate management
- Database queries
- System statistics
"""

import argparse
import getpass
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from sqlalchemy.orm import Session
from tabulate import tabulate

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from main_server.database import DatabaseManager
from main_server.models import User, Client, Message, AuditLog, UserRole, ClientStatus, MessageStatus
from main_server.encryption import EncryptionManager

# Import password hashing from api
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ============================================================================
# Configuration
# ============================================================================

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+pymysql://systemuser:StrongPass123!@localhost/message_system"
)

ENCRYPTION_KEY_PATH = os.getenv("ENCRYPTION_KEY_PATH", "secrets/encryption.key")
HASH_SALT = os.getenv("HASH_SALT", "message_broker_salt_change_in_production")

# ============================================================================
# Database Connection
# ============================================================================

db_manager = None
encryption_manager = None

def init_db():
    """Initialize database connection"""
    global db_manager, encryption_manager
    
    if not db_manager:
        try:
            db_manager = DatabaseManager(DATABASE_URL)
            print("[OK] Database connected")
        except Exception as e:
            print(f"[ERROR] Failed to connect to database: {e}")
            sys.exit(1)
    
    if not encryption_manager:
        try:
            encryption_manager = EncryptionManager(
                key_path=ENCRYPTION_KEY_PATH,
                salt=HASH_SALT
            )
            print("[OK] Encryption manager initialized")
        except Exception as e:
            print(f"[ERROR] Failed to initialize encryption: {e}")
            sys.exit(1)
    
    return db_manager, encryption_manager

def get_db() -> Session:
    """Get database session"""
    return db_manager.get_session()

# ============================================================================
# User Management Commands
# ============================================================================

def cmd_user_list(args):
    """List all users"""
    init_db()
    
    with get_db() as db:
        users = db.query(User).all()
        
        if not users:
            print("No users found")
            return
        
        table_data = []
        for user in users:
            table_data.append([
                user.id,
                user.email,
                user.role.value,
                "[OK]" if user.is_active else "[X]",
                user.created_at.strftime("%Y-%m-%d %H:%M"),
                user.last_login_at.strftime("%Y-%m-%d %H:%M") if user.last_login_at else "Never",
            ])
        
        headers = ["ID", "Email", "Role", "Active", "Created", "Last Login"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))
        print(f"\nTotal: {len(users)} users")

def cmd_user_create(args):
    """Create a new user"""
    init_db()
    
    email = args.email
    role = args.role.upper()
    
    # Get password
    if args.password:
        password = args.password
    else:
        password = getpass.getpass("Password: ")
        password_confirm = getpass.getpass("Confirm password: ")
        
        if password != password_confirm:
            print("[X] Passwords do not match")
            return
    
    if len(password) < 8:
        print("[X] Password must be at least 8 characters")
        return
    
    with get_db() as db:
        # Check if email exists
        existing = db.query(User).filter(User.email == email).first()
        if existing:
            print(f"[X] User with email {email} already exists")
            return
        
        # Validate client_id if provided
        client_id = getattr(args, 'client_id', None)
        if client_id:
            client = db.query(Client).filter(Client.client_id == client_id).first()
            if not client:
                print(f"[X] Client not found: {client_id}")
                return
        
        # Create user
        # Use UserRole enum
        role_enum = getattr(UserRole, role.upper())  # UserRole.ADMIN or UserRole.USER
        user = User(
            email=email,
            password_hash=pwd_context.hash(password),
            role=role_enum,
            client_id=client_id,
            is_active=True,
        )
        
        db.add(user)
        db.commit()
        db.refresh(user)
        
        client_info = f", Client: {client_id}" if client_id else ""
        print(f"[OK] User created: {user.email} (ID: {user.id}, Role: {role}{client_info})")

def cmd_user_delete(args):
    """Delete a user"""
    init_db()
    
    user_id = args.user_id
    
    with get_db() as db:
        user = db.query(User).filter(User.id == user_id).first()
        
        if not user:
            print(f"[X] User not found: {user_id}")
            return
        
        # Confirm deletion
        if not args.force:
            confirm = input(f"Delete user {user.email}? (yes/no): ")
            if confirm.lower() != "yes":
                print("Cancelled")
                return
        
        db.delete(user)
        db.commit()
        
        print(f"[OK] User deleted: {user.email}")

def cmd_user_password(args):
    """Change user password"""
    init_db()
    
    user_id = args.user_id
    
    # Get new password
    if args.password:
        password = args.password
    else:
        password = getpass.getpass("New password: ")
        password_confirm = getpass.getpass("Confirm password: ")
        
        if password != password_confirm:
            print("[X] Passwords do not match")
            return
    
    if len(password) < 8:
        print("[X] Password must be at least 8 characters")
        return
    
    with get_db() as db:
        user = db.query(User).filter(User.id == user_id).first()
        
        if not user:
            print(f"[X] User not found: {user_id}")
            return
        
        user.password_hash = pwd_context.hash(password)
        db.commit()
        
        print(f"[OK] Password changed for {user.email}")

# ============================================================================
# Certificate Management Commands
# ============================================================================

def cmd_cert_list(args):
    """List all certificates"""
    init_db()
    
    with get_db() as db:
        query = db.query(Client)
        
        if args.status:
            query = query.filter(Client.status == ClientStatus(args.status))
        
        clients = query.all()
        
        if not clients:
            print("No certificates found")
            return
        
        table_data = []
        for client in clients:
            table_data.append([
                client.id,
                client.client_id,
                client.domain or "N/A",
                client.status.value,
                client.issued_at.strftime("%Y-%m-%d") if client.issued_at else "N/A",
                client.expires_at.strftime("%Y-%m-%d") if client.expires_at else "N/A",
                client.revoked_at.strftime("%Y-%m-%d") if client.revoked_at else "N/A",
            ])
        
        headers = ["ID", "Client ID", "Domain", "Status", "Issued", "Expires", "Revoked"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))
        print(f"\nTotal: {len(clients)} certificates")

def cmd_cert_revoke(args):
    """Revoke a certificate"""
    init_db()
    
    client_id = args.client_id
    reason = args.reason or "Administrative revocation"
    
    with get_db() as db:
        client = db.query(Client).filter(Client.client_id == client_id).first()
        
        if not client:
            print(f"[X] Client not found: {client_id}")
            return
        
        if client.status == ClientStatus.REVOKED:
            print(f"[X] Certificate already revoked for {client_id}")
            return
        
        # Confirm revocation
        if not args.force:
            confirm = input(f"Revoke certificate for {client_id}? (yes/no): ")
            if confirm.lower() != "yes":
                print("Cancelled")
                return
        
        client.status = ClientStatus.REVOKED
        client.revoked_at = datetime.utcnow()
        
        db.commit()
        
        print(f"[OK] Certificate revoked for {client_id}")
        print(f"  Reason: {reason}")
        print(f"  Revoked at: {client.revoked_at}")

# ============================================================================
# Message Commands
# ============================================================================

def cmd_message_list(args):
    """List messages"""
    init_db()
    
    with get_db() as db:
        query = db.query(Message)
        
        if args.client:
            query = query.filter(Message.client_id == args.client)
        
        if args.status:
            query = query.filter(Message.status == MessageStatus(args.status))
        
        messages = query.order_by(Message.created_at.desc()).limit(args.limit).all()
        
        if not messages:
            print("No messages found")
            return
        
        table_data = []
        for msg in messages:
            table_data.append([
                msg.id,
                msg.message_id[:8] + "...",
                msg.client_id,
                msg.status.value,
                msg.attempt_count,
                msg.created_at.strftime("%Y-%m-%d %H:%M"),
                msg.delivered_at.strftime("%Y-%m-%d %H:%M") if msg.delivered_at else "N/A",
            ])
        
        headers = ["ID", "Message ID", "Client", "Status", "Attempts", "Created", "Delivered"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))
        print(f"\nShowing {len(messages)} messages")

def cmd_message_view(args):
    """View message details"""
    init_db()
    
    message_id = args.message_id
    
    with get_db() as db:
        msg = db.query(Message).filter(Message.message_id == message_id).first()
        
        if not msg:
            print(f"[X] Message not found: {message_id}")
            return
        
        print(f"\nMessage Details:")
        print(f"  ID: {msg.id}")
        print(f"  Message ID: {msg.message_id}")
        print(f"  Client ID: {msg.client_id}")
        print(f"  Status: {msg.status.value}")
        print(f"  Attempt Count: {msg.attempt_count}")
        print(f"  Created: {msg.created_at}")
        print(f"  Queued: {msg.queued_at}")
        print(f"  Delivered: {msg.delivered_at or 'Not delivered'}")
        print(f"  Sender Hash: {msg.sender_number_hashed[:20]}...")
        
        # Decrypt body if requested
        if args.decrypt:
            try:
                body = encryption_manager.decrypt(msg.encrypted_body)
                print(f"  Message Body: {body}")
            except Exception as e:
                print(f"  Message Body: [decryption failed: {e}]")
        else:
            print(f"  Message Body: [encrypted - use --decrypt to view]")

# ============================================================================
# Statistics Commands
# ============================================================================

def cmd_stats(args):
    """Show system statistics"""
    init_db()
    
    with get_db() as db:
        from sqlalchemy import func
        from datetime import timedelta
        
        # Total messages
        total_messages = db.query(func.count(Message.id)).scalar()
        
        # Messages by status
        status_counts = db.query(
            Message.status,
            func.count(Message.id)
        ).group_by(Message.status).all()
        
        # Total clients
        total_clients = db.query(func.count(Client.id)).scalar()
        active_clients = db.query(func.count(Client.id)).filter(
            Client.status == ClientStatus.ACTIVE
        ).scalar()
        revoked_clients = db.query(func.count(Client.id)).filter(
            Client.status == ClientStatus.REVOKED
        ).scalar()
        
        # Messages last 24h
        day_ago = datetime.utcnow() - timedelta(days=1)
        messages_24h = db.query(func.count(Message.id)).filter(
            Message.created_at >= day_ago
        ).scalar()
        
        # Messages last 7d
        week_ago = datetime.utcnow() - timedelta(days=7)
        messages_7d = db.query(func.count(Message.id)).filter(
            Message.created_at >= week_ago
        ).scalar()
        
        # Total users
        total_users = db.query(func.count(User.id)).scalar()
        
        print("\n" + "="*50)
        print("System Statistics")
        print("="*50)
        
        print(f"\nMessages:")
        print(f"  Total: {total_messages}")
        for status, count in status_counts:
            print(f"  {status.value.capitalize()}: {count}")
        print(f"  Last 24 hours: {messages_24h}")
        print(f"  Last 7 days: {messages_7d}")
        
        print(f"\nClients:")
        print(f"  Total: {total_clients}")
        print(f"  Active: {active_clients}")
        print(f"  Revoked: {revoked_clients}")
        
        print(f"\nUsers:")
        print(f"  Total: {total_users}")
        
        print()

# ============================================================================
# Main
# ============================================================================

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Message Broker Admin CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    
    # User commands
    user_parser = subparsers.add_parser("user", help="User management")
    user_subparsers = user_parser.add_subparsers(dest="subcommand")
    
    user_list_parser = user_subparsers.add_parser("list", help="List users")
    
    user_create_parser = user_subparsers.add_parser("create", help="Create user")
    user_create_parser.add_argument("email", help="User email")
    user_create_parser.add_argument("--role", choices=["user", "admin"], default="user", help="User role")
    user_create_parser.add_argument("--password", help="User password (prompt if not provided)")
    user_create_parser.add_argument("--client-id", help="Associated client ID for regular users")
    
    user_delete_parser = user_subparsers.add_parser("delete", help="Delete user")
    user_delete_parser.add_argument("user_id", type=int, help="User ID")
    user_delete_parser.add_argument("--force", action="store_true", help="Skip confirmation")
    
    user_password_parser = user_subparsers.add_parser("password", help="Change user password")
    user_password_parser.add_argument("user_id", type=int, help="User ID")
    user_password_parser.add_argument("--password", help="New password (prompt if not provided)")
    
    # Certificate commands
    cert_parser = subparsers.add_parser("cert", help="Certificate management")
    cert_subparsers = cert_parser.add_subparsers(dest="subcommand")
    
    cert_list_parser = cert_subparsers.add_parser("list", help="List certificates")
    cert_list_parser.add_argument("--status", choices=["active", "revoked", "expired"], help="Filter by status")
    
    cert_revoke_parser = cert_subparsers.add_parser("revoke", help="Revoke certificate")
    cert_revoke_parser.add_argument("client_id", help="Client ID")
    cert_revoke_parser.add_argument("--reason", help="Revocation reason")
    cert_revoke_parser.add_argument("--force", action="store_true", help="Skip confirmation")
    
    # Message commands
    msg_parser = subparsers.add_parser("message", help="Message management")
    msg_subparsers = msg_parser.add_subparsers(dest="subcommand")
    
    msg_list_parser = msg_subparsers.add_parser("list", help="List messages")
    msg_list_parser.add_argument("--client", help="Filter by client ID")
    msg_list_parser.add_argument("--status", choices=["queued", "delivered", "failed"], help="Filter by status")
    msg_list_parser.add_argument("--limit", type=int, default=20, help="Limit results")
    
    msg_view_parser = msg_subparsers.add_parser("view", help="View message details")
    msg_view_parser.add_argument("message_id", help="Message UUID")
    msg_view_parser.add_argument("--decrypt", action="store_true", help="Decrypt message body")
    
    # Stats command
    stats_parser = subparsers.add_parser("stats", help="Show system statistics")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    # Dispatch commands
    try:
        if args.command == "user":
            if args.subcommand == "list":
                cmd_user_list(args)
            elif args.subcommand == "create":
                cmd_user_create(args)
            elif args.subcommand == "delete":
                cmd_user_delete(args)
            elif args.subcommand == "password":
                cmd_user_password(args)
            else:
                user_parser.print_help()
        
        elif args.command == "cert":
            if args.subcommand == "list":
                cmd_cert_list(args)
            elif args.subcommand == "revoke":
                cmd_cert_revoke(args)
            else:
                cert_parser.print_help()
        
        elif args.command == "message":
            if args.subcommand == "list":
                cmd_message_list(args)
            elif args.subcommand == "view":
                cmd_message_view(args)
            else:
                msg_parser.print_help()
        
        elif args.command == "stats":
            cmd_stats(args)
        
    except KeyboardInterrupt:
        print("\n\nOperation cancelled")
    except Exception as e:
        print(f"\n[X] Error: {e}")
        import traceback
        if os.getenv("DEBUG"):
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()

