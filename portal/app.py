"""
Message Broker Web Portal

Web interface for users and administrators to view messages,
manage accounts, and monitor the system.
"""

import logging
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, List

import httpx
from fastapi import (
    FastAPI,
    Request,
    Form,
    Query,
    Depends,
    HTTPException,
    status,
)
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware
from logging.handlers import TimedRotatingFileHandler

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

# ============================================================================
# Configuration
# ============================================================================

class Config:
    """Portal configuration"""
    
    # Main server API
    MAIN_SERVER_URL = os.getenv("MAIN_SERVER_URL", "https://localhost:8000")
    MAIN_SERVER_VERIFY_SSL = os.getenv("MAIN_SERVER_VERIFY_SSL", "false").lower() == "true"
    
    # Portal server
    PORTAL_HOST = os.getenv("PORTAL_HOST", "0.0.0.0")
    PORTAL_PORT = int(os.getenv("PORTAL_PORT", "8080"))
    
    # Session
    SESSION_SECRET = os.getenv("SESSION_SECRET", "change_this_session_secret_in_production")
    SESSION_MAX_AGE = int(os.getenv("SESSION_MAX_AGE", "3600"))  # 1 hour
    
    # Logging
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
    LOG_DIR = Path(os.getenv("LOG_FILE_PATH", "logs"))
    LOG_DIR.mkdir(exist_ok=True)
    
    # Pagination
    MESSAGES_PER_PAGE = int(os.getenv("MESSAGES_PER_PAGE", "20"))

config = Config()

# ============================================================================
# Logging Setup
# ============================================================================

def setup_logging():
    """Setup logging with daily rotation"""
    logger = logging.getLogger("portal")
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
        log_file = config.LOG_DIR / "portal.log"
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
# FastAPI Application
# ============================================================================

app = FastAPI(
    title="Message Broker Portal",
    description="Web portal for message viewing and system management",
    version="1.0.0",
    docs_url=None,  # Disable for production
    redoc_url=None,
)

# Session middleware
app.add_middleware(
    SessionMiddleware,
    secret_key=config.SESSION_SECRET,
    max_age=config.SESSION_MAX_AGE,
)

# Static files and templates
static_path = Path(__file__).parent / "static"
static_path.mkdir(exist_ok=True)

templates_path = Path(__file__).parent / "templates"
templates = Jinja2Templates(directory=str(templates_path))

# Add custom Jinja filter for date formatting
def format_datetime(value, format='%Y-%m-%d %H:%M'):
    """Format datetime - handles both datetime objects and ISO strings"""
    if not value:
        return 'N/A'
    if isinstance(value, str):
        from datetime import datetime
        try:
            dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
            return dt.strftime(format)
        except:
            return value
    return value.strftime(format)

templates.env.filters['datetimeformat'] = format_datetime

# Mount static files
app.mount("/static", StaticFiles(directory=str(static_path)), name="static")

# ============================================================================
# API Client
# ============================================================================

