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
import uuid
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
from pydantic import BaseModel, Field, validator
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, text
import jwt
from passlib.context import CryptContext

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from main_server.models import (
    User,
    Client,
    Message,
    AuditLog,
    UserRole,
    ClientStatus,
    MessageStatus,
)
from main_server.database import DatabaseManager
from main_server.encryption import EncryptionManager

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
    log_file = config.LOG_DIR / "main_server.log"
    file_handler = TimedRotatingFileHandler(
        log_file,
        when='midnight',
        interval=1,
        backupCount=7,
        encoding='utf-8'
    )
    file_handler.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s'
    )
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)
    
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
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

def get_password_hash(password: str) -> str:
    """Generate password hash"""
    return pwd_context.hash(password)

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
    except jwt.JWTError as e:
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

# ============================================================================
# Lifespan Management
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown"""
    # Startup
    global db_manager, encryption_manager
    
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
    
    logger.info("Main Server started successfully")
    
    yield
    
    # Shutdown
    logger.info("Shutting down Main Server...")
    
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
    user.last_login_at = datetime.utcnow()
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
    last_login_at: Optional[datetime]

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

class StatsResponse(BaseModel):
    """System statistics"""
    total_messages: int
    messages_by_status: Dict[str, int]
    total_clients: int
    active_clients: int
    revoked_clients: int
    messages_last_24h: int
    messages_last_7d: int

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
        user.last_login_at = datetime.utcnow()
        db.commit()
        
        # Audit log
        audit = AuditLog(
            user_id=user.id,
            event_type="user_login",
            event_data={"email": user.email}
        )
        db.add(audit)
        db.commit()
        
        logger.info(f"User logged in: {user.email}")
        
        return LoginResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=config.JWT_EXPIRATION_HOURS * 3600,
            user={
                "id": user.id,
                "email": user.email,
                "role": user.role.value,
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Login failed for {request.email}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed"
        )

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
        # For now, we'll restrict to empty result for non-admin
        # In production, implement proper client-user association
        query = query.filter(Message.client_id == f"user_{current_user.id}")
    
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
            "sender_number_masked": encryption.mask_phone_number(msg.sender_number_hashed),
            "status": msg.status.value,
            "attempt_count": msg.attempt_count,
            "created_at": msg.created_at,
            "queued_at": msg.queued_at,
            "delivered_at": msg.delivered_at,
        }
        
        # Decrypt body for authorized users
        if current_user.role == UserRole.ADMIN:
            try:
                msg_dict["message_body"] = encryption.decrypt(msg.encrypted_body)
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
        
        # Create user
        user = User(
            email=request.email,
            password_hash=get_password_hash(request.password),
            role=UserRole(request.role),
            is_active=True,
        )
        
        db.add(user)
        db.commit()
        db.refresh(user)
        
        # Audit log
        audit = AuditLog(
            event_type="user_created",
            user_id=current_user.id,
            event_data={"email": user.email, "role": request.role}
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
        
        return StatsResponse(
            total_messages=total_messages or 0,
            messages_by_status=messages_by_status,
            total_clients=total_clients or 0,
            active_clients=active_clients or 0,
            revoked_clients=revoked_clients or 0,
            messages_last_24h=messages_last_24h or 0,
            messages_last_7d=messages_last_7d or 0,
        )
        
    except Exception as e:
        logger.error(f"Failed to get stats: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve statistics"
        )

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

if __name__ == "__main__":
    import uvicorn
    
    logger.info(f"Starting Main Server on {config.HOST}:{config.PORT}")
    
    uvicorn.run(
        app,
        host=config.HOST,
        port=config.PORT,
        log_level=config.LOG_LEVEL.lower(),
    )

