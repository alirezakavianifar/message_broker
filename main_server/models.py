"""
SQLAlchemy models for Message Broker System.

This module defines the database models matching the MySQL schema.
All models include proper relationships, indexes, and validation.
"""

from datetime import datetime
from enum import Enum as PyEnum
from typing import Optional

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    JSON,
    SmallInteger,
    String,
    Text,
)
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.sql import func

# Base class for all models
Base = declarative_base()


# ============================================================================
# Enumerations
# ============================================================================

class UserRole(str, PyEnum):
    """User role enumeration."""
    USER = "user"
    ADMIN = "admin"
    USER_MANAGER = "user_manager"


class ClientStatus(str, PyEnum):
    """Client certificate status enumeration."""
    ACTIVE = "active"
    REVOKED = "revoked"
    EXPIRED = "expired"


class MessageStatus(str, PyEnum):
    """Message processing status enumeration."""
    QUEUED = "queued"
    PROCESSING = "processing"
    DELIVERED = "delivered"
    FAILED = "failed"


class AuditSeverity(str, PyEnum):
    """Audit log severity levels."""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


# ============================================================================
# Models
# ============================================================================

class User(Base):
    """
    Portal user model.
    
    Stores user credentials and profile information for portal access.
    Passwords are hashed with bcrypt before storage.
    """
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(
        String(255),
        nullable=False,
        comment="bcrypt hashed password"
    )
    role = Column(
        Enum(UserRole, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        default=UserRole.USER,
        index=True
    )
    client_id = Column(
        String(255),
        nullable=True,
        index=True,
        comment="Associated client for regular users"
    )
    is_active = Column(Boolean, nullable=False, default=True, index=True)
    last_login = Column(DateTime, nullable=True)
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp()
    )
    updated_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    )

    # Relationships
    audit_logs = relationship(
        "AuditLog",
        back_populates="user",
        cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<User(id={self.id}, email='{self.email}', role='{self.role}')>"

    def to_dict(self) -> dict:
        """Convert user to dictionary (excluding password)."""
        return {
            "id": self.id,
            "email": self.email,
            "role": self.role.value,
            "client_id": self.client_id,
            "is_active": self.is_active,
            "last_login": self.last_login.isoformat() if self.last_login else None,
            "created_at": self.created_at.isoformat(),
        }


class Client(Base):
    """
    Client certificate model.
    
    Stores information about client certificates issued by the CA.
    Includes fingerprint for identity verification and revocation status.
    """
    __tablename__ = "clients"

    id = Column(Integer, primary_key=True, autoincrement=True)
    client_id = Column(
        String(255),
        unique=True,
        nullable=False,
        index=True,
        comment="Unique client identifier (CN from cert)"
    )
    cert_fingerprint = Column(
        String(255),
        unique=True,
        nullable=False,
        index=True,
        comment="SHA-256 fingerprint of certificate"
    )
    domain = Column(
        String(255),
        nullable=False,
        default="default",
        index=True
    )
    status = Column(
        Enum(ClientStatus, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        default=ClientStatus.ACTIVE,
        index=True
    )
    issued_at = Column(DateTime, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, nullable=True)
    revocation_reason = Column(String(500), nullable=True)
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp()
    )
    updated_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    )

    # Relationships
    messages = relationship(
        "Message",
        back_populates="client",
        cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return (
            f"<Client(id={self.id}, client_id='{self.client_id}', "
            f"status='{self.status}', domain='{self.domain}')>"
        )

    def to_dict(self) -> dict:
        """Convert client to dictionary."""
        return {
            "id": self.id,
            "client_id": self.client_id,
            "fingerprint": self.cert_fingerprint,
            "domain": self.domain,
            "status": self.status.value,
            "issued_at": self.issued_at.isoformat(),
            "expires_at": self.expires_at.isoformat(),
            "revoked_at": self.revoked_at.isoformat() if self.revoked_at else None,
            "revocation_reason": self.revocation_reason,
            "created_at": self.created_at.isoformat(),
        }

    def is_valid(self) -> bool:
        """Check if certificate is valid (not revoked or expired)."""
        if self.status != ClientStatus.ACTIVE:
            return False
        if self.expires_at < datetime.utcnow():
            return False
        return True


class Message(Base):
    """
    Message model with encryption and privacy.
    
    Stores messages with:
    - AES-256 encrypted body
    - SHA-256 hashed sender number
    - Processing status and delivery tracking
    """
    __tablename__ = "messages"

    # Composite indexes defined at class level
    __table_args__ = (
        Index("idx_composite_status_created", "status", "created_at"),
        Index("idx_composite_client_created", "client_id", "created_at"),
        Index("idx_messages_portal_query", "client_id", "status", "created_at"),
        Index("idx_messages_worker_query", "status", "attempt_count", "queued_at"),
    )

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    message_id = Column(
        String(36),
        unique=True,
        nullable=False,
        index=True,
        comment="UUID v4"
    )
    client_id = Column(
        String(255),
        ForeignKey("clients.client_id", ondelete="RESTRICT", onupdate="CASCADE"),
        nullable=False,
        index=True,
        comment="Client who submitted the message"
    )
    sender_number_hashed = Column(
        String(64),
        nullable=False,
        index=True,
        comment="SHA-256 hash of sender phone number"
    )
    encrypted_body = Column(
        Text,
        nullable=False,
        comment="AES-256 encrypted message body (base64)"
    )
    encryption_key_version = Column(
        SmallInteger,
        nullable=False,
        default=1,
        comment="Key version for rotation support"
    )
    status = Column(
        Enum(MessageStatus, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        default=MessageStatus.QUEUED,
        index=True
    )
    domain = Column(
        String(255),
        nullable=False,
        default="default",
        index=True
    )
    attempt_count = Column(Integer, nullable=False, default=0)
    error_message = Column(
        String(500),
        nullable=True,
        comment="Last error message (if failed)"
    )
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp(),
        index=True,
        comment="Message creation time"
    )
    queued_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp(),
        comment="Queue insertion time"
    )
    delivered_at = Column(
        DateTime,
        nullable=True,
        index=True,
        comment="Successful delivery time"
    )
    last_attempt_at = Column(
        DateTime,
        nullable=True,
        comment="Most recent delivery attempt"
    )

    # Relationships
    client = relationship("Client", back_populates="messages")

    def __repr__(self) -> str:
        return (
            f"<Message(id={self.id}, message_id='{self.message_id}', "
            f"status='{self.status}', client_id='{self.client_id}')>"
        )

    def to_dict(self, include_body: bool = False) -> dict:
        """
        Convert message to dictionary.
        
        Args:
            include_body: If True, includes encrypted body (requires decryption)
        """
        data = {
            "id": self.id,
            "message_id": self.message_id,
            "client_id": self.client_id,
            "sender_number_hashed": self.sender_number_hashed,
            "status": self.status.value,
            "domain": self.domain,
            "attempt_count": self.attempt_count,
            "error_message": self.error_message,
            "created_at": self.created_at.isoformat(),
            "queued_at": self.queued_at.isoformat(),
            "delivered_at": self.delivered_at.isoformat() if self.delivered_at else None,
            "last_attempt_at": self.last_attempt_at.isoformat() if self.last_attempt_at else None,
        }
        
        if include_body:
            data["encrypted_body"] = self.encrypted_body
            data["encryption_key_version"] = self.encryption_key_version
        
        return data

    def mask_sender_number(self, original_number: str) -> str:
        """
        Mask phone number for display.
        
        Args:
            original_number: Original phone number
            
        Returns:
            Masked number (e.g., +123****7890)
        """
        if len(original_number) <= 8:
            return original_number[:3] + "****" + original_number[-2:]
        return original_number[:4] + "****" + original_number[-4:]