class MainServerClient:
    """HTTP client for main server API"""
    
    def __init__(self):
        self.base_url = config.MAIN_SERVER_URL
        self.verify_ssl = config.MAIN_SERVER_VERIFY_SSL
        self.timeout = httpx.Timeout(30.0)
    
    async def login(self, email: str, password: str) -> dict:
        """Login to main server"""
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/portal/auth/login",
                json={"email": email, "password": password}
            )
            response.raise_for_status()
            return response.json()
    
    async def refresh_token(self, refresh_token: str) -> dict:
        """Refresh access token"""
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/portal/auth/refresh",
                json={"refresh_token": refresh_token}
            )
            response.raise_for_status()
            return response.json()
    
    async def get_messages(
        self,
        access_token: str,
        skip: int = 0,
        limit: int = 20,
        status_filter: Optional[str] = None
    ) -> List[dict]:
        """Get messages"""
        headers = {"Authorization": f"Bearer {access_token}"}
        params = {"skip": skip, "limit": limit}
        if status_filter:
            params["status_filter"] = status_filter
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/portal/messages",
                headers=headers,
                params=params
            )
            response.raise_for_status()
            return response.json()
    
    async def get_profile(self, access_token: str) -> dict:
        """Get user profile"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/portal/profile",
                headers=headers
            )
            response.raise_for_status()
            return response.json()
    
    async def get_stats(self, access_token: str) -> dict:
        """Get system statistics (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/stats",
                headers=headers
            )
            response.raise_for_status()
            return response.json()
    
    async def get_users(self, access_token: str) -> List[dict]:
        """Get all users (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/users",
                headers=headers
            )
            response.raise_for_status()
            return response.json()
    
    async def create_user(
        self,
        access_token: str,
        email: str,
        password: str,
        role: str
    ) -> dict:
        """Create new user (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/admin/users",
                headers=headers,
                json={"email": email, "password": password, "role": role}
            )
            response.raise_for_status()
            return response.json()
    
    async def generate_certificate(
        self,
        access_token: str,
        client_id: str,
        domain: Optional[str] = None,
        validity_days: int = 365
    ) -> dict:
        """Generate client certificate (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/admin/certificates/generate",
                headers=headers,
                json={
                    "client_id": client_id,
                    "domain": domain,
                    "validity_days": validity_days
                }
            )
            response.raise_for_status()
            return response.json()
    
    async def revoke_certificate(
        self,
        access_token: str,
        client_id: str,
        reason: str
    ) -> dict:
        """Revoke client certificate (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/admin/certificates/revoke",
                headers=headers,
                json={"client_id": client_id, "reason": reason}
            )
            response.raise_for_status()
            return response.json()

    async def update_user_role(
        self,
        access_token: str,
        user_id: int,
        role: str
    ) -> dict:
        """Update user role (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.put(
                f"{self.base_url}/admin/users/{user_id}/role",
                headers=headers,
                json={"role": role}
            )
            response.raise_for_status()
            return response.json()

    async def toggle_user_status(
        self,
        access_token: str,
        user_id: int,
        is_active: bool
    ) -> dict:
        """Activate or deactivate user"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.put(
                f"{self.base_url}/admin/users/{user_id}/status",
                headers=headers,
                json={"is_active": is_active}
            )
            response.raise_for_status()
            return response.json()

    async def change_user_password(
        self,
        access_token: str,
        user_id: int,
        new_password: str
    ) -> dict:
        """Change user password"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.put(
                f"{self.base_url}/admin/users/{user_id}/password",
                headers=headers,
                json={"new_password": new_password}
            )
            response.raise_for_status()
            return response.json()

    async def get_proxy_status(self, access_token: str) -> dict:
        """Get proxy server statuses"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/proxies/status",
                headers=headers
            )
            response.raise_for_status()
            return response.json()

    async def get_certificates_list(self, access_token: str) -> list:
        """Get all client certificates"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/certificates/list",
                headers=headers
            )
            response.raise_for_status()
            return response.json()

    async def get_expiring_certificates(self, access_token: str, days: int = 30) -> list:
        """Get expiring certificates"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/certificates/expiring",
                headers=headers,
                params={"days": days}
            )
            response.raise_for_status()
            return response.json()

    async def run_data_cleanup(self, access_token: str, retention_days: int = 180) -> dict:
        """Run data retention cleanup"""
        headers = {"Authorization": f"Bearer {access_token}"}
        
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/admin/data-retention/cleanup",
                headers=headers,
                params={"retention_days": retention_days}
            )
            response.raise_for_status()
            return response.json()

    async def forgot_password(self, email: str) -> dict:
        """Initiate password reset"""
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/portal/auth/forgot-password",
                json={"email": email}
            )
            response.raise_for_status()
            return response.json()

    async def reset_password(self, token: str, new_password: str) -> dict:
        """Reset password using token"""
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/portal/auth/reset-password",
                json={"token": token, "new_password": new_password}
            )
            response.raise_for_status()
            return response.json()

    async def get_db_status(self, access_token: str) -> dict:
        """Get database status (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/db/status",
                headers=headers
            )
            response.raise_for_status()
            return response.json()

    async def trigger_backup(self, access_token: str) -> dict:
        """Trigger manual backup (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/admin/db/backup",
                headers=headers
            )
            response.raise_for_status()
            return response.json()

    async def get_backups(self, access_token: str) -> list:
        """List available backups (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/db/backups",
                headers=headers
            )
            response.raise_for_status()
            return response.json()

    async def get_tls_status(self, access_token: str) -> dict:
        """Get TLS status (admin only)"""
        headers = {"Authorization": f"Bearer {access_token}"}
        async with httpx.AsyncClient(verify=self.verify_ssl, timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/admin/tls/status",
                headers=headers
            )
            response.raise_for_status()
            return response.json()

# Global API client
api_client = MainServerClient()

# ============================================================================
# Authentication Dependencies
# ============================================================================

async def get_current_user(request: Request) -> Optional[dict]:
    """Get current user from session"""
    user_data = request.session.get("user")
    access_token = request.session.get("access_token")
    
    if not user_data or not access_token:
        return None
    
    # Check if token needs refresh
    expires_at = request.session.get("expires_at")
    if expires_at and datetime.fromisoformat(expires_at) < datetime.utcnow():
        # Try to refresh token
        refresh_token = request.session.get("refresh_token")
        if refresh_token:
            try:
                result = await api_client.refresh_token(refresh_token)
                request.session["access_token"] = result["access_token"]
                request.session["expires_at"] = (
                    datetime.utcnow() + timedelta(seconds=result["expires_in"])
                ).isoformat()
            except Exception as e:
                logger.warning(f"Failed to refresh token: {e}")
                return None
    
    return user_data

async def require_auth(request: Request) -> dict:
    """Require authenticated user"""
    user = await get_current_user(request)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated"
        )
    return user

async def require_admin(request: Request) -> dict:
    """Require admin or user_manager user"""
    user = await require_auth(request)
    if user.get("role") not in ["admin", "user_manager"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return user

# ============================================================================
# Routes - Public
# ============================================================================

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Home page"""
    user = await get_current_user(request)
    if user:
        # Redirect to dashboard if authenticated
        if user.get("role") in ["admin", "user_manager"]:
            return RedirectResponse(url="/admin/dashboard", status_code=302)
        return RedirectResponse(url="/dashboard", status_code=302)
    
    return templates.TemplateResponse(
        "index.html",
        {"request": request}
    )

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """Login page"""
    user = await get_current_user(request)
    if user:
        return RedirectResponse(url="/dashboard", status_code=302)
    
    error = request.session.pop("error", None)
    return templates.TemplateResponse(
        "login.html",
        {"request": request, "error": error}
    )

