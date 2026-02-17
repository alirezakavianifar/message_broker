"""
Message Broker Main Server

Central server providing:
- Internal API (proxy → server, worker → server)
- Admin API (certificate management, user management, statistics)
- Portal API (authentication, message viewing)
- Health monitoring and metrics
"""

import logging
import os
import sys
import asyncio
import hashlib
import json
import secrets
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, List, Dict, Any, Generator

from fastapi import (
    FastAPI,
    Depends,
    HTTPException,
    Request,
    status,
    Security,
)
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from logging.handlers import TimedRotatingFileHandler
from pydantic import BaseModel, Field, EmailStr, validator
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, text
import jwt
from passlib.context import CryptContext
import redis
import httpx

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from main_server.models import (
    User,
    Client,
    Message,
    AuditLog,
    PasswordReset,
    UserRole,
    ClientStatus,
    MessageStatus,
)
import secrets
from main_server.database import DatabaseManager
from main_server.encryption import EncryptionManager, mask_phone_number
from main_server.email_utils import EmailManager

# ============================================================================
# Configuration
# ============================================================================

class Config:
    """Server configuration"""
    
    # Base directory (main_server directory)
    BASE_DIR = Path(__file__).parent
    
    # Database
    DATABASE_URL = os.getenv(
        "DATABASE_URL",
        "mysql+pymysql://systemuser:StrongPass123!@localhost/message_system"
    )
    
    # Encryption
    ENCRYPTION_KEY_PATH = os.getenv(
        "ENCRYPTION_KEY_PATH", 
        str(BASE_DIR / "secrets" / "encryption.key")
    )
    HASH_SALT = os.getenv("HASH_SALT", "message_broker_salt_change_in_production")
    
    # JWT
    JWT_SECRET = os.getenv("JWT_SECRET", "change_this_secret_in_production")
    JWT_ALGORITHM = "HS256"
    JWT_EXPIRATION_HOURS = 24
    JWT_REFRESH_EXPIRATION_DAYS = 30
    
    # TLS
    CA_CERT_PATH = os.getenv("CA_CERT_PATH", "certs/ca.crt")
    SERVER_CERT_PATH = os.getenv("SERVER_CERT_PATH", "certs/server.crt")
    SERVER_KEY_PATH = os.getenv("SERVER_KEY_PATH", "certs/server.key")
    CRL_PATH = os.getenv("CRL_PATH", "crl/revoked.pem")
    
    # Server
    HOST = os.getenv("MAIN_SERVER_HOST", "0.0.0.0")
    PORT = int(os.getenv("MAIN_SERVER_PORT", "8000"))
    
    # Logging
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
    LOG_DIR = Path(os.getenv("LOG_FILE_PATH", str(BASE_DIR / "logs")))
    LOG_DIR.mkdir(exist_ok=True)
    
    # Metrics
    METRICS_ENABLED = os.getenv("METRICS_ENABLED", "true").lower() == "true"

    # SMTP Configuration
    SMTP_HOST = os.getenv("SMTP_HOST", "localhost")
    SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER = os.getenv("SMTP_USER", "")
    SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
    SMTP_FROM = os.getenv("SMTP_FROM", "noreply@example.com")
    PORTAL_URL = os.getenv("PORTAL_URL", "http://localhost:8080")

config = Config()

# ============================================================================
# Logging Setup
# ============================================================================

def setup_logging():
    """Setup logging with daily rotation"""
    logger = logging.getLogger("main_server")
    logger.setLevel(getattr(logging, config.LOG_LEVEL))
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)
    
    # File handler with daily rotation
    # Use try-except to handle Windows log rotation issues with multiple workers
    try:
        log_file = config.LOG_DIR / "main_server.log"
        file_handler = TimedRotatingFileHandler(
            log_file,
            when='midnight',
            interval=1,
            backupCount=7,
            encoding='utf-8',
            delay=True  # Delay file opening to reduce lock conflicts
        )
        file_handler.setLevel(logging.DEBUG)
        file_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s'
        )
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        # If file logging fails (e.g., permission issues), continue with console only
        print(f"Warning: Could not setup file logging: {e}")
        print("Continuing with console logging only...")
    
    return logger

logger = setup_logging()

