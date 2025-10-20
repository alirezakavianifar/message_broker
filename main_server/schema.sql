-- ============================================================================
-- Message Broker System - MySQL Database Schema
-- Version: 1.0.0
-- Description: Minimal, privacy-oriented database schema
-- ============================================================================

-- Drop existing tables (for clean reinstall)
-- WARNING: This will delete all data!
DROP TABLE IF EXISTS `messages`;
DROP TABLE IF EXISTS `clients`;
DROP TABLE IF EXISTS `users`;
DROP TABLE IF EXISTS `audit_log`;
DROP TABLE IF EXISTS `alembic_version`;

-- ============================================================================
-- Table: users
-- Description: Portal users (admin and regular users)
-- ============================================================================

CREATE TABLE `users` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(255) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL COMMENT 'bcrypt hashed password',
  `role` ENUM('user', 'admin') NOT NULL DEFAULT 'user',
  `client_id` VARCHAR(255) NULL COMMENT 'Associated client for regular users',
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
  `last_login` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_email` (`email`),
  KEY `idx_client_id` (`client_id`),
  KEY `idx_role` (`role`),
  KEY `idx_is_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Portal users with role-based access';

-- ============================================================================
-- Table: clients
-- Description: Client certificate information
-- ============================================================================

CREATE TABLE `clients` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `client_id` VARCHAR(255) NOT NULL COMMENT 'Unique client identifier (CN from cert)',
  `cert_fingerprint` VARCHAR(255) NOT NULL COMMENT 'SHA-256 fingerprint of certificate',
  `domain` VARCHAR(255) NOT NULL DEFAULT 'default',
  `status` ENUM('active', 'revoked', 'expired') NOT NULL DEFAULT 'active',
  `issued_at` DATETIME NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `revoked_at` DATETIME NULL,
  `revocation_reason` VARCHAR(500) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_client_id` (`client_id`),
  UNIQUE KEY `idx_cert_fingerprint` (`cert_fingerprint`),
  KEY `idx_domain` (`domain`),
  KEY `idx_status` (`status`),
  KEY `idx_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Client certificates and their status';

-- ============================================================================
-- Table: messages
-- Description: Message storage with encryption and privacy
-- ============================================================================