class AuditLog(Base):
    """
    Audit log model for security events.
    
    Tracks security-sensitive operations like:
    - User logins
    - Certificate issuance/revocation
    - Configuration changes
    """
    __tablename__ = "audit_log"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    event_type = Column(
        String(50),
        nullable=False,
        index=True,
        comment="Type of event (login, cert_issue, cert_revoke, etc.)"
    )
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL", onupdate="CASCADE"),
        nullable=True,
        index=True,
        comment="User who performed the action"
    )
    client_id = Column(
        String(255),
        nullable=True,
        index=True,
        comment="Client involved in the action"
    )
    ip_address = Column(
        String(45),
        nullable=True,
        comment="IPv4 or IPv6 address"
    )
    event_data = Column(
        JSON,
        nullable=True,
        comment="Additional event details"
    )
    severity = Column(
        Enum(AuditSeverity),
        nullable=False,
        default=AuditSeverity.INFO,
        index=True
    )
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp(),
        index=True
    )

    # Relationships
    user = relationship("User", back_populates="audit_logs")

    def __repr__(self) -> str:
        return (
            f"<AuditLog(id={self.id}, event_type='{self.event_type}', "
            f"severity='{self.severity}', created_at='{self.created_at}')>"
        )

    def to_dict(self) -> dict:
        """Convert audit log entry to dictionary."""
        return {
            "id": self.id,
            "event_type": self.event_type,
            "user_id": self.user_id,
            "client_id": self.client_id,
            "ip_address": self.ip_address,
            "event_data": self.event_data,
            "severity": self.severity.value,
            "created_at": self.created_at.isoformat(),
        }


# ============================================================================
# Helper Functions
# ============================================================================

def create_all_tables(engine):
    """
    Create all database tables.
    
    Args:
        engine: SQLAlchemy engine instance
    """
    Base.metadata.create_all(engine)


def drop_all_tables(engine):
    """
    Drop all database tables.
    
    WARNING: This will delete all data!
    
    Args:
        engine: SQLAlchemy engine instance
    """
    Base.metadata.drop_all(engine)


class PasswordReset(Base):
    """
    Password reset token model.
    
    Stores tokens generated for password resets via email.
    Tokens are single-use and expire after a set duration.
    """
    __tablename__ = "password_resets"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE", onupdate="CASCADE"),
        nullable=False,
        index=True
    )
    token = Column(String(255), unique=True, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True)
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.current_timestamp()
    )

    # Relationships
    user = relationship("User")

    def __repr__(self) -> str:
        return f"<PasswordReset(user_id={self.user_id}, used={self.used_at is not None})>"

    def is_valid(self) -> bool:
        """Check if reset token is still valid (not expired and not used)."""
        if self.used_at:
            return False
        if self.expires_at < datetime.utcnow():
            return False
        return True