# ============================================================================
# Security
# ============================================================================

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# HTTP Bearer for JWT
security = HTTPBearer()

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify password against hash"""
    import bcrypt
    # Truncate password to 72 bytes for bcrypt compatibility
    password_bytes = plain_password.encode('utf-8')[:72]
    return bcrypt.checkpw(password_bytes, hashed_password.encode('utf-8'))

def get_password_hash(password: str) -> str:
    """Generate password hash (bcrypt has 72 byte limit)"""
    import bcrypt
    # Truncate password to 72 bytes for bcrypt compatibility
    password_bytes = password.encode('utf-8')[:72]
    # Use bcrypt directly to avoid passlib's length check
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT access token"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(hours=config.JWT_EXPIRATION_HOURS)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Optional[dict]:
    """Decode and verify JWT token"""
    try:
        payload = jwt.decode(token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        logger.warning("Token expired")
        return None
    except jwt.PyJWTError as e:
        logger.warning(f"JWT error: {e}")
        return None

# ============================================================================
# Prometheus Metrics
# ============================================================================

# Request metrics
requests_total = Counter(
    'main_server_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

request_duration = Histogram(
    'main_server_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint']
)

# Message metrics
messages_registered = Counter(
    'main_server_messages_registered_total',
    'Total messages registered',
    ['client_id']
)

messages_delivered = Counter(
    'main_server_messages_delivered_total',
    'Total messages delivered',
    ['client_id']
)

messages_failed = Counter(
    'main_server_messages_failed_total',
    'Total failed messages',
    ['client_id', 'reason']
)

# Database metrics
db_connections = Gauge(
    'main_server_db_connections',
    'Active database connections'
)

# Certificate metrics
certificates_issued = Counter(
    'main_server_certificates_issued_total',
    'Total certificates issued'
)

certificates_revoked = Counter(
    'main_server_certificates_revoked_total',
    'Total certificates revoked'
)

# ============================================================================
# Global Instances
# ============================================================================

# Database manager
db_manager: Optional[DatabaseManager] = None

# Encryption manager
encryption_manager: Optional[EncryptionManager] = None

# Email manager
email_manager: Optional[EmailManager] = None

# Redis connection for enqueuing messages
redis_client: Optional[redis.Redis] = None

# ============================================================================
# Lifespan Management
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown"""
    # Startup
    global db_manager, encryption_manager, redis_client
    
    logger.info("Starting Main Server...")
    
    # Initialize database
    try:
        db_manager = DatabaseManager(
            config.DATABASE_URL,
            pool_size=10,
            max_overflow=20,
            echo=(config.LOG_LEVEL == "DEBUG")
        )
        logger.info("Database manager initialized")
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        raise
    
    # Initialize encryption
    try:
        encryption_manager = EncryptionManager(
            key_path=config.ENCRYPTION_KEY_PATH,
            salt=config.HASH_SALT
        )
        logger.info("Encryption manager initialized")
    except Exception as e:
        logger.error(f"Failed to initialize encryption: {e}")
        raise
    
    # Initialize Redis connection (optional, for enqueuing messages)
    try:
        redis_host = os.getenv("REDIS_HOST", "localhost")
        redis_port = int(os.getenv("REDIS_PORT", "6379"))
        redis_password = os.getenv("REDIS_PASSWORD", None)
        redis_client = redis.Redis(
            host=redis_host,
            port=redis_port,
            password=redis_password if redis_password else None,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_keepalive=True
        )
        redis_client.ping()
        logger.info(f"Redis connection initialized at {redis_host}:{redis_port}")
    except Exception as e:
        logger.warning(f"Redis connection failed (messages may not be enqueued): {e}")
        redis_client = None  # Continue without Redis - proxy will handle enqueuing
    
    logger.info("Main Server started successfully")
    
    # Initialize email manager
    global email_manager
    email_manager = EmailManager(
        host=config.SMTP_HOST,
        port=config.SMTP_PORT,
        user=config.SMTP_USER,
        password=config.SMTP_PASSWORD,
        from_addr=config.SMTP_FROM
    )
    logger.info("Email manager initialized")

    yield
    
    # Shutdown
    logger.info("Shutting down Main Server...")
    
    if redis_client:
        try:
            redis_client.close()
            logger.info("Redis connection closed")
        except Exception:
            pass
    
    if db_manager:
        db_manager.dispose()
        logger.info("Database connections closed")
    
    logger.info("Main Server shutdown complete")

# ============================================================================
# FastAPI Application
# ============================================================================

app = FastAPI(
    title="Message Broker Main Server",
    description="Central server for message broker system with mutual TLS authentication",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================================
# Dependencies
# ============================================================================

def get_db() -> Generator[Session, None, None]:
    """Get database session"""
    with db_manager.get_session() as session:
        yield session

def get_encryption() -> EncryptionManager:
    """Get encryption manager"""
    if encryption_manager is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Encryption manager not initialized"
        )
    return encryption_manager

def get_client_from_cert(request: Request) -> str:
    """
    Extract client ID from certificate CN
    
    In production, this would extract from the SSL certificate.
    For development, we use a header.
    """
    # Try to get from certificate (populated by reverse proxy or ASGI server)
    cert_subject = request.headers.get("X-SSL-Client-Subject-DN")
    
    if cert_subject:
        # Extract CN from subject DN
        # Format: /CN=client_name/O=Organization/...
        for part in cert_subject.split("/"):
            if part.startswith("CN="):
                return part[3:]
    
    # Development fallback: use header
    client_id = request.headers.get("X-Client-ID")
    if not client_id:
        logger.warning("No client certificate found in request")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Client certificate required"
        )
    
    return client_id

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Security(security),
    db: Session = Depends(get_db)
) -> User:
    """Get current authenticated user from JWT"""
    token = credentials.credentials
    payload = decode_access_token(token)
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload"
        )
    
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is inactive"
        )
    
    # Update last login
    user.last_login = datetime.utcnow()
    db.commit()
    
    return user