CREATE TABLE `messages` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` VARCHAR(36) NOT NULL COMMENT 'UUID v4',
  `client_id` VARCHAR(255) NOT NULL COMMENT 'Client who submitted the message',
  `sender_number_hashed` VARCHAR(64) NOT NULL COMMENT 'SHA-256 hash of sender phone number',
  `encrypted_body` TEXT NOT NULL COMMENT 'AES-256 encrypted message body (base64)',
  `encryption_key_version` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'Key version for rotation support',
  `status` ENUM('queued', 'processing', 'delivered', 'failed') NOT NULL DEFAULT 'queued',
  `domain` VARCHAR(255) NOT NULL DEFAULT 'default',
  `attempt_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `error_message` VARCHAR(500) NULL COMMENT 'Last error message (if failed)',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Message creation time',
  `queued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Queue insertion time',
  `delivered_at` DATETIME NULL COMMENT 'Successful delivery time',
  `last_attempt_at` DATETIME NULL COMMENT 'Most recent delivery attempt',
  
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_message_id` (`message_id`),
  KEY `idx_client_id` (`client_id`),
  KEY `idx_sender_hash` (`sender_number_hashed`),
  KEY `idx_status` (`status`),
  KEY `idx_domain` (`domain`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_delivered_at` (`delivered_at`),
  KEY `idx_composite_status_created` (`status`, `created_at`),
  KEY `idx_composite_client_created` (`client_id`, `created_at`),
  
  CONSTRAINT `fk_messages_client` 
    FOREIGN KEY (`client_id`) 
    REFERENCES `clients` (`client_id`)
    ON DELETE RESTRICT 
    ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Encrypted message storage with privacy protection';

-- ============================================================================
-- Table: audit_log
-- Description: Audit trail for security-sensitive operations
-- ============================================================================

CREATE TABLE `audit_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_type` VARCHAR(50) NOT NULL COMMENT 'Type of event (login, cert_issue, cert_revoke, etc.)',
  `user_id` INT UNSIGNED NULL COMMENT 'User who performed the action',
  `client_id` VARCHAR(255) NULL COMMENT 'Client involved in the action',
  `ip_address` VARCHAR(45) NULL COMMENT 'IPv4 or IPv6 address',
  `event_data` JSON NULL COMMENT 'Additional event details',
  `severity` ENUM('info', 'warning', 'error', 'critical') NOT NULL DEFAULT 'info',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  PRIMARY KEY (`id`),
  KEY `idx_event_type` (`event_type`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_client_id` (`client_id`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_severity` (`severity`),
  
  CONSTRAINT `fk_audit_user` 
    FOREIGN KEY (`user_id`) 
    REFERENCES `users` (`id`)
    ON DELETE SET NULL 
    ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Audit log for security events';

-- ============================================================================
-- Initial Data
-- ============================================================================

-- Create default admin user
-- Password: AdminPass123! (hashed with bcrypt)
-- IMPORTANT: Change this password immediately after first login!
INSERT INTO `users` (`email`, `password_hash`, `role`, `is_active`) VALUES
('admin@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5MQgCLrPEiB7m', 'admin', TRUE);

-- ============================================================================
-- Views (for convenience)
-- ============================================================================

-- View: Active messages summary
CREATE OR REPLACE VIEW `v_active_messages` AS
SELECT 
  m.message_id,
  m.client_id,
  m.status,
  m.domain,
  m.attempt_count,
  m.created_at,
  m.queued_at,
  m.delivered_at,
  TIMESTAMPDIFF(SECOND, m.created_at, IFNULL(m.delivered_at, NOW())) AS age_seconds,
  c.status AS client_status
FROM messages m
INNER JOIN clients c ON m.client_id = c.client_id
WHERE m.status IN ('queued', 'processing')
ORDER BY m.created_at ASC;

-- View: Message statistics by client
CREATE OR REPLACE VIEW `v_client_stats` AS
SELECT 
  c.client_id,
  c.domain,
  c.status AS client_status,
  COUNT(m.id) AS total_messages,
  SUM(CASE WHEN m.status = 'queued' THEN 1 ELSE 0 END) AS queued_count,
  SUM(CASE WHEN m.status = 'delivered' THEN 1 ELSE 0 END) AS delivered_count,
  SUM(CASE WHEN m.status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
  AVG(CASE 
    WHEN m.delivered_at IS NOT NULL 
    THEN TIMESTAMPDIFF(SECOND, m.created_at, m.delivered_at)
    ELSE NULL 
  END) AS avg_delivery_time_seconds,
  MAX(m.created_at) AS last_message_at
FROM clients c
LEFT JOIN messages m ON c.client_id = m.client_id
GROUP BY c.client_id, c.domain, c.status;

-- View: Daily message statistics
CREATE OR REPLACE VIEW `v_daily_stats` AS
SELECT 
  DATE(created_at) AS date,
  domain,
  COUNT(*) AS total_messages,
  SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered_count,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
  AVG(CASE 
    WHEN delivered_at IS NOT NULL 
    THEN TIMESTAMPDIFF(SECOND, created_at, delivered_at)
    ELSE NULL 
  END) AS avg_delivery_time_seconds,
  AVG(attempt_count) AS avg_attempts
FROM messages
GROUP BY DATE(created_at), domain
ORDER BY date DESC, domain;

-- ============================================================================
-- Stored Procedures
-- ============================================================================

DELIMITER //

-- Procedure: Get message statistics for a time period
CREATE PROCEDURE `sp_get_stats`(
  IN p_period VARCHAR(10), -- 'hour', 'day', 'week', 'month'
  IN p_domain VARCHAR(255)
)
BEGIN
  DECLARE v_since DATETIME;
  
  -- Calculate time period
  CASE p_period
    WHEN 'hour' THEN SET v_since = DATE_SUB(NOW(), INTERVAL 1 HOUR);
    WHEN 'day' THEN SET v_since = DATE_SUB(NOW(), INTERVAL 1 DAY);
    WHEN 'week' THEN SET v_since = DATE_SUB(NOW(), INTERVAL 1 WEEK);
    WHEN 'month' THEN SET v_since = DATE_SUB(NOW(), INTERVAL 1 MONTH);
    ELSE SET v_since = DATE_SUB(NOW(), INTERVAL 1 DAY);
  END CASE;
  
  -- Return statistics
  SELECT 
    COUNT(*) AS total_messages,
    SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued,
    SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
    AVG(CASE 
      WHEN delivered_at IS NOT NULL 
      THEN TIMESTAMPDIFF(SECOND, created_at, delivered_at)
      ELSE NULL 
    END) AS avg_delivery_time_seconds,
    ROUND(
      100.0 * SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) / COUNT(*),
      2
    ) AS success_rate_percent
  FROM messages
  WHERE created_at >= v_since
    AND (p_domain IS NULL OR domain = p_domain);
END //

-- Procedure: Clean up old messages (for data retention)
CREATE PROCEDURE `sp_cleanup_old_messages`(
  IN p_retention_days INT
)
BEGIN
  DECLARE v_cutoff_date DATETIME;
  DECLARE v_deleted_count INT;
  
  SET v_cutoff_date = DATE_SUB(NOW(), INTERVAL p_retention_days DAY);
  
  DELETE FROM messages
  WHERE delivered_at < v_cutoff_date
    OR (status = 'failed' AND created_at < v_cutoff_date);
  
  SET v_deleted_count = ROW_COUNT();
  
  SELECT v_deleted_count AS deleted_count, v_cutoff_date AS cutoff_date;
END //

-- Procedure: Update message status
CREATE PROCEDURE `sp_update_message_status`(
  IN p_message_id VARCHAR(36),
  IN p_status VARCHAR(20),
  IN p_error_message VARCHAR(500)
)
BEGIN
  UPDATE messages
  SET 
    status = p_status,
    attempt_count = attempt_count + 1,
    error_message = p_error_message,
    last_attempt_at = NOW(),
    delivered_at = CASE WHEN p_status = 'delivered' THEN NOW() ELSE delivered_at END
  WHERE message_id = p_message_id;
  
  SELECT ROW_COUNT() AS updated;
END //

DELIMITER ;

-- ============================================================================
-- Triggers
-- ============================================================================

DELIMITER //

-- Trigger: Log user login
CREATE TRIGGER `trg_user_login_audit`
AFTER UPDATE ON `users`
FOR EACH ROW
BEGIN
  IF NEW.last_login != OLD.last_login THEN
    INSERT INTO audit_log (event_type, user_id, severity)
    VALUES ('user_login', NEW.id, 'info');
  END IF;
END //

-- Trigger: Log certificate revocation
CREATE TRIGGER `trg_cert_revoke_audit`
AFTER UPDATE ON `clients`
FOR EACH ROW
BEGIN
  IF NEW.status = 'revoked' AND OLD.status != 'revoked' THEN
    INSERT INTO audit_log (event_type, client_id, event_data, severity)
    VALUES (
      'cert_revoked', 
      NEW.client_id,
      JSON_OBJECT('reason', NEW.revocation_reason),
      'warning'
    );
  END IF;
END //

DELIMITER ;

-- ============================================================================
-- Indexes for Performance
-- ============================================================================

-- Additional covering indexes for common queries
CREATE INDEX `idx_messages_portal_query` ON `messages` (`client_id`, `status`, `created_at`);
CREATE INDEX `idx_messages_worker_query` ON `messages` (`status`, `attempt_count`, `queued_at`);

-- ============================================================================
-- Grants (Application User)
-- ============================================================================

-- Create application user if it doesn't exist
-- Password should be set via environment variable
CREATE USER IF NOT EXISTS 'systemuser'@'localhost' IDENTIFIED BY 'CHANGE_THIS_PASSWORD';

-- Grant necessary privileges
GRANT SELECT, INSERT, UPDATE ON message_system.messages TO 'systemuser'@'localhost';
GRANT SELECT, INSERT, UPDATE ON message_system.clients TO 'systemuser'@'localhost';
GRANT SELECT, INSERT, UPDATE ON message_system.users TO 'systemuser'@'localhost';
GRANT SELECT, INSERT ON message_system.audit_log TO 'systemuser'@'localhost';
GRANT SELECT ON message_system.v_active_messages TO 'systemuser'@'localhost';
GRANT SELECT ON message_system.v_client_stats TO 'systemuser'@'localhost';
GRANT SELECT ON message_system.v_daily_stats TO 'systemuser'@'localhost';
GRANT EXECUTE ON PROCEDURE message_system.sp_get_stats TO 'systemuser'@'localhost';
GRANT EXECUTE ON PROCEDURE message_system.sp_update_message_status TO 'systemuser'@'localhost';

FLUSH PRIVILEGES;

-- ============================================================================
-- Database Configuration
-- ============================================================================

-- Optimize InnoDB settings for this workload
SET GLOBAL innodb_buffer_pool_size = 1073741824; -- 1GB (adjust based on available RAM)
SET GLOBAL innodb_log_file_size = 268435456; -- 256MB
SET GLOBAL innodb_flush_log_at_trx_commit = 1; -- Full ACID compliance
SET GLOBAL innodb_file_per_table = 1; -- Separate file per table

-- Query cache (if supported)
-- SET GLOBAL query_cache_type = 1;
-- SET GLOBAL query_cache_size = 67108864; -- 64MB

-- ============================================================================
-- Schema Information
-- ============================================================================

SELECT 
  'Schema created successfully!' AS status,
  VERSION() AS mysql_version,
  @@character_set_database AS charset,
  @@collation_database AS collation,
  NOW() AS created_at;

-- Show table information
SELECT 
  TABLE_NAME,
  TABLE_ROWS,
  AVG_ROW_LENGTH,
  DATA_LENGTH,
  INDEX_LENGTH,
  CREATE_TIME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'message_system'
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