@app.post("/login")
async def login(
    request: Request,
    email: str = Form(...),
    password: str = Form(...)
):
    """Process login"""
    try:
        result = await api_client.login(email, password)
        
        # Store in session
        request.session["user"] = result["user"]
        request.session["access_token"] = result["access_token"]
        request.session["refresh_token"] = result["refresh_token"]
        request.session["expires_at"] = (
            datetime.utcnow() + timedelta(seconds=result["expires_in"])
        ).isoformat()
        
        logger.info(f"User logged in: {email}")
        
        # Redirect to appropriate dashboard
        if result["user"].get("role") in ["admin", "user_manager"]:
            return RedirectResponse(url="/admin/dashboard", status_code=302)
        return RedirectResponse(url="/dashboard", status_code=302)
        
    except httpx.HTTPStatusError as e:
        logger.warning(f"Login failed for {email}: {e}")
        request.session["error"] = "Invalid email or password"
        return RedirectResponse(url="/login", status_code=302)
    except Exception as e:
        logger.error(f"Login error: {e}")
        request.session["error"] = "Login failed. Please try again."
        return RedirectResponse(url="/login", status_code=302)

@app.get("/logout")
async def logout(request: Request):
    """Logout"""
    request.session.clear()
    return RedirectResponse(url="/login", status_code=302)


@app.get("/forgot-password", response_class=HTMLResponse)
async def forgot_password_page(request: Request):
    """Forgot password page"""
    return templates.TemplateResponse(
        "auth/forgot_password.html",
        {"request": request}
    )