async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Require admin role"""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return current_user

async def require_admin_or_user_manager(current_user: User = Depends(get_current_user)) -> User:
    """Require admin or user_manager role"""
    if current_user.role not in [UserRole.ADMIN, UserRole.USER_MANAGER]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin or user manager access required"
        )
    return current_user

# ============================================================================
# Request/Response Models
# ============================================================================

# Internal API Models
class RegisterMessageRequest(BaseModel):
    """Request to register a new message"""
    message_id: str = Field(..., description="UUID for the message")
    client_id: str = Field(..., description="Client identifier")
    sender_number: str = Field(..., description="Sender phone number (E.164)")
    message_body: str = Field(..., min_length=1, max_length=1000, description="Message content")
    queued_at: datetime = Field(..., description="Time message was queued")
    domain: Optional[str] = Field("default", description="Message domain")
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Additional metadata")

class DeliverMessageRequest(BaseModel):
    """Request to mark message as delivered"""
    message_id: str = Field(..., description="Message UUID")
    worker_id: str = Field(..., description="Worker identifier")

class UpdateStatusRequest(BaseModel):
    """Request to update message status"""
    status: str = Field(..., description="New status")
    attempt_count: int = Field(..., ge=0, description="Current attempt count")
    error_message: Optional[str] = Field(None, description="Error message if failed")

# Portal API Models
class LoginRequest(BaseModel):
    """Login request"""
    email: str = Field(..., description="User email")
    password: str = Field(..., description="User password")

class LoginResponse(BaseModel):
    """Login response"""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: Dict[str, Any]

class RefreshTokenRequest(BaseModel):
    """Refresh token request"""
    refresh_token: str

class MessageResponse(BaseModel):
    """Message response for portal"""
    id: int
    message_id: str
    client_id: str
    sender_number_masked: str
    message_body: Optional[str] = None  # Only if user authorized
    status: str
    attempt_count: int
    created_at: datetime
    queued_at: Optional[datetime]
    delivered_at: Optional[datetime]

    class Config:
        from_attributes = True

class UserResponse(BaseModel):
    """User response"""
    id: int
    email: str
    role: str
    is_active: bool
    created_at: datetime
    last_login: Optional[datetime] = None  # Changed from last_login_at to match model

    class Config:
        from_attributes = True

# Admin API Models
class GenerateCertRequest(BaseModel):
    """Request to generate client certificate"""
    client_id: str = Field(..., description="Client identifier")
    domain: Optional[str] = Field(None, description="Client domain")
    validity_days: int = Field(365, ge=1, le=3650, description="Certificate validity in days")

class RevokeCertRequest(BaseModel):
    """Request to revoke certificate"""
    client_id: str = Field(..., description="Client identifier")
    reason: str = Field(..., description="Revocation reason")

class CreateUserRequest(BaseModel):
    """Request to create user"""
    email: str = Field(..., description="User email")
    password: str = Field(..., min_length=8, description="User password")
    role: str = Field("user", description="User role (user/admin)")
    client_id: Optional[str] = Field(None, description="Associated client ID for regular users")

class UpdateUserRoleRequest(BaseModel):
    """Request to update user role"""
    role: str = Field(..., description="New user role (user/admin/user_manager)")

class UpdateUserPasswordRequest(BaseModel):
    """Request to change user password"""
    new_password: str = Field(..., min_length=8, description="New password")

class UpdateUserStatusRequest(BaseModel):
    """Request to update user status"""
    is_active: bool = Field(..., description="Whether user is active")


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str = Field(..., min_length=8)


class DBStatusResponse(BaseModel):
    database_name: str
    size_mb: float
    table_counts: Dict[str, int]
    connection_pool: Dict[str, Any]


class BackupInfo(BaseModel):
    filename: str
    size_mb: float
    created_at: str


class TLSStatusResponse(BaseModel):
    is_valid: bool
    issuer: str
    expires_at: str
    days_left: int


class StatsResponse(BaseModel):
    """System statistics"""
    total_messages: int
    messages_by_status: Dict[str, int]
    total_clients: int
    active_clients: int
    revoked_clients: int
    messages_last_24h: int
    messages_last_7d: int
    messages_last_30d: int = 0

# ============================================================================
# Internal API (Mutual TLS Required)
# ============================================================================

@app.post("/internal/messages/register", tags=["Internal"])
async def register_message(
    request: RegisterMessageRequest,
    db: Session = Depends(get_db),
    encryption: EncryptionManager = Depends(get_encryption),
):
    """
    Register a new message (called by proxy)
    
    This endpoint is called by the proxy when a message is submitted.
    The message body is encrypted before storage.
    """
    try:
        # Encrypt message body
        encrypted_body, key_version = encryption.encrypt_message(request.message_body)
        
        # Hash sender number
        sender_hash = encryption.hash_phone_number(request.sender_number)
        
        # Create message record
        message = Message(
            message_id=request.message_id,
            client_id=request.client_id,
            encrypted_body=encrypted_body,
            sender_number_hashed=sender_hash,
            status=MessageStatus.QUEUED,
            queued_at=request.queued_at,
            attempt_count=0,
            encryption_key_version=key_version,
        )
        
        db.add(message)
        db.commit()
        db.refresh(message)
        
        # Update metrics
        messages_registered.labels(client_id=request.client_id).inc()
        
        # Audit log
        audit = AuditLog(
            event_type="message_registered",
            user_id=None,
            client_id=request.client_id,
            event_data={"message_id": request.message_id, "client_id": request.client_id}
        )
        db.add(audit)
        db.commit()
        
        # Enqueue message to Redis if Redis is available
        # This ensures messages registered directly (bypassing proxy) still get processed
        if redis_client:
            try:
                message_data = {
                    "message_id": request.message_id,
                    "sender_number": request.sender_number,
                    "message_body": request.message_body,
                    "client_id": request.client_id,
                    "domain": request.domain or "default",
                    "queued_at": request.queued_at,
                    "attempt_count": 0,
                    "metadata": request.metadata.dict() if request.metadata else {}
                }
                message_json = json.dumps(message_data)
                redis_client.lpush("message_queue", message_json)
                logger.debug(f"Message enqueued to Redis: {request.message_id}")
            except Exception as e:
                logger.warning(f"Failed to enqueue message to Redis: {e} (worker may pick it up later)")
        else:
            logger.debug("Redis not available, message not enqueued (proxy should handle enqueuing)")
        
        logger.info(f"Message registered: {request.message_id} for client {request.client_id}")
        
        return {
            "status": "success",
            "message_id": request.message_id,
            "id": message.id,
            "registered_at": message.created_at.isoformat()
        }
        
    except Exception as e:
        logger.error(f"Failed to register message {request.message_id}: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to register message: {str(e)}"
        )

@app.post("/internal/messages/deliver", tags=["Internal"])
async def deliver_message(
    request: DeliverMessageRequest,
    db: Session = Depends(get_db),
):
    """
    Mark message as delivered (called by worker)
    
    This endpoint is called by workers when a message is successfully delivered.
    """
    try:
        message = db.query(Message).filter(
            Message.message_id == request.message_id
        ).first()
        
        if not message:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Message not found: {request.message_id}"
            )
        
        # Update message status
        message.status = MessageStatus.DELIVERED
        message.delivered_at = datetime.utcnow()
        
        db.commit()
        
        # Update metrics
        messages_delivered.labels(client_id=message.client_id).inc()
        
        # Audit log
        audit = AuditLog(
            event_type="message_delivered",
            user_id=None,
            event_data={"message_id": request.message_id, "worker_id": request.worker_id}
        )
        db.add(audit)
        db.commit()
        
        logger.info(f"Message delivered: {request.message_id} by {request.worker_id}")
        
        return {
            "status": "success",
            "delivered_at": message.delivered_at.isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to mark message as delivered {request.message_id}: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to mark as delivered: {str(e)}"
        )

@app.put("/internal/messages/{message_id}/status", tags=["Internal"])
async def update_message_status(
    message_id: str,
    request: UpdateStatusRequest,
    db: Session = Depends(get_db),
):
    """
    Update message status (called by worker for retries/failures)
    """
    try:
        message = db.query(Message).filter(
            Message.message_id == message_id
        ).first()
        
        if not message:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Message not found: {message_id}"
            )
        
        # Update status
        old_status = message.status
        message.status = MessageStatus(request.status)
        message.attempt_count = request.attempt_count
        
        if request.status == "failed":
            messages_failed.labels(
                client_id=message.client_id,
                reason=request.error_message or "unknown"
            ).inc()
        
        db.commit()
        
        logger.info(
            f"Message status updated: {message_id} "
            f"{old_status.value} → {request.status} "
            f"(attempt {request.attempt_count})"
        )
        
        return {"status": "updated"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update status for {message_id}: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update status: {str(e)}"
        )

# ============================================================================
# Portal API (JWT Authentication)
# ============================================================================

@app.post("/portal/auth/login", response_model=LoginResponse, tags=["Portal"])
async def portal_login(
    request: LoginRequest,
    db: Session = Depends(get_db),
):
    """
    Portal login endpoint
    
    Authenticates user and returns JWT tokens.
    """
    try:
        # Find user
        user = db.query(User).filter(User.email == request.email).first()
        
        if not user or not verify_password(request.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account is inactive"
            )
        
        # Create tokens
        access_token = create_access_token(
            data={"sub": str(user.id), "email": user.email, "role": user.role.value}
        )
        
        refresh_token = create_access_token(
            data={"sub": str(user.id), "type": "refresh"},
            expires_delta=timedelta(days=config.JWT_REFRESH_EXPIRATION_DAYS)
        )
        
        # Update last login
        user.last_login = datetime.utcnow()
        db.commit()
        
        return LoginResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=config.JWT_EXPIRATION_HOURS * 3600,
            user=user.to_dict()
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Login failed for {request.email}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed"
        )


@app.post("/portal/auth/forgot-password", tags=["Portal"])
async def forgot_password(
    request: ForgotPasswordRequest,
    db: Session = Depends(get_db),
):
    """
    Initiate password reset process.
    
    Generates a secure token and sends an email to the user.
    """
    user = db.query(User).filter(User.email == request.email).first()
    
    # Security: Don't reveal if user exists or not
    if not user:
        logger.warning(f"Password reset requested for non-existent email: {request.email}")
        return {"message": "If your email is registered, you will receive a reset link shortly."}

    # Generate token
    token = secrets.token_urlsafe(32)
    expires_at = datetime.utcnow() + timedelta(hours=1)
    
    # Store token
    reset_entry = PasswordReset(
        user_id=user.id,
        token=token,
        expires_at=expires_at
    )
    db.add(reset_entry)
    db.commit()
    
    # Send email
    reset_url = f"{config.PORTAL_URL}/reset-password?token={token}"
    if email_manager:
        success = email_manager.send_password_reset(user.email, reset_url)
        if not success:
            logger.error(f"Failed to send password reset email to {user.email}")
            # We still return success to the user to avoid enumeration
    else:
        logger.error("Email manager not initialized. Reset URL: %s", reset_url)

    return {"message": "If your email is registered, you will receive a reset link shortly."}


@app.post("/portal/auth/reset-password", tags=["Portal"])
async def reset_password(
    request: ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    """
    Reset password using a token.
    """
    # Find token
    reset_entry = db.query(PasswordReset).filter(
        PasswordReset.token == request.token
    ).first()
    
    if not reset_entry or not reset_entry.is_valid():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset token"
        )
    
    # Update password
    user = db.query(User).get(reset_entry.user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    user.password_hash = hash_password(request.new_password)
    reset_entry.used_at = datetime.utcnow()
    
    # Audit log
    audit = AuditLog(
        event_type="password_reset_confirm",
        user_id=user.id,
        severity=AuditSeverity.WARNING,
        event_data={"email": user.email}
    )
    db.add(audit)
    db.commit()
    
    return {"message": "Password has been successfully reset."}


@app.post("/portal/auth/refresh", tags=["Portal"])
async def refresh_token(
    request: RefreshTokenRequest,
    db: Session = Depends(get_db),
):
    """Refresh access token using refresh token"""
    payload = decode_access_token(request.refresh_token)
    
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )
    
    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive"
        )
    
    # Create new access token
    access_token = create_access_token(
        data={"sub": str(user.id), "email": user.email, "role": user.role.value}
    )
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": config.JWT_EXPIRATION_HOURS * 3600
    }

@app.get("/portal/messages", response_model=List[MessageResponse], tags=["Portal"])
async def get_portal_messages(
    skip: int = 0,
    limit: int = 100,
    status_filter: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    encryption: EncryptionManager = Depends(get_encryption),
):
    """
    Get messages for portal (users see their own, admins see all)
    """
    query = db.query(Message)
    
    # Filter by client for non-admin users
    if current_user.role != UserRole.ADMIN:
        # Users should only see messages for clients they're associated with
        if current_user.client_id:
            query = query.filter(Message.client_id == current_user.client_id)
        else:
            # Users without a client_id see no messages
            query = query.filter(text("1 = 0"))  # Always returns empty result
    
    # Status filter
    if status_filter:
        query = query.filter(Message.status == MessageStatus(status_filter))
    
    # Pagination
    messages = query.order_by(desc(Message.created_at)).offset(skip).limit(limit).all()
    
    # Build response
    response = []
    for msg in messages:
        msg_dict = {
            "id": msg.id,
            "message_id": msg.message_id,
            "client_id": msg.client_id,
            "sender_number_masked": mask_phone_number(msg.sender_number_hashed) if msg.sender_number_hashed else "N/A",
            "status": msg.status.value,
            "attempt_count": msg.attempt_count,
            "created_at": msg.created_at,
            "queued_at": msg.queued_at,
            "delivered_at": msg.delivered_at,
        }
        
        # Decrypt body for authorized users
        if current_user.role == UserRole.ADMIN:
            try:
                key_version = msg.encryption_key_version or 1
                msg_dict["message_body"] = encryption.decrypt_message(msg.encrypted_body, key_version=key_version)
            except Exception as e:
                logger.warning(f"Failed to decrypt message {msg.id}: {e}")
                msg_dict["message_body"] = "[decryption failed]"
        
        response.append(MessageResponse(**msg_dict))
    
    return response

@app.get("/portal/profile", response_model=UserResponse, tags=["Portal"])
async def get_profile(
    current_user: User = Depends(get_current_user),
):
    """Get current user profile"""
    return UserResponse.from_orm(current_user)

# ============================================================================
# Admin API (Admin Role Required)
# ============================================================================

@app.post("/admin/certificates/generate", tags=["Admin"])
async def generate_certificate(
    request: GenerateCertRequest,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Generate client certificate (admin only)
    
    Note: This is a placeholder. Actual certificate generation
    should call generate_cert.bat/sh script.
    """
    try:
        # Check if client exists
        client = db.query(Client).filter(Client.client_id == request.client_id).first()
        
        if client:
            if client.status == ClientStatus.ACTIVE:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Client {request.client_id} already has an active certificate"
                )
        else:
            # Create new client record
            client = Client(
                client_id=request.client_id,
                cert_fingerprint="",  # Will be updated after cert generation
                status=ClientStatus.ACTIVE,
                domain=request.domain,
                issued_at=datetime.utcnow(),
                expires_at=datetime.utcnow() + timedelta(days=request.validity_days),
            )
            db.add(client)
        
        # TODO: Call certificate generation script
        # For now, just log the request
        logger.info(
            f"Certificate generation requested for {request.client_id} "
            f"by {current_user.email} (validity: {request.validity_days} days)"
        )
        
        # Update metrics
        certificates_issued.inc()
        
        # Audit log
        audit = AuditLog(
            event_type="certificate_generated",
            user_id=current_user.id,
            client_id=request.client_id,
            event_data={
                "client_id": request.client_id,
                "validity_days": request.validity_days,
                "domain": request.domain,
            },
        )
        db.add(audit)
        db.commit()
        
        return {
            "status": "success",
            "message": f"Certificate generation initiated for {request.client_id}",
            "client_id": request.client_id,
            "expires_at": client.expires_at.isoformat() if client.expires_at else None,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to generate certificate: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Certificate generation failed: {str(e)}"
        )

