"""Initial database schema

Revision ID: 001
Revises: 
Create Date: 2025-10-20

Creates the initial database schema with tables:
- users: Portal users
- clients: Client certificates
- messages: Message storage with encryption
- audit_log: Security audit trail
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create initial database schema."""
    
    # Create users table
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('password_hash', sa.String(length=255), nullable=False, 
                  comment='bcrypt hashed password'),
        sa.Column('role', sa.Enum('user', 'admin', name='userrole'), 
                  nullable=False, server_default='user'),
        sa.Column('client_id', sa.String(length=255), nullable=True,
                  comment='Associated client for regular users'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('last_login', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, 
                  server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_unicode_ci',
        mysql_engine='InnoDB',
        comment='Portal users with role-based access'
    )
    op.create_index('idx_email', 'users', ['email'], unique=True)
    op.create_index('idx_client_id', 'users', ['client_id'])
    op.create_index('idx_role', 'users', ['role'])
    op.create_index('idx_is_active', 'users', ['is_active'])
    
    # Create clients table
    op.create_table(
        'clients',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('client_id', sa.String(length=255), nullable=False,
                  comment='Unique client identifier (CN from cert)'),
        sa.Column('cert_fingerprint', sa.String(length=255), nullable=False,
                  comment='SHA-256 fingerprint of certificate'),
        sa.Column('domain', sa.String(length=255), nullable=False, 
                  server_default='default'),
        sa.Column('status', sa.Enum('active', 'revoked', 'expired', name='clientstatus'),
                  nullable=False, server_default='active'),
        sa.Column('issued_at', sa.DateTime(), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('revoked_at', sa.DateTime(), nullable=True),
        sa.Column('revocation_reason', sa.String(length=500), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_unicode_ci',
        mysql_engine='InnoDB',
        comment='Client certificates and their status'
    )
    op.create_index('idx_client_id', 'clients', ['client_id'], unique=True)
    op.create_index('idx_cert_fingerprint', 'clients', ['cert_fingerprint'], unique=True)
    op.create_index('idx_domain', 'clients', ['domain'])
    op.create_index('idx_status', 'clients', ['status'])
    op.create_index('idx_expires_at', 'clients', ['expires_at'])
    
    # Create messages table
    op.create_table(
        'messages',
        sa.Column('id', sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column('message_id', sa.String(length=36), nullable=False, comment='UUID v4'),
        sa.Column('client_id', sa.String(length=255), nullable=False,
                  comment='Client who submitted the message'),
        sa.Column('sender_number_hashed', sa.String(length=64), nullable=False,
                  comment='SHA-256 hash of sender phone number'),
        sa.Column('encrypted_body', sa.Text(), nullable=False,
                  comment='AES-256 encrypted message body (base64)'),
        sa.Column('encryption_key_version', sa.SmallInteger(), nullable=False,
                  server_default='1', comment='Key version for rotation support'),
        sa.Column('status', 
                  sa.Enum('queued', 'processing', 'delivered', 'failed', name='messagestatus'),
                  nullable=False, server_default='queued'),
        sa.Column('domain', sa.String(length=255), nullable=False, server_default='default'),
        sa.Column('attempt_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('error_message', sa.String(length=500), nullable=True,
                  comment='Last error message (if failed)'),
        sa.Column('created_at', sa.DateTime(), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP'),
                  comment='Message creation time'),
        sa.Column('queued_at', sa.DateTime(), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP'),
                  comment='Queue insertion time'),
        sa.Column('delivered_at', sa.DateTime(), nullable=True,
                  comment='Successful delivery time'),
        sa.Column('last_attempt_at', sa.DateTime(), nullable=True,
                  comment='Most recent delivery attempt'),
        sa.ForeignKeyConstraint(['client_id'], ['clients.client_id'],
                                ondelete='RESTRICT', onupdate='CASCADE',
                                name='fk_messages_client'),
        sa.PrimaryKeyConstraint('id'),
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_unicode_ci',
        mysql_engine='InnoDB',
        comment='Encrypted message storage with privacy protection'
    )
    op.create_index('idx_message_id', 'messages', ['message_id'], unique=True)
    op.create_index('idx_client_id', 'messages', ['client_id'])
    op.create_index('idx_sender_hash', 'messages', ['sender_number_hashed'])
    op.create_index('idx_status', 'messages', ['status'])
    op.create_index('idx_domain', 'messages', ['domain'])
    op.create_index('idx_created_at', 'messages', ['created_at'])
    op.create_index('idx_delivered_at', 'messages', ['delivered_at'])
    op.create_index('idx_composite_status_created', 'messages', ['status', 'created_at'])
    op.create_index('idx_composite_client_created', 'messages', ['client_id', 'created_at'])
    op.create_index('idx_messages_portal_query', 'messages', 
                    ['client_id', 'status', 'created_at'])
    op.create_index('idx_messages_worker_query', 'messages',
                    ['status', 'attempt_count', 'queued_at'])
    
    # Create audit_log table
    op.create_table(
        'audit_log',
        sa.Column('id', sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column('event_type', sa.String(length=50), nullable=False,
                  comment='Type of event (login, cert_issue, cert_revoke, etc.)'),
        sa.Column('user_id', sa.Integer(), nullable=True,
                  comment='User who performed the action'),
        sa.Column('client_id', sa.String(length=255), nullable=True,
                  comment='Client involved in the action'),
        sa.Column('ip_address', sa.String(length=45), nullable=True,
                  comment='IPv4 or IPv6 address'),
        sa.Column('event_data', sa.JSON(), nullable=True,
                  comment='Additional event details'),
        sa.Column('severity',
                  sa.Enum('info', 'warning', 'error', 'critical', name='auditseverity'),
                  nullable=False, server_default='info'),
        sa.Column('created_at', sa.DateTime(), nullable=False,
                  server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'],
                                ondelete='SET NULL', onupdate='CASCADE',
                                name='fk_audit_user'),
        sa.PrimaryKeyConstraint('id'),
        mysql_charset='utf8mb4',
        mysql_collate='utf8mb4_unicode_ci',
        mysql_engine='InnoDB',
        comment='Audit log for security events'
    )
    op.create_index('idx_event_type', 'audit_log', ['event_type'])
    op.create_index('idx_user_id', 'audit_log', ['user_id'])
    op.create_index('idx_client_id', 'audit_log', ['client_id'])
    op.create_index('idx_created_at', 'audit_log', ['created_at'])
    op.create_index('idx_severity', 'audit_log', ['severity'])
    
    # Insert default admin user
    # Password: AdminPass123! (hashed with bcrypt)
    op.execute(
        """
        INSERT INTO users (email, password_hash, role, is_active)
        VALUES (
            'admin@example.com',
            '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5MQgCLrPEiB7m',
            'admin',
            TRUE
        )
        """
    )


def downgrade() -> None:
    """Drop all tables."""
    op.drop_table('audit_log')
    op.drop_table('messages')
    op.drop_table('clients')
    op.drop_table('users')
    
    # Drop custom enum types
    op.execute("DROP TYPE IF EXISTS auditseverity")
    op.execute("DROP TYPE IF EXISTS messagestatus")
    op.execute("DROP TYPE IF EXISTS clientstatus")
    op.execute("DROP TYPE IF EXISTS userrole")