@app.post("/forgot-password")
async def process_forgot_password(
    request: Request,
    email: str = Form(...),
):
    """Process forgot password request"""
    try:
        await api_client.forgot_password(email)
        return templates.TemplateResponse(
            "auth/forgot_password.html",
            {
                "request": request,
                "success": "If your email is registered, you will receive a reset link shortly."
            }
        )
    except Exception as e:
        logger.error(f"Forgot password error: {e}")
        return templates.TemplateResponse(
            "auth/forgot_password.html",
            {
                "request": request,
                "error": "An error occurred. Please try again later."
            }
        )


@app.get("/reset-password", response_class=HTMLResponse)
async def reset_password_page(
    request: Request,
    token: str = Query(...)
):
    """Reset password page"""
    return templates.TemplateResponse(
        "auth/reset_password.html",
        {"request": request, "token": token}
    )


@app.post("/reset-password")
async def process_reset_password(
    request: Request,
    token: str = Form(...),
    password: str = Form(...)
):
    """Process password reset"""
    try:
        await api_client.reset_password(token, password)
        return templates.TemplateResponse(
            "auth/reset_password.html",
            {
                "request": request,
                "success": "Your password has been successfully reset. You can now login.",
                "token": token
            }
        )
    except httpx.HTTPStatusError as e:
        logger.warning(f"Reset password failed: {e}")
        return templates.TemplateResponse(
            "auth/reset_password.html",
            {
                "request": request,
                "error": "Invalid or expired reset token.",
                "token": token
            }
        )
    except Exception as e:
        logger.error(f"Reset password error: {e}")
        return templates.TemplateResponse(
            "auth/reset_password.html",
            {
                "request": request,
                "error": "An error occurred. Please try again later.",
                "token": token
            }
        )

# ============================================================================
# Routes - User Dashboard
# ============================================================================

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(
    request: Request,
    page: int = 1,
    status_filter: Optional[str] = None,
    user: dict = Depends(require_auth)
):
    """User dashboard"""
    try:
        access_token = request.session.get("access_token")
        skip = (page - 1) * config.MESSAGES_PER_PAGE
        
        messages = await api_client.get_messages(
            access_token,
            skip=skip,
            limit=config.MESSAGES_PER_PAGE,
            status_filter=status_filter
        )
        
        return templates.TemplateResponse(
            "dashboard.html",
            {
                "request": request,
                "user": user,
                "messages": messages,
                "page": page,
                "status_filter": status_filter or "",
                "per_page": config.MESSAGES_PER_PAGE,
            }
        )
    except Exception as e:
        logger.error(f"Dashboard error: {e}")
        request.session["error"] = "Failed to load messages"
        return RedirectResponse(url="/login", status_code=302)

@app.get("/profile", response_class=HTMLResponse)
async def profile(request: Request, user: dict = Depends(require_auth)):
    """User profile"""
    try:
        access_token = request.session.get("access_token")
        profile_data = await api_client.get_profile(access_token)
        
        return templates.TemplateResponse(
            "profile.html",
            {
                "request": request,
                "user": user,
                "profile": profile_data,
            }
        )
    except Exception as e:
        logger.error(f"Profile error: {e}")
        request.session["error"] = "Failed to load profile"
        return RedirectResponse(url="/dashboard", status_code=302)

# ============================================================================
# Routes - Admin Dashboard
# ============================================================================

@app.get("/admin/dashboard", response_class=HTMLResponse)
async def admin_dashboard(request: Request, user: dict = Depends(require_admin)):
    """Admin dashboard with system statistics"""
    try:
        access_token = request.session.get("access_token")
        stats = await api_client.get_stats(access_token)
        
        return templates.TemplateResponse(
            "admin/dashboard.html",
            {
                "request": request,
                "user": user,
                "stats": stats,
            }
        )
    except Exception as e:
        logger.error(f"Admin dashboard error: {e}")
        request.session["error"] = "Failed to load statistics"
        return RedirectResponse(url="/dashboard", status_code=302)

