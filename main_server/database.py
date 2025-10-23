"""
Database connection and session management.

This module provides database connectivity using SQLAlchemy with
connection pooling, retry logic, and proper session management.
"""

import logging
from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine, event, pool, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import QueuePool

from main_server.models import Base

logger = logging.getLogger(__name__)


class DatabaseManager:
    """
    Database connection manager with connection pooling.
    
    Handles database connections, session lifecycle, and provides
    health checks and connection pool statistics.
    """
    
    def __init__(
        self,
        database_url: str,
        pool_size: int = 10,
        max_overflow: int = 20,
        pool_timeout: int = 30,
        pool_recycle: int = 3600,
        echo: bool = False,
    ):
        """
        Initialize database manager.
        
        Args:
            database_url: SQLAlchemy database URL
            pool_size: Size of connection pool
            max_overflow: Max connections beyond pool_size
            pool_timeout: Timeout for getting connection from pool (seconds)
            pool_recycle: Recycle connections after this time (seconds)
            echo: Enable SQL query logging
        """
        self.database_url = database_url
        self.engine: Engine = None
        self.SessionLocal: sessionmaker = None
        
        # Connection pool configuration
        self.pool_config = {
            "poolclass": QueuePool,
            "pool_size": pool_size,
            "max_overflow": max_overflow,
            "pool_timeout": pool_timeout,
            "pool_recycle": pool_recycle,
            "pool_pre_ping": True,  # Verify connections before using
            "echo": echo,
            "echo_pool": False,
        }
        
        self._initialize_engine()
    
    def _initialize_engine(self):
        """Initialize SQLAlchemy engine with connection pool."""
        try:
            # Create engine with connection pooling
            self.engine = create_engine(
                self.database_url,
                **self.pool_config,
                connect_args={
                    "connect_timeout": 10,
                }
            )
            
            # Register event listeners
            self._register_events()
            
            # Create session factory
            self.SessionLocal = sessionmaker(
                autocommit=False,
                autoflush=False,
                bind=self.engine
            )
            
            logger.info(
                f"Database engine initialized: "
                f"pool_size={self.pool_config['pool_size']}, "
                f"max_overflow={self.pool_config['max_overflow']}"
            )
            
        except Exception as e:
            logger.error(f"Failed to initialize database engine: {e}")
            raise
    
    def _register_events(self):
        """Register SQLAlchemy event listeners."""
        
        @event.listens_for(self.engine, "connect")
        def receive_connect(dbapi_conn, connection_record):
            """Configure connection on connect."""
            # Set connection timeout
            cursor = dbapi_conn.cursor()
            cursor.execute("SET SESSION wait_timeout = 300")
            cursor.execute("SET SESSION interactive_timeout = 300")
            cursor.close()
            logger.debug("Database connection established")
        
        @event.listens_for(self.engine, "checkout")
        def receive_checkout(dbapi_conn, connection_record, connection_proxy):
            """Log connection checkout from pool."""
            logger.debug("Connection checked out from pool")
        
        @event.listens_for(self.engine, "checkin")
        def receive_checkin(dbapi_conn, connection_record):
            """Log connection return to pool."""
            logger.debug("Connection returned to pool")
    
    def create_tables(self):
        """Create all database tables."""
        try:
            Base.metadata.create_all(self.engine)
            logger.info("Database tables created successfully")
        except Exception as e:
            logger.error(f"Failed to create database tables: {e}")
            raise
    
    def drop_tables(self):
        """
        Drop all database tables.
        
        WARNING: This will delete all data!
        """
        try:
            Base.metadata.drop_all(self.engine)
            logger.warning("All database tables dropped")
        except Exception as e:
            logger.error(f"Failed to drop database tables: {e}")
            raise
    
    @contextmanager
    def get_session(self) -> Generator[Session, None, None]:
        """
        Get database session with automatic cleanup.
        
        Usage:
            with db_manager.get_session() as session:
                # Use session
                pass
        
        Yields:
            SQLAlchemy session
        """
        session = self.SessionLocal()
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()
    
    def get_new_session(self) -> Session:
        """
        Get a new database session (manual management).
        
        Note: Caller is responsible for closing the session.
        
        Returns:
            SQLAlchemy session
        """
        return self.SessionLocal()
    
    def health_check(self) -> bool:
        """
        Check database connectivity.
        
        Returns:
            True if database is accessible, False otherwise
        """
        try:
            with self.get_session() as session:
                session.execute(text("SELECT 1"))
            return True
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            return False
    
    def get_pool_stats(self) -> dict:
        """
        Get connection pool statistics.
        
        Returns:
            Dictionary with pool statistics
        """
        pool = self.engine.pool
        return {
            "pool_size": pool.size(),
            "checked_in": pool.checkedin(),
            "checked_out": pool.checkedout(),
            "overflow": pool.overflow(),
            "status": pool.status(),
        }
    
    def dispose(self):
        """Dispose of connection pool and close all connections."""
        if self.engine:
            self.engine.dispose()
            logger.info("Database connection pool disposed")
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.dispose()


# ============================================================================
# Dependency Injection for FastAPI
# ============================================================================

# Global database manager instance (initialized in main)
db_manager: DatabaseManager = None


def init_db(database_url: str, **kwargs):
    """
    Initialize global database manager.
    
    Args:
        database_url: SQLAlchemy database URL
        **kwargs: Additional arguments for DatabaseManager
    """
    global db_manager
    db_manager = DatabaseManager(database_url, **kwargs)
    logger.info("Database manager initialized")


def get_db() -> Generator[Session, None, None]:
    """
    FastAPI dependency for database session.
    
    Usage in FastAPI:
        @app.get("/items")
        def get_items(db: Session = Depends(get_db)):
            return db.query(Item).all()
    
    Yields:
        Database session
    """
    if not db_manager:
        raise RuntimeError("Database manager not initialized. Call init_db() first.")
    
    with db_manager.get_session() as session:
        yield session


# ============================================================================
# Helper Functions
# ============================================================================

def build_database_url(
    host: str,
    port: int,
    database: str,
    user: str,
    password: str,
    driver: str = "pymysql",
) -> str:
    """
    Build MySQL database URL.
    
    Args:
        host: Database host
        port: Database port
        database: Database name
        user: Database user
        password: Database password
        driver: SQLAlchemy driver (default: pymysql)
    
    Returns:
        SQLAlchemy database URL
    """
    return f"mysql+{driver}://{user}:{password}@{host}:{port}/{database}"


def test_connection(database_url: str) -> bool:
    """
    Test database connection.
    
    Args:
        database_url: SQLAlchemy database URL
    
    Returns:
        True if connection successful, False otherwise
    """
    try:
        engine = create_engine(database_url)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        engine.dispose()
        return True
    except Exception as e:
        logger.error(f"Database connection test failed: {e}")
        return False