@app.post("/admin/certificates/revoke", tags=["Admin"])
async def revoke_certificate(
    request: RevokeCertRequest,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Revoke client certificate (admin only)
    """
    try:
        client = db.query(Client).filter(Client.client_id == request.client_id).first()
        
        if not client:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Client not found: {request.client_id}"
            )
        
        if client.status == ClientStatus.REVOKED:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Certificate already revoked for {request.client_id}"
            )
        
        # Update client status
        client.status = ClientStatus.REVOKED
        client.revoked_at = datetime.utcnow()
        
        db.commit()
        
        # Update metrics
        certificates_revoked.inc()
        
        # Audit log
        audit = AuditLog(
            event_type="certificate_revoked",
            user_id=current_user.id,
            client_id=request.client_id,
            event_data={
                "client_id": request.client_id,
                "reason": request.reason,
            },
        )
        db.add(audit)
        db.commit()
        
        # TODO: Update CRL file
        logger.info(
            f"Certificate revoked for {request.client_id} "
            f"by {current_user.email} (reason: {request.reason})"
        )
        
        return {
            "status": "success",
            "message": f"Certificate revoked for {request.client_id}",
            "revoked_at": client.revoked_at.isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to revoke certificate: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Certificate revocation failed: {str(e)}"
        )

@app.post("/admin/users", response_model=UserResponse, tags=["Admin"])
async def create_user(
    request: CreateUserRequest,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Create new user (admin only)"""
    try:
        # Check if email exists
        existing = db.query(User).filter(User.email == request.email).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        
        # Validate client_id if provided
        if request.client_id:
            client = db.query(Client).filter(Client.client_id == request.client_id).first()
            if not client:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Client not found: {request.client_id}"
                )
        
        # Create user
        # Map role string to enum (handle case-insensitive input)
        role_str = request.role.lower().strip()
        role_map = {"admin": UserRole.ADMIN, "user": UserRole.USER, "user_manager": UserRole.USER_MANAGER}
        user_role = role_map.get(role_str)
        if not user_role:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid role: {request.role}. Must be 'user', 'admin', or 'user_manager'"
            )
        
        user = User(
            email=request.email,
            password_hash=get_password_hash(request.password),
            role=user_role,
            client_id=request.client_id,
            is_active=True,
        )
        
        db.add(user)
        db.commit()
        db.refresh(user)
        
        # Audit log
        audit = AuditLog(
            event_type="user_created",
            user_id=current_user.id,
            event_data={"email": user.email, "role": request.role, "client_id": request.client_id}
        )
        db.add(audit)
        db.commit()
        
        logger.info(f"User created: {user.email} by {current_user.email}")
        
        return UserResponse.from_orm(user)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to create user: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"User creation failed: {str(e)}"
        )