@app.get("/admin/users", response_class=HTMLResponse)
async def admin_users(request: Request, user: dict = Depends(require_admin)):
    """Admin user management"""
    try:
        access_token = request.session.get("access_token")
        users = await api_client.get_users(access_token)
        
        success = request.session.pop("success", None)
        error = request.session.pop("error", None)
        
        return templates.TemplateResponse(
            "admin/users.html",
            {
                "request": request,
                "user": user,
                "users": users,
                "success": success,
                "error": error,
            }
        )
    except Exception as e:
        logger.error(f"Admin users error: {e}")
        request.session["error"] = "Failed to load users"
        return RedirectResponse(url="/admin/dashboard", status_code=302)

@app.post("/admin/users/create")
async def admin_create_user(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    role: str = Form(...),
    user: dict = Depends(require_admin)
):
    """Create new user"""
    try:
        access_token = request.session.get("access_token")
        await api_client.create_user(access_token, email, password, role)
        
        logger.info(f"User created: {email} by {user['email']}")
        request.session["success"] = f"User {email} created successfully"
        return RedirectResponse(url="/admin/users", status_code=302)
        
    except Exception as e:
        logger.error(f"Create user error: {e}")
        request.session["error"] = f"Failed to create user: {str(e)}"
        return RedirectResponse(url="/admin/users", status_code=302)

@app.post("/admin/users/{user_id}/role")
async def admin_update_user_role(
    user_id: int,
    request: Request,
    role: str = Form(...),
    user: dict = Depends(require_admin)
):
    """Update user role"""
    try:
        access_token = request.session.get("access_token")
        await api_client.update_user_role(access_token, user_id, role)
        
        logger.info(f"User role updated for ID {user_id} to {role} by {user['email']}")
        request.session["success"] = "User role updated successfully"
        return RedirectResponse(url="/admin/users", status_code=302)
        
    except httpx.HTTPStatusError as e:
        error_msg = e.response.json().get("detail", str(e))
        logger.error(f"Update user role HTTP error: {error_msg}")
        request.session["error"] = f"Failed to update user role: {error_msg}"
        return RedirectResponse(url="/admin/users", status_code=302)
    except Exception as e:
        logger.error(f"Update user role error: {e}")
        request.session["error"] = f"Failed to update user role: {str(e)}"
        return RedirectResponse(url="/admin/users", status_code=302)

@app.get("/admin/certificates", response_class=HTMLResponse)
async def admin_certificates(request: Request, user: dict = Depends(require_admin)):
    """Admin certificate management"""
    success = request.session.pop("success", None)
    error = request.session.pop("error", None)
    
    # Load certificate list and expiring certs
    access_token = request.session.get("access_token")
    certificates = []
    expiring = []
    try:
        certificates = await api_client.get_certificates_list(access_token)
        expiring = await api_client.get_expiring_certificates(access_token)
    except Exception as e:
        logger.warning(f"Could not load certificates: {e}")
    
    return templates.TemplateResponse(
        "admin/certificates.html",
        {
            "request": request,
            "user": user,
            "certificates": certificates,
            "expiring": expiring,
            "success": success,
            "error": error,
        }
    )

@app.post("/admin/certificates/generate")
async def admin_generate_cert(
    request: Request,
    client_id: str = Form(...),
    domain: str = Form(""),
    validity_days: int = Form(365),
    user: dict = Depends(require_admin)
):
    """Generate client certificate"""
    try:
        access_token = request.session.get("access_token")
        result = await api_client.generate_certificate(
            access_token,
            client_id,
            domain if domain else None,
            validity_days
        )
        
        logger.info(f"Certificate generated: {client_id} by {user['email']}")
        request.session["success"] = f"Certificate for {client_id} generated successfully"
        return RedirectResponse(url="/admin/certificates", status_code=302)
        
    except Exception as e:
        logger.error(f"Generate certificate error: {e}")
        request.session["error"] = f"Failed to generate certificate: {str(e)}"
        return RedirectResponse(url="/admin/certificates", status_code=302)

@app.post("/admin/certificates/revoke")
async def admin_revoke_cert(
    request: Request,
    client_id: str = Form(...),
    reason: str = Form(...),
    user: dict = Depends(require_admin)
):
    """Revoke client certificate"""
    try:
        access_token = request.session.get("access_token")
        await api_client.revoke_certificate(access_token, client_id, reason)
        
        logger.info(f"Certificate revoked: {client_id} by {user['email']}")
        request.session["success"] = f"Certificate for {client_id} revoked successfully"
        return RedirectResponse(url="/admin/certificates", status_code=302)
        
    except Exception as e:
        logger.error(f"Revoke certificate error: {e}")
        request.session["error"] = f"Failed to revoke certificate: {str(e)}"
        return RedirectResponse(url="/admin/certificates", status_code=302)

@app.get("/admin/messages", response_class=HTMLResponse)
async def admin_messages(
    request: Request,
    page: int = 1,
    status_filter: Optional[str] = None,
    user: dict = Depends(require_admin)
):
    """Admin message viewing (all messages)"""
    try:
        access_token = request.session.get("access_token")
        skip = (page - 1) * config.MESSAGES_PER_PAGE
        
        messages = await api_client.get_messages(
            access_token,
            skip=skip,
            limit=config.MESSAGES_PER_PAGE,
            status_filter=status_filter
        )
        
        return templates.TemplateResponse(
            "admin/messages.html",
            {
                "request": request,
                "user": user,
                "messages": messages,
                "page": page,
                "status_filter": status_filter or "",
                "per_page": config.MESSAGES_PER_PAGE,
            }
        )
    except Exception as e:
        logger.error(f"Admin messages error: {e}")
        request.session["error"] = "Failed to load messages"
        return RedirectResponse(url="/admin/dashboard", status_code=302)

@app.get("/admin/database", response_class=HTMLResponse)
async def admin_database(request: Request, user: dict = Depends(require_admin)):
    """Database and system status page"""
    try:
        access_token = request.session.get("access_token")
        db_status = await api_client.get_db_status(access_token)
        tls_status = await api_client.get_tls_status(access_token)
        
        return templates.TemplateResponse(
            "admin/database.html",
            {
                "request": request,
                "user": user,
                "db_status": db_status,
                "tls_status": tls_status
            }
        )
    except Exception as e:
        logger.error(f"Database status error: {e}")
        request.session["error"] = "Failed to load database status"
        return RedirectResponse(url="/admin/dashboard", status_code=302)


@app.get("/admin/backups", response_class=HTMLResponse)
async def admin_backups(request: Request, user: dict = Depends(require_admin)):
    """Backup management page"""
    try:
        access_token = request.session.get("access_token")
        backups = await api_client.get_backups(access_token)
        
        success = request.session.pop("success", None)
        error = request.session.pop("error", None)
        
        return templates.TemplateResponse(
            "admin/backups.html",
            {
                "request": request,
                "user": user,
                "backups": backups,
                "success": success,
                "error": error
            }
        )
    except Exception as e:
        logger.error(f"Backups list error: {e}")
        request.session["error"] = "Failed to load backups"
        return RedirectResponse(url="/admin/dashboard", status_code=302)


@app.post("/admin/db/backup")
async def admin_trigger_backup(request: Request, user: dict = Depends(require_admin)):
    """Trigger manual backup"""
    try:
        access_token = request.session.get("access_token")
        await api_client.trigger_backup(access_token)
        
        request.session["success"] = "Backup process started in background."
        return RedirectResponse(url="/admin/backups", status_code=302)
    except Exception as e:
        logger.error(f"Trigger backup error: {e}")
        request.session["error"] = f"Failed to start backup: {str(e)}"
        return RedirectResponse(url="/admin/backups", status_code=302)

# ============================================================================
# Routes - Admin User Status & Password
# ============================================================================

@app.post("/admin/users/{user_id}/status")
async def admin_toggle_user_status(
    user_id: int,
    request: Request,
    is_active: str = Form(...),
    user: dict = Depends(require_admin)
):
    """Toggle user active status"""
    try:
        access_token = request.session.get("access_token")
        active = is_active.lower() == "true"
        await api_client.toggle_user_status(access_token, user_id, active)
        action = "activated" if active else "deactivated"
        logger.info(f"User {user_id} {action} by {user['email']}")
        request.session["success"] = f"User {action} successfully"
        return RedirectResponse(url="/admin/users", status_code=302)
    except Exception as e:
        logger.error(f"Toggle user status error: {e}")
        request.session["error"] = f"Failed to update user status: {str(e)}"
        return RedirectResponse(url="/admin/users", status_code=302)