@app.put("/admin/users/{user_id}/role", response_model=UserResponse, tags=["Admin"])
async def update_user_role(
    user_id: int,
    request: UpdateUserRoleRequest,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Update user role (admin only)"""
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Map role string to enum
        role_str = request.role.lower().strip()
        role_map = {"admin": UserRole.ADMIN, "user": UserRole.USER, "user_manager": UserRole.USER_MANAGER}
        user_role = role_map.get(role_str)
        if not user_role:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid role: {request.role}. Must be 'user', 'admin', or 'user_manager'"
            )
        
        if user.role == user_role:
            return UserResponse.from_orm(user)
            
        old_role = user.role.value
        user.role = user_role
        db.commit()
        db.refresh(user)
        
        # Audit log
        audit = AuditLog(
            event_type="user_role_updated",
            user_id=current_user.id,
            event_data={
                "target_user_id": user_id,
                "target_email": user.email,
                "old_role": old_role,
                "new_role": user_role.value
            }
        )
        db.add(audit)
        db.commit()
        
        logger.info(f"User role updated for {user.email}: {old_role} -> {user_role.value} by {current_user.email}")
        
        return UserResponse.from_orm(user)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update user role: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"User role update failed: {str(e)}"
        )


@app.get("/admin/users", response_model=List[UserResponse], tags=["Admin"])
async def list_users(
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """List all users (admin only)"""
    users = db.query(User).offset(skip).limit(limit).all()
    return [UserResponse.from_orm(user) for user in users]

@app.get("/admin/stats", response_model=StatsResponse, tags=["Admin"])
async def get_stats(
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Get system statistics (admin only)"""
    try:
        # Total messages
        total_messages = db.query(func.count(Message.id)).scalar()
        
        # Messages by status
        status_counts = db.query(
            Message.status,
            func.count(Message.id)
        ).group_by(Message.status).all()
        
        messages_by_status = {
            status.value: count for status, count in status_counts
        }
        
        # Total clients
        total_clients = db.query(func.count(Client.id)).scalar()
        
        # Active/revoked clients
        active_clients = db.query(func.count(Client.id)).filter(
            Client.status == ClientStatus.ACTIVE
        ).scalar()
        
        revoked_clients = db.query(func.count(Client.id)).filter(
            Client.status == ClientStatus.REVOKED
        ).scalar()
        
        # Messages last 24 hours
        day_ago = datetime.utcnow() - timedelta(days=1)
        messages_last_24h = db.query(func.count(Message.id)).filter(
            Message.created_at >= day_ago
        ).scalar()
        
        # Messages last 7 days
        week_ago = datetime.utcnow() - timedelta(days=7)
        messages_last_7d = db.query(func.count(Message.id)).filter(
            Message.created_at >= week_ago
        ).scalar()
        
        # Messages last 30 days
        month_ago = datetime.utcnow() - timedelta(days=30)
        messages_last_30d = db.query(func.count(Message.id)).filter(
            Message.created_at >= month_ago
        ).scalar()
        
        return StatsResponse(
            total_messages=total_messages or 0,
            messages_by_status=messages_by_status,
            total_clients=total_clients or 0,
            active_clients=active_clients or 0,
            revoked_clients=revoked_clients or 0,
            messages_last_24h=messages_last_24h or 0,
            messages_last_7d=messages_last_7d or 0,
            messages_last_30d=messages_last_30d or 0,
        )
        
    except Exception as e:
        logger.error(f"Failed to get stats: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve statistics"
        )

# ============================================================================
# User Status & Password (Admin/User Manager)
# ============================================================================

@app.put("/admin/users/{user_id}/status", response_model=UserResponse, tags=["Admin"])
async def update_user_status(
    user_id: int,
    request: UpdateUserStatusRequest,
    current_user: User = Depends(require_admin_or_user_manager),
    db: Session = Depends(get_db),
):
    """Activate or deactivate a user"""
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        if user.id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot change your own active status"
            )
        old_status = user.is_active
        user.is_active = request.is_active
        db.commit()
        db.refresh(user)
        audit = AuditLog(
            event_type="user_status_updated",
            user_id=current_user.id,
            event_data={"target_user_id": user_id, "target_email": user.email,
                        "old_status": old_status, "new_status": request.is_active}
        )
        db.add(audit)
        db.commit()
        action = "activated" if request.is_active else "deactivated"
        logger.info(f"User {action}: {user.email} by {current_user.email}")
        return UserResponse.from_orm(user)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update user status: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"User status update failed: {str(e)}")