@app.post("/admin/users/{user_id}/password")
async def admin_change_user_password(
    user_id: int,
    request: Request,
    new_password: str = Form(...),
    user: dict = Depends(require_admin)
):
    """Change user password"""
    try:
        access_token = request.session.get("access_token")
        await api_client.change_user_password(access_token, user_id, new_password)
        logger.info(f"Password changed for user {user_id} by {user['email']}")
        request.session["success"] = "Password changed successfully"
        return RedirectResponse(url="/admin/users", status_code=302)
    except Exception as e:
        logger.error(f"Change password error: {e}")
        request.session["error"] = f"Failed to change password: {str(e)}"
        return RedirectResponse(url="/admin/users", status_code=302)

# ============================================================================
# Routes - Proxy Status
# ============================================================================

@app.get("/admin/proxies", response_class=HTMLResponse)
async def admin_proxies(request: Request, user: dict = Depends(require_admin)):
    """Proxy status monitoring page"""
    try:
        access_token = request.session.get("access_token")
        proxy_data = await api_client.get_proxy_status(access_token)
        return templates.TemplateResponse(
            "admin/proxies.html",
            {"request": request, "user": user,
             "proxies": proxy_data.get("proxies", [])}
        )
    except Exception as e:
        logger.error(f"Proxy status error: {e}")
        request.session["error"] = "Failed to load proxy status"
        return RedirectResponse(url="/admin/dashboard", status_code=302)

# ============================================================================
# Routes - Data Retention
# ============================================================================

@app.get("/admin/data-retention", response_class=HTMLResponse)
async def admin_data_retention(request: Request, user: dict = Depends(require_admin)):
    """Data retention management page"""
    success = request.session.pop("success", None)
    error = request.session.pop("error", None)
    return templates.TemplateResponse(
        "admin/data_retention.html",
        {"request": request, "user": user,
         "success": success, "error": error}
    )

@app.post("/admin/data-retention/cleanup")
async def admin_run_cleanup(
    request: Request,
    retention_days: int = Form(180),
    user: dict = Depends(require_admin)
):
    """Run data cleanup"""
    try:
        access_token = request.session.get("access_token")
        result = await api_client.run_data_cleanup(access_token, retention_days)
        deleted = result.get("deleted_count", 0)
        logger.info(f"Data cleanup: {deleted} messages deleted by {user['email']}")
        request.session["success"] = f"Cleanup complete: {deleted} messages deleted (older than {retention_days} days)"
        return RedirectResponse(url="/admin/data-retention", status_code=302)
    except Exception as e:
        logger.error(f"Data cleanup error: {e}")
        request.session["error"] = f"Cleanup failed: {str(e)}"
        return RedirectResponse(url="/admin/data-retention", status_code=302)

# ============================================================================
# Health Check
# ============================================================================

@app.get("/health")
async def health():
    """Health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "portal"
    }

# ============================================================================
# Error Handlers
# ============================================================================

@app.exception_handler(404)
async def not_found_handler(request: Request, exc):
    """Handle 404 errors"""
    user = await get_current_user(request)
    return templates.TemplateResponse(
        "404.html",
        {"request": request, "user": user},
        status_code=404
    )

@app.exception_handler(500)
async def server_error_handler(request: Request, exc):
    """Handle 500 errors"""
    logger.error(f"Server error: {exc}")
    user = await get_current_user(request)
    return templates.TemplateResponse(
        "500.html",
        {"request": request, "user": user},
        status_code=500
    )

# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    
    logger.info(f"Starting Portal on {config.PORTAL_HOST}:{config.PORTAL_PORT}")
    
    uvicorn.run(
        app,
        host=config.PORTAL_HOST,
        port=config.PORTAL_PORT,
        log_level=config.LOG_LEVEL.lower(),
    )