@app.put("/admin/users/{user_id}/password", tags=["Admin"])
async def update_user_password(
    user_id: int,
    request: UpdateUserPasswordRequest,
    current_user: User = Depends(require_admin_or_user_manager),
    db: Session = Depends(get_db),
):
    """Change user password"""
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        user.password_hash = get_password_hash(request.new_password)
        db.commit()
        audit = AuditLog(
            event_type="user_password_changed",
            user_id=current_user.id,
            event_data={"target_user_id": user_id, "target_email": user.email}
        )
        db.add(audit)
        db.commit()
        logger.info(f"Password changed for {user.email} by {current_user.email}")
        return {"status": "success", "message": f"Password updated for {user.email}"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to change password: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Password change failed: {str(e)}")


# ============================================================================
# Proxy Status Monitoring
# ============================================================================

@app.get("/admin/proxies/status", tags=["Admin"])
async def get_proxy_statuses(
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Get status of all configured proxy servers"""
    proxy_urls_str = os.getenv("PROXY_URLS", os.getenv("PROXY_URL", "https://localhost:8001"))
    proxy_urls = [u.strip() for u in proxy_urls_str.split(",") if u.strip()]
    results = []
    for proxy_url in proxy_urls:
        health_url = f"{proxy_url}/api/v1/health"
        try:
            async with httpx.AsyncClient(verify=False, timeout=httpx.Timeout(5.0)) as client:
                response = await client.get(health_url)
                if response.status_code == 200:
                    results.append({"url": proxy_url, "status": "online",
                                    "health": response.json(),
                                    "checked_at": datetime.utcnow().isoformat()})
                else:
                    results.append({"url": proxy_url, "status": "unhealthy",
                                    "error": f"HTTP {response.status_code}",
                                    "checked_at": datetime.utcnow().isoformat()})
        except Exception as e:
            results.append({"url": proxy_url, "status": "offline",
                            "error": str(e),
                            "checked_at": datetime.utcnow().isoformat()})
    return {"proxies": results}


# ============================================================================
# Certificate Listing & Expiry
# ============================================================================

@app.get("/admin/certificates/list", tags=["Admin"])
async def list_certificates(
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """List all client certificates"""
    clients = db.query(Client).order_by(Client.expires_at.asc()).all()
    return [{"client_id": c.client_id, "domain": c.domain, "status": c.status.value,
             "issued_at": c.issued_at.isoformat(), "expires_at": c.expires_at.isoformat(),
             "revoked_at": c.revoked_at.isoformat() if c.revoked_at else None,
             "is_valid": c.is_valid()} for c in clients]


@app.get("/admin/certificates/expiring", tags=["Admin"])
async def get_expiring_certificates(
    days: int = 30,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Get certificates expiring within N days"""
    cutoff_date = datetime.utcnow() + timedelta(days=days)
    expiring = db.query(Client).filter(
        Client.status == ClientStatus.ACTIVE,
        Client.expires_at <= cutoff_date,
        Client.expires_at > datetime.utcnow()
    ).order_by(Client.expires_at.asc()).all()
    return [{"client_id": c.client_id, "domain": c.domain,
             "expires_at": c.expires_at.isoformat(),
             "days_remaining": (c.expires_at - datetime.utcnow()).days} for c in expiring]


# ============================================================================
# Data Retention
# ============================================================================

@app.post("/admin/data-retention/cleanup", tags=["Admin"])
async def run_data_cleanup(
    retention_days: int = 180,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Delete delivered/failed messages older than retention_days"""
    try:
        cutoff_date = datetime.utcnow() - timedelta(days=retention_days)
        deleted_count = db.query(Message).filter(
            (Message.delivered_at < cutoff_date) |
            ((Message.status == MessageStatus.FAILED) & (Message.created_at < cutoff_date))
        ).delete(synchronize_session=False)
        db.commit()
        audit = AuditLog(
            event_type="data_cleanup",
            user_id=current_user.id,
            event_data={"retention_days": retention_days,
                        "deleted_count": deleted_count,
                        "cutoff_date": cutoff_date.isoformat()}
        )
        db.add(audit)
        db.commit()
        logger.info(f"Data cleanup: {deleted_count} messages deleted (>{retention_days} days) by {current_user.email}")
        return {"status": "success", "deleted_count": deleted_count,
                "retention_days": retention_days, "cutoff_date": cutoff_date.isoformat()}
    except Exception as e:
        logger.error(f"Data cleanup failed: {e}", exc_info=True)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Data cleanup failed: {str(e)}")


# ============================================================================
# Health & Monitoring
# ============================================================================

@app.get("/health", tags=["Monitoring"])
async def health_check(db: Session = Depends(get_db)):
    """Health check endpoint"""
    try:
        # Check database
        db.execute(text("SELECT 1"))
        db_healthy = True
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        db_healthy = False
    
    health_status = {
        "status": "healthy" if db_healthy else "unhealthy",
        "timestamp": datetime.utcnow().isoformat(),
        "components": {
            "database": "healthy" if db_healthy else "unhealthy",
            "encryption": "healthy" if encryption_manager else "unhealthy",
        }
    }
    
    status_code = status.HTTP_200_OK if db_healthy else status.HTTP_503_SERVICE_UNAVAILABLE
    
    return JSONResponse(content=health_status, status_code=status_code)

@app.get("/metrics", tags=["Monitoring"])
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )

from fastapi import Response

@app.get("/", tags=["General"])
async def root():
    """Root endpoint"""
    return {
        "service": "Message Broker Main Server",
        "version": "1.0.0",
        "status": "running",
        "documentation": "/docs",
    }

# ============================================================================
# Error Handlers
# ============================================================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Handle HTTP exceptions"""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "status_code": exc.status_code,
        }
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle general exceptions"""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "status_code": 500,
        }
    )

# ============================================================================
# Main
# ============================================================================


@app.get("/admin/db/status", response_model=DBStatusResponse, tags=["Admin"])
async def get_db_status(
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Get database status and statistics.
    """
    try:
        # Get table row counts
        table_counts = {}
        for table in [User, Client, Message, AuditLog, PasswordReset]:
            count = db.query(func.count(table.id)).scalar()
            table_counts[table.__tablename__] = count or 0

        # Get database size (MySQL specific)
        size_query = f"""
            SELECT SUM(data_length + index_length) / 1024 / 1024 AS size_mb 
            FROM information_schema.TABLES 
            WHERE table_schema = '{os.getenv("DB_NAME", "message_system")}'
        """
        size_res = db.execute(text(size_query)).fetchone()
        size_mb = float(size_res[0]) if size_res and size_res[0] else 0.0

        return DBStatusResponse(
            database_name=os.getenv("DB_NAME", "message_system"),
            size_mb=round(size_mb, 2),
            table_counts=table_counts,
            connection_pool=db_manager.get_pool_stats() if db_manager else {}
        )
    except Exception as e:
        logger.error(f"Failed to get DB status: {e}")
        raise HTTPException(status_code=500, detail="Failed to get DB status")


@app.get("/admin/db/config", tags=["Admin"])
async def get_db_config(
    current_user: User = Depends(require_admin),
):
    """
    Get database configuration (sanitized).
    """
    return {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": os.getenv("DB_PORT", "3306"),
        "user": os.getenv("DB_USER", "systemuser"),
        "database": os.getenv("DB_NAME", "message_system"),
        "pool_size": 10,  # Default
        "max_overflow": 20
    }


@app.post("/admin/db/backup", tags=["Admin"])
async def trigger_backup(
    current_user: User = Depends(require_admin),
):
    """
    Trigger a manual database backup.
    """
    try:
        backup_script = config.BASE_DIR / "deployment" / "backup" / "backup.ps1"
        if not backup_script.exists():
            raise HTTPException(status_code=404, detail="Backup script not found")

        # Run backup script asynchronously
        # Note: In a real Windows environment, powershell.exe is used.
        cmd = f"powershell.exe -File {backup_script} -BackupRoot {config.BASE_DIR / 'backups'}"
        process = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        # We don't wait for completion here to avoid timeout, but we log the start
        logger.info(f"Manual backup triggered by {current_user.email}")
        
        return {"status": "started", "message": "Backup process has been started in the background."}
    except Exception as e:
        logger.error(f"Failed to trigger backup: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/db/backups", response_model=List[BackupInfo], tags=["Admin"])
async def list_backups(
    current_user: User = Depends(require_admin),
):
    """
    List available database backups.
    """
    backup_dir = config.BASE_DIR / "backups"
    if not backup_dir.exists():
        return []

    backups = []
    for f in backup_dir.glob("backup_*.zip"):
        stats = f.stat()
        backups.append(BackupInfo(
            filename=f.name,
            size_mb=round(stats.st_size / (1024 * 1024), 2),
            created_at=datetime.fromtimestamp(stats.st_ctime).isoformat()
        ))
    
    return sorted(backups, key=lambda x: x.created_at, reverse=True)


@app.get("/admin/tls/status", response_model=TLSStatusResponse, tags=["Admin"])
async def get_tls_status(
    current_user: User = Depends(require_admin),
):
    """
    Get TLS certificate status (stub for Let's Encrypt).
    """
    # In a real scenario, we'd check the cert files on disk
    cert_path = config.BASE_DIR / "main_server" / "certs" / "server-cert.pem"
    
    if cert_path.exists():
        return TLSStatusResponse(
            is_valid=True,
            issuer="Let's Encrypt / Internal CA",
            expires_at=(datetime.utcnow() + timedelta(days=60)).isoformat(),
            days_left=60
        )
    
    return TLSStatusResponse(
        is_valid=False,
        issuer="None",
        expires_at=datetime.utcnow().isoformat(),
        days_left=0
    )


if __name__ == "__main__":
    import uvicorn
    
    logger.info(f"Starting Main Server on {config.HOST}:{config.PORT}")
    
    uvicorn.run(
        app,
        host=config.HOST,
        port=config.PORT,
        log_level=config.LOG_LEVEL.lower(),
    )

