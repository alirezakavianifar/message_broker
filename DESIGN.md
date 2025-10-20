# Message Broker System - Design Document

**Version:** 1.0  
**Date:** October 2025  
**Status:** Draft for Review  
**Phase:** Phase 1 - Requirements Consolidation & Design

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture](#system-architecture)
3. [Component Design](#component-design)
4. [Data Flow](#data-flow)
5. [Message Schema](#message-schema)
6. [Authentication & Security](#authentication--security)
7. [Certificate Management](#certificate-management)
8. [Queue & Persistence](#queue--persistence)
9. [Multi-Domain Support](#multi-domain-support)
10. [Technology Stack](#technology-stack)
11. [Scaling Considerations](#scaling-considerations)
12. [Sequence Diagrams](#sequence-diagrams)
13. [Configuration Model](#configuration-model)

---

## 1. Executive Summary

### 1.1 Purpose

This document describes the architecture and design of a secure, scalable message broker system capable of handling up to 100,000 messages per day with the following key features:

- **Mutual TLS Authentication** for all client-to-proxy and proxy-to-server communication
- **Persistent Message Queuing** using Redis with AOF (Append-Only File) persistence
- **Encrypted Storage** of message content using AES-256 encryption
- **Retry Mechanism** with configurable intervals (default: 30 seconds)
- **Web Portal** for message viewing and system administration
- **Multi-Domain Support** with domain-based configuration
- **Real-time Monitoring** via Prometheus and Grafana

### 1.2 Design Goals

1. **Security First**: All communication encrypted, messages stored encrypted, minimal data retention
2. **Reliability**: Guaranteed message delivery with persistent queuing and retry logic
3. **Scalability**: Support for 100k+ messages/day with horizontal worker scaling
4. **Privacy**: Hash phone numbers, encrypt message bodies, minimal logging
5. **Simplicity**: Straightforward deployment without containerization (systemd services)
6. **Observability**: Real-time metrics and monitoring for all components

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────┐
│   Client    │
│  (Python)   │
└──────┬──────┘
       │ Mutual TLS
       │ POST /api/v1/messages
       ▼
┌─────────────────────────────────────────────────────────────┐
│                        Proxy Server                         │
│  - Validate Message (phone format, body length)             │
│  - Extract Client Certificate Fingerprint → client_id       │
│  - Enqueue to Redis                                         │
│  - Call Main Server /register API                           │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
       ┌──────────────┐
       │ Redis Queue  │
       │ (Persistent) │
       └──────┬───────┘
              │
              │ (Multiple Workers, concurrent)
              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Worker Processes                       │
│  - Pop message from queue (atomic)                          │
│  - Attempt delivery to Main Server (Mutual TLS)             │
│  - On success: update status                                │
│  - On failure: retry every 30s                              │
└─────────────┬───────────────────────────────────────────────┘
              │ Mutual TLS
              │ POST /internal/messages/deliver
              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Main Server                            │
│  - Certificate Authority (CA)                               │
│  - Encrypt message body (AES-256)                           │
│  - Hash sender number                                       │
│  - Store in MySQL                                           │
│  - Certificate management endpoints                         │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
       ┌──────────────┐
       │    MySQL     │
       │  (Encrypted) │
       └──────────────┘

              ┌──────────────────────────────────┐
              │        Web Portal                │
              │  - User Panel (view own msgs)    │
              │  - Admin Panel (manage users)    │
              │  - HTTPS + JWT Authentication    │
              └──────────────────────────────────┘
```

### 2.2 Component Interactions

1. **Client → Proxy**: Mutual TLS authenticated POST request with message payload
2. **Proxy → Redis**: Enqueue validated message to persistent queue
3. **Proxy → Main Server**: Register message in database via internal API
4. **Worker → Redis**: Atomic pop from queue for processing
5. **Worker → Main Server**: Deliver message via mutual TLS
6. **Portal → Main Server**: Query messages via JWT-authenticated API
7. **Prometheus → All**: Scrape metrics from all services

---

## 3. Component Design

### 3.1 Proxy Server

**Technology:** FastAPI + Uvicorn  
**Port:** 8001 (HTTPS)  
**Authentication:** Mutual TLS

**Responsibilities:**
- Accept incoming messages from clients
- Validate message format and sender number (E.164 format)
- Extract client certificate fingerprint and map to `client_id`
- Enqueue message to Redis queue
- Call Main Server's `/internal/messages/register` endpoint
- Expose Prometheus metrics
- Health check endpoint

**Key Features:**
- Rate limiting (configurable per client)
- Request validation with Pydantic models
- Certificate-based client identification
- Structured logging (queued time, validation errors)

### 3.2 Main Server

**Technology:** FastAPI + SQLAlchemy + MySQL  
**Port:** 8000 (HTTPS)  
**Authentication:** Mutual TLS (internal), JWT (portal)

**Responsibilities:**
- Certificate Authority (CA) operations
- Message persistence with encryption
- Database management
- Certificate issuance, revocation, and CRL maintenance
- Internal API for proxy and workers
- Public API for portal
- Admin endpoints for system management

**Key Features:**
- AES-256 message encryption at rest
- SHA-256 hashing of phone numbers
- Certificate generation via OpenSSL
- Database migrations with Alembic
- Certificate fingerprint validation

### 3.3 Worker Processes

**Technology:** Python + Redis + HTTPx  
**Port:** 9100 (Prometheus metrics)  
**Authentication:** Mutual TLS (to Main Server)

**Responsibilities:**
- Consume messages from Redis queue atomically
- Deliver messages to Main Server
- Implement retry logic (fixed 30-second interval)
- Update message status in database
- Track attempt counts
- Expose worker metrics

**Key Features:**
- Concurrent processing (configurable worker count)
- Atomic queue operations (Redis BRPOP)
- Graceful shutdown handling
- Exponential backoff option (disabled by default)
- Dead letter queue support (optional)

### 3.4 Web Portal

**Technology:** FastAPI + Jinja2 + Bootstrap  
**Port:** 8080 (HTTPS)  
**Authentication:** Username/Password + JWT

**Responsibilities:**
- User authentication and session management
- Message viewing (users see only their own messages)
- Admin panel for user management
- Search and filter functionality
- Display message status and metadata
- User last login tracking

**Key Features:**
- JWT-based authentication
- Role-based access control (user vs admin)
- Server-side message decryption (with authorization check)
- Search by date range, status, sender number
- Bootstrap-based responsive UI
- No message editing or export (privacy requirement)

### 3.5 Redis Queue

**Technology:** Redis 7.0+  
**Persistence:** AOF (Append-Only File) enabled  
**Data Structure:** List (LPUSH/BRPOP) or Streams

**Configuration:**
```
appendonly yes
appendfsync everysec
maxmemory-policy noeviction
```

**Key Features:**
- Durable message storage
- Atomic operations for concurrent workers
- Fast enqueue/dequeue operations
- Optional Redis Streams for consumer groups

### 3.6 MySQL Database

**Technology:** MySQL 8.0+  
**Charset:** utf8mb4  
**Encryption:** Application-level AES-256

**Key Features:**
- InnoDB storage engine
- ACID compliance
- Binary logging disabled (privacy)
- Minimal data retention
- Encrypted column storage

---

## 4. Data Flow

### 4.1 Message Submission Flow

```
1. Client sends message with certificate
   ↓
2. Proxy validates TLS certificate (mutual TLS handshake)
   ↓
3. Proxy validates message format
   - sender_number: E.164 format (regex: ^\+[1-9]\d{1,14}$)
   - message_body: max 1000 characters
   ↓
4. Proxy extracts certificate fingerprint → client_id
   ↓
5. Proxy enqueues to Redis: LPUSH message_queue <payload>
   ↓
6. Proxy calls Main Server: POST /internal/messages/register
   - Main Server encrypts message body
   - Main Server hashes sender number
   - Main Server stores in MySQL with status='queued'
   ↓
7. Proxy returns success response to client
```

### 4.2 Message Processing Flow

```
1. Worker polls Redis: BRPOP message_queue 5
   ↓
2. Worker retrieves message payload
   ↓
3. Worker calls Main Server: POST /internal/messages/deliver
   - Mutual TLS authentication
   - Includes message_id, client_id, status
   ↓
4. Main Server validates request
   ↓
5. On Success:
   - Update message status='delivered'
   - Set delivered_at timestamp
   - Log delivery
   ↓
6. On Failure:
   - Worker increments attempt_count
   - Worker sleeps 30 seconds
   - Worker re-enqueues message: LPUSH message_queue <payload>
   - Continues until success or max_attempts reached
```

### 4.3 Portal Access Flow

```
1. User visits portal (HTTPS)
   ↓
2. User enters username/password
   ↓
3. Portal validates credentials against MySQL users table
   ↓
4. Portal generates JWT token (30-minute expiry)
   ↓
5. User browses messages:
   - Portal queries Main Server with JWT
   - Main Server validates JWT
   - Main Server checks authorization (user can only see own messages)
   - Main Server decrypts message bodies
   - Returns filtered, decrypted data
   ↓
6. Admin accesses admin panel:
   - Admin role check via JWT claims
   - Access to all messages, user management, system stats
```

---

## 5. Message Schema

### 5.1 Client Submission Format (JSON)

```json
{
  "sender_number": "+1234567890",
  "message_body": "This is the message content",
  "metadata": {
    "client_id": "client_001",
    "timestamp": "2025-10-20T12:34:56.789Z"
  }
}
```

**Field Specifications:**

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `sender_number` | string | Yes | E.164 format: `^\+[1-9]\d{1,14}$` | Phone number with country code |
| `message_body` | string | Yes | Max 1000 chars, non-empty | Message content |
| `metadata.client_id` | string | No | Auto-extracted from cert | Client identifier |
| `metadata.timestamp` | string | No | ISO 8601 format | Submission timestamp |

### 5.2 Redis Queue Format

```json
{
  "message_id": "uuid-v4",
  "sender_number": "+1234567890",
  "message_body": "This is the message content",
  "client_id": "sha256_fingerprint",
  "queued_at": "2025-10-20T12:34:56.789Z",
  "attempt_count": 0,
  "domain": "example.com"
}
```

### 5.3 Database Storage Format (MySQL)

**messages table:**
```sql
{
  "id": 12345,
  "message_id": "uuid-v4",
  "client_id": "sha256_fingerprint",
  "sender_number_hashed": "sha256_hash",
  "encrypted_body": "base64_encrypted_content",
  "status": "queued|delivered|failed",
  "domain": "example.com",
  "created_at": "2025-10-20 12:34:56",
  "queued_at": "2025-10-20 12:34:56",
  "delivered_at": null,
  "attempt_count": 0
}
```

### 5.4 Portal Display Format (Decrypted)

```json
{
  "message_id": "uuid-v4",
  "sender_number_masked": "+123****7890",
  "message_body": "This is the message content",
  "status": "delivered",
  "created_at": "2025-10-20T12:34:56Z",
  "delivered_at": "2025-10-20T12:35:12Z",
  "attempt_count": 1
}
```

---

## 6. Authentication & Security

### 6.1 Authentication Model

#### 6.1.1 Mutual TLS (Client ↔ Proxy ↔ Main Server)

**Used For:**
- Client → Proxy message submission
- Proxy → Main Server internal API calls
- Worker → Main Server message delivery

**Implementation:**
- X.509 certificates issued by internal CA
- Certificate Common Name (CN) mapped to client_id
- Certificate fingerprint (SHA-256) stored in database
- CRL (Certificate Revocation List) checked on each request

**Certificate Validation:**
1. Verify certificate signature against CA
2. Check certificate expiration
3. Verify certificate CN matches expected client
4. Check CRL for revocation
5. Extract fingerprint for client identification

#### 6.1.2 JWT Authentication (Portal)

**Used For:**
- Web portal user authentication
- Admin panel access

**Implementation:**
- HS256 signing algorithm
- 30-minute token expiry
- Refresh token support (optional)
- Role-based claims (user, admin)

**JWT Claims:**
```json
{
  "sub": "user@example.com",
  "role": "admin",
  "client_id": "client_001",
  "exp": 1698765432,
  "iat": 1698763632
}
```

### 6.2 Encryption

#### 6.2.1 Message Body Encryption (AES-256)

**Algorithm:** AES-256-CBC  
**Key Management:** File-based key storage with restricted permissions  
**Implementation:**
```python
from cryptography.fernet import Fernet

# Key generation (one-time)
key = Fernet.generate_key()

# Encryption
cipher = Fernet(key)
encrypted_body = cipher.encrypt(message_body.encode())

# Decryption
decrypted_body = cipher.decrypt(encrypted_body).decode()
```

**Key Storage:**
- Location: `C:\app_secrets\aes.key` (Windows) or `/etc/app_secrets/aes.key` (Linux)
- Permissions: Read-only for application user, no group/world access
- Backup: Encrypted backup stored separately
- Rotation: Manual rotation with re-encryption script

#### 6.2.2 Phone Number Hashing (SHA-256)

**Purpose:** Store searchable phone number reference without storing plaintext

```python
import hashlib

def hash_phone_number(phone: str) -> str:
    """Hash phone number with salt."""
    salt = "system_wide_salt"  # Stored in config
    return hashlib.sha256(f"{salt}{phone}".encode()).hexdigest()
```

### 6.3 Security Features

1. **TLS 1.3** for all HTTPS communication
2. **Certificate pinning** for critical connections
3. **Rate limiting** per client (configurable)
4. **Input validation** on all endpoints
5. **Minimal logging** (no sensitive data in logs)
6. **SQL injection prevention** via parameterized queries
7. **XSS protection** in portal (CSP headers)
8. **CSRF protection** for portal forms

---

## 7. Certificate Management

### 7.1 Certificate Authority (CA)

**Location:** Main Server (`main_server/certs/`)  
**Implementation:** OpenSSL-based

**CA Setup:**
```bash
# Generate CA private key (4096-bit RSA)
openssl genrsa -out ca.key 4096

# Generate self-signed CA certificate (10-year validity)
openssl req -x509 -new -nodes -key ca.key \
  -sha256 -days 3650 -out ca.crt \
  -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"
```

### 7.2 Client Certificate Issuance

**Process:**
1. Admin requests certificate for new client via Main Server endpoint
2. Main Server generates private key and CSR
3. Main Server signs CSR with CA certificate
4. Certificate details stored in database (`clients` table)
5. Certificate and private key returned to admin
6. Admin delivers certificate to client securely

**Automated Script:** `main_server/generate_cert.bat` (Windows) or `.sh` (Linux)

```bash
# Usage: generate_cert.bat <client_name>

# Generate client private key
openssl genrsa -out <client_name>.key 2048

# Generate certificate signing request (CSR)
openssl req -new -key <client_name>.key \
  -out <client_name>.csr \
  -subj "/CN=<client_name>"

# Sign with CA certificate (1-year validity)
openssl x509 -req -in <client_name>.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out <client_name>.crt -days 365 -sha256

# Calculate fingerprint for database
openssl x509 -in <client_name>.crt -noout -fingerprint -sha256
```

### 7.3 Certificate Lifecycle

```
┌─────────────┐
│   Request   │  Admin requests cert via API or CLI
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Generate   │  OpenSSL generates key + CSR + cert
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Issue     │  CA signs cert, store in DB
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Active    │  Client uses cert for auth (365 days)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Renew     │  Re-issue before expiry (optional)
│     or      │  OR
│   Revoke    │  Add to CRL if compromised
└─────────────┘
```

### 7.4 Certificate Revocation

**CRL File:** `main_server/crl/revoked.pem`

**Revocation Process:**
1. Admin calls `/admin/certificates/revoke` endpoint
2. Main Server adds certificate serial to CRL
3. Main Server updates `clients` table (status='revoked')
4. CRL distributed to Proxy and Workers
5. Revoked certificates rejected on next TLS handshake

**Automated Script:** `main_server/revoke_cert.bat`

```bash
# Usage: revoke_cert.bat <client_name>

# Add to CRL
openssl ca -revoke <client_name>.crt \
  -keyfile ca.key -cert ca.crt

# Update CRL file
openssl ca -gencrl -keyfile ca.key -cert ca.crt \
  -out crl/revoked.pem
```

### 7.5 Certificate Renewal

**Default Validity:** 365 days  
**Renewal Window:** 30 days before expiry  
**Process:**
1. Monitor certificate expiry via cron job or scheduled task
2. Admin notified 30 days before expiry
3. Generate new certificate with same CN
4. Distribute new certificate to client
5. Old certificate remains valid until expiry (overlap period)

---

## 8. Queue & Persistence

### 8.1 Redis Configuration

**Persistence Strategy:** AOF (Append-Only File) with `everysec` fsync

```conf
# redis.conf
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Memory management
maxmemory 2gb
maxmemory-policy noeviction

# Durability
save ""  # Disable RDB snapshots (use AOF only)
```

**Queue Operations:**

```python
# Enqueue (Proxy)
redis_client.lpush('message_queue', json.dumps(message))

# Dequeue (Worker, blocking with 5-second timeout)
message = redis_client.brpop('message_queue', timeout=5)

# Queue length (monitoring)
queue_length = redis_client.llen('message_queue')
```

**Alternative: Redis Streams**

For better multi-worker coordination:

```python
# Enqueue
redis_client.xadd('message_stream', {'data': json.dumps(message)})

# Consumer group
redis_client.xgroup_create('message_stream', 'workers', mkstream=True)

# Dequeue
messages = redis_client.xreadgroup('workers', 'worker-1', 
                                   {'message_stream': '>'}, count=1)
```

### 8.2 MySQL Configuration

**Storage Engine:** InnoDB  
**Transaction Isolation:** READ-COMMITTED  
**Character Set:** utf8mb4

```sql
-- MySQL configuration
[mysqld]
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
innodb_file_per_table=1
innodb_flush_log_at_trx_commit=1
max_connections=200
```

**Backup Strategy:**
- Daily automated backups via `infra/backup.ps1`
- 7-day retention
- Backup includes encrypted data (AES key backed up separately)

### 8.3 Persistence Guarantees

| Component | Persistence Level | Recovery Time |
|-----------|------------------|---------------|
| Redis Queue | AOF with everysec fsync | < 1 second data loss max |
| MySQL Database | InnoDB with commit=1 | Zero data loss |
| Message Body | AES-256 encrypted | Requires AES key |
| Certificates | File system + DB | From backup |

---

## 9. Multi-Domain Support

### 9.1 Domain Configuration

**Approach:** Domain-driven configuration using environment variables and database

**Configuration Structure:**

```yaml
# config.yaml
domains:
  - name: "example.com"
    proxy_url: "https://proxy.example.com:8001"
    main_server_url: "https://main.example.com:8000"
    ca_cert: "certs/example_ca.crt"
    
  - name: "another.com"
    proxy_url: "https://proxy.another.com:8001"
    main_server_url: "https://main.another.com:8000"
    ca_cert: "certs/another_ca.crt"
```

### 9.2 Domain Identification

**Method 1: Client Certificate CN**
- Certificate CN includes domain: `client001.example.com`
- Proxy extracts domain from CN
- Domain stored with message in database

**Method 2: HTTP Host Header**
- Client sends request to domain-specific URL
- Proxy extracts domain from Host header
- Validates against configured domains

**Method 3: API Key Prefix**
- Client ID includes domain prefix: `example.com:client001`
- Parsed during authentication

### 9.3 Domain Isolation

**Database:**
- Single database with domain column in tables
- Queries filtered by domain
- Row-level security via client_id

**Certificates:**
- Separate CA per domain (optional)
- Or single CA with domain in certificate attributes

**Portal:**
- Domain-specific login URLs
- Users scoped to single domain
- Admin can view across domains (super-admin role)

### 9.4 Domain-Based Routing

```python
# Pseudo-code for domain routing
def route_by_domain(client_cert):
    domain = extract_domain_from_cert(client_cert)
    config = load_domain_config(domain)
    
    return {
        'redis_queue': f"{config.queue_prefix}:messages",
        'main_server_url': config.main_server_url,
        'db_filter': f"domain = '{domain}'"
    }
```

---

## 10. Technology Stack

### 10.1 Stack Overview

| Layer | Technology | Version | Rationale |
|-------|-----------|---------|-----------|
| **Runtime** | Python | 3.12+ | Modern Python with type hints, asyncio support |
| **Web Framework** | FastAPI | 0.115+ | High performance, auto-docs, async support |
| **ASGI Server** | Uvicorn | 0.30+ | Fast ASGI server with TLS support |
| **Queue** | Redis | 7.0+ | Fast, reliable, AOF persistence, simple operations |
| **Database** | MySQL | 8.0+ | ACID compliance, mature, good performance |
| **ORM** | SQLAlchemy | 2.0+ | Mature ORM with async support |
| **Encryption** | Cryptography | 43+ | Industry-standard Python crypto library |
| **Templates** | Jinja2 | 3.1+ | Flexible templating for portal |
| **Frontend** | Bootstrap | 5.3+ | Responsive UI, well-documented |
| **Monitoring** | Prometheus | 2.x | Industry-standard metrics |
| **Visualization** | Grafana | 10.x | Rich dashboards and alerting |
| **TLS/SSL** | OpenSSL | 3.x | Certificate generation and management |

### 10.2 Technology Rationale

#### FastAPI
- **Pros:** Automatic API documentation, Pydantic validation, async/await support, excellent performance
- **Cons:** Relatively newer framework
- **Choice:** Modern features and performance outweigh maturity concerns

#### Redis (vs RabbitMQ/Kafka)
- **Pros:** Simple operations, excellent performance, AOF persistence adequate for 100k msgs/day, familiar
- **Cons:** Not designed as message queue primarily
- **Choice:** Simplicity and performance for required scale; can migrate to RabbitMQ if needed

#### MySQL (vs PostgreSQL)
- **Pros:** Widely deployed, excellent performance, good tooling, familiar
- **Cons:** Less advanced features than PostgreSQL
- **Choice:** Meets all requirements, simpler deployment on Windows

#### Bootstrap (vs React)
- **Pros:** Simple server-side rendering, no complex build process, fast development
- **Cons:** Less interactive than SPA
- **Choice:** Portal is primarily read-only, server-side rendering sufficient

### 10.3 Development Tools

- **Linting:** flake8, pylint
- **Formatting:** black
- **Type Checking:** mypy
- **Testing:** pytest (manual testing for Phase 8)
- **Migration:** Alembic
- **Documentation:** Swagger/OpenAPI (auto-generated)

---

## 11. Scaling Considerations

### 11.1 Target Capacity

**Daily Volume:** 100,000 messages/day  
**Average Rate:** ~1.16 messages/second  
**Peak Rate:** ~10 messages/second (assuming 10x burst)  
**Storage:** ~100MB/day (assuming 1KB average message size)

### 11.2 Component Scaling

#### Proxy Server
- **Current Capacity:** 1,000+ req/sec with single Uvicorn instance
- **Scaling Strategy:** Vertical scaling sufficient; horizontal with load balancer if needed
- **Bottleneck:** Redis connection pool (easily configurable)

#### Workers
- **Current Config:** 4 concurrent workers
- **Scaling Strategy:** Horizontal scaling via multiple processes
- **Calculation:** 1 worker @ 30s retry = 2 msg/min = 120 msg/hr = 2,880 msg/day
- **Required Workers:** ~35 workers for 100k/day (with buffer)
- **Implementation:** Configurable worker count via `WORKER_CONCURRENCY` env var

#### Redis Queue
- **Current Capacity:** 100,000+ operations/second
- **Memory Usage:** ~100MB for 100k messages @ 1KB each
- **Scaling Strategy:** Redis Cluster if >1M messages/day
- **Bottleneck:** None for target scale

#### MySQL Database
- **Current Capacity:** 10,000+ writes/second (InnoDB)
- **Storage:** ~36GB/year (100k msgs/day @ 1KB)
- **Scaling Strategy:** Read replicas for portal; partitioning by domain
- **Bottleneck:** None for target scale

#### Portal
- **Current Capacity:** 100+ concurrent users
- **Scaling Strategy:** Vertical scaling; multiple instances behind load balancer
- **Optimization:** Caching with Redis, pagination

### 11.3 Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Message submission latency | < 100ms (p95) | Prometheus histogram |
| Queue processing rate | > 50 msg/sec | Worker metrics |
| Database write latency | < 50ms (p95) | SQLAlchemy metrics |
| Portal page load | < 2s | Browser timing |
| Message delivery time | < 60s (success) | End-to-end tracking |
| Worker retry interval | 30s (fixed) | Config |

### 11.4 Scaling Roadmap

**Phase 1 (0-50k msgs/day):**
- 1 Proxy instance
- 4 Worker processes
- 1 MySQL instance
- 1 Redis instance

**Phase 2 (50k-100k msgs/day):**
- 1-2 Proxy instances (load balanced)
- 8-16 Worker processes
- 1 MySQL instance + read replica
- 1 Redis instance

**Phase 3 (100k-500k msgs/day):**
- 2-4 Proxy instances (load balanced)
- 32-64 Worker processes (multiple servers)
- MySQL sharding or clustering
- Redis Cluster

**Phase 4 (500k+ msgs/day):**
- Evaluate migration to RabbitMQ or Kafka
- Microservices architecture
- Kubernetes deployment (if needed)

---

## 12. Sequence Diagrams

### 12.1 Message Submission Flow

```
Client              Proxy               Redis               Main Server          MySQL
  |                   |                   |                      |                  |
  |-- POST /msg ----->|                   |                      |                  |
  |   (Mutual TLS)    |                   |                      |                  |
  |                   |                   |                      |                  |
  |                   |-- Validate ------>|                      |                  |
  |                   |   (phone, body)   |                      |                  |
  |                   |                   |                      |                  |
  |                   |-- LPUSH --------->|                      |                  |
  |                   |   message_queue   |                      |                  |
  |                   |                   |-- ACK -------------->|                  |
  |                   |                   |                      |                  |
  |                   |-- POST /register ------------------>     |                  |
  |                   |   (Mutual TLS)                           |                  |
  |                   |                                          |                  |
  |                   |                                          |-- Encrypt ------>|
  |                   |                                          |   AES-256        |
  |                   |                                          |                  |
  |                   |                                          |-- Hash phone --->|
  |                   |                                          |   SHA-256        |
  |                   |                                          |                  |
  |                   |                                          |-- INSERT ------->|
  |                   |                                          |   status=queued  |
  |                   |                                          |                  |
  |                   |                                          |<-- ID -----------|
  |                   |                                          |                  |
  |                   |<-- 201 Created -----------------------------|                  |
  |                   |                                                              |
  |<-- 202 Accepted --|                                                              |
  |   {message_id}    |                                                              |
```

### 12.2 Message Processing Flow (Worker)

```
Worker              Redis               Main Server          MySQL
  |                   |                      |                  |
  |-- BRPOP --------->|                      |                  |
  |   message_queue   |                      |                  |
  |   (blocking)      |                      |                  |
  |                   |                      |                  |
  |<-- message -------|                      |                  |
  |                   |                      |                  |
  |-- POST /deliver ------------------>      |                  |
  |   (Mutual TLS)                           |                  |
  |                                          |                  |
  |                                          |-- UPDATE ------->|
  |                                          |   delivered_at   |
  |                                          |   status         |
  |                                          |                  |
  |                                          |<-- OK -----------|
  |                                          |                  |
  |<-- 200 OK ---------------------------|                      |
  |                                                             |
  |-- Log Success                                               |
  |-- Prometheus++                                              |
  
  
--- Failure Scenario ---

Worker              Redis               Main Server          MySQL
  |                   |                      |                  |
  |-- POST /deliver ------------------>      |                  |
  |   (timeout)                              |                  |
  |                                          X (error)          |
  |                                          |                  |
  |<-- 500 Error ------------------------|                      |
  |                                                             |
  |-- Sleep 30s                                                 |
  |                                                             |
  |-- LPUSH --------->|                                         |
  |   (re-queue)      |                                         |
  |                   |                                         |
  |-- Update DB ------------------------------------->          |
  |   attempt_count++                                           |
  |                                                             |
  |-- Log Retry                                                 |
  |-- Prometheus++                                              |
```

### 12.3 Certificate Issuance Flow

```
Admin CLI          Main Server         OpenSSL             Database
  |                   |                   |                   |
  |-- POST ---------->|                   |                   |
  |  /admin/certs     |                   |                   |
  |  {client_name}    |                   |                   |
  |                   |                   |                   |
  |                   |-- genrsa -------->|                   |
  |                   |   (2048-bit)      |                   |
  |                   |                   |                   |
  |                   |<-- private.key ---|                   |
  |                   |                   |                   |
  |                   |-- req ----------->|                   |
  |                   |   (CSR)           |                   |
  |                   |                   |                   |
  |                   |<-- client.csr ----|                   |
  |                   |                   |                   |
  |                   |-- x509 sign ----->|                   |
  |                   |   (with CA)       |                   |
  |                   |                   |                   |
  |                   |<-- client.crt ----|                   |
  |                   |                   |                   |
  |                   |-- fingerprint --->|                   |
  |                   |   SHA-256         |                   |
  |                   |                   |                   |
  |                   |<-- fingerprint ---|                   |
  |                   |                   |                   |
  |                   |-- INSERT ------------------------>     |
  |                   |   clients table                       |
  |                   |                                       |
  |                   |<-- client_id -----------------------------|
  |                   |                                       |
  |<-- Response ------|                                       |
  |   {cert, key,     |                                       |
  |    fingerprint}   |                                       |
```

### 12.4 Portal Authentication Flow

```
User Browser        Portal              Main Server          Database
  |                   |                      |                  |
  |-- GET /login ---->|                      |                  |
  |                   |                      |                  |
  |<-- Login Form ----|                      |                  |
  |                   |                      |                  |
  |-- POST ---------->|                      |                  |
  |   {user, pass}    |                      |                  |
  |                   |                      |                  |
  |                   |-- Query ----------------------->        |
  |                   |   users table                           |
  |                   |                                         |
  |                   |<-- user record ----------------------------|
  |                   |   (hashed password)                     |
  |                   |                                         |
  |                   |-- Verify hash                           |
  |                   |   (bcrypt)                              |
  |                   |                                         |
  |                   |-- Generate JWT                          |
  |                   |   (30min expiry)                        |
  |                   |                                         |
  |                   |-- UPDATE --------------------------->   |
  |                   |   last_login                            |
  |                   |                                         |
  |<-- Set-Cookie ----|                                         |
  |   JWT token       |                                         |
  |                   |                                         |
  |-- GET /messages ->|                                         |
  |   Cookie: JWT     |                                         |
  |                   |                                         |
  |                   |-- Verify JWT                            |
  |                   |   (signature)                           |
  |                   |                                         |
  |                   |-- POST /api/messages ---------->        |
  |                   |   (with JWT)                            |
  |                   |                                         |
  |                   |                            |-- Query -->|
  |                   |                            |   WHERE    |
  |                   |                            |   client_id|
  |                   |                            |            |
  |                   |                            |<-- rows ---|
  |                   |                            |            |
  |                   |                            |-- Decrypt  |
  |                   |                            |   (AES)    |
  |                   |                            |            |
  |                   |<-- JSON data -------------------        |
  |                   |                                         |
  |<-- HTML ----------|                                         |
  |   (rendered)      |                                         |
```

---

## 13. Configuration Model

### 13.1 Configuration Hierarchy

1. **Environment Variables** (.env file)
   - Database credentials
   - Redis connection
   - Service URLs
   - Secret keys

2. **YAML Configuration** (config.yaml)
   - Service-specific settings
   - Domain configurations
   - Feature flags
   - Rate limits

3. **Database Configuration**
   - Client certificates
   - Domain mappings
   - User roles

### 13.2 Configuration Files

#### Proxy Configuration (`proxy/config.yaml`)
```yaml
server:
  host: "0.0.0.0"
  port: 8001
  workers: 4

redis:
  host: "${REDIS_HOST}"
  port: 6379
  queue_name: "message_queue"

tls:
  cert_file: "certs/proxy.crt"
  key_file: "certs/proxy.key"
  ca_file: "certs/ca.crt"
  verify_client: true

validation:
  phone_pattern: "^\\+[1-9]\\d{1,14}$"
  max_body_length: 1000

rate_limiting:
  enabled: true
  max_requests: 100
  window_seconds: 60
```

#### Worker Configuration (`worker/config.yaml`)
```yaml
redis:
  host: "${REDIS_HOST}"
  queue_name: "message_queue"

worker:
  concurrency: 4
  retry_interval: 30
  max_attempts: 10000

main_server:
  url: "${MAIN_SERVER_URL}"
  timeout: 30

tls:
  cert_file: "certs/worker.crt"
  key_file: "certs/worker.key"
  ca_file: "certs/ca.crt"
```

#### Environment Variables (`.env`)
```bash
# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=StrongPass123!

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Security
AES_KEY_PATH=C:/app_secrets/aes.key
JWT_SECRET=SuperSecretKey

# Services
MAIN_SERVER_URL=https://localhost:8000
PROXY_URL=https://localhost:8001
```

### 13.3 Multi-Domain Configuration Example

```yaml
# domains.yaml
domains:
  - domain: "example.com"
    proxy:
      url: "https://proxy.example.com:8001"
      cert: "certs/example/proxy.crt"
    main_server:
      url: "https://main.example.com:8000"
    redis:
      queue_prefix: "example"
    
  - domain: "testdomain.com"
    proxy:
      url: "https://proxy.testdomain.com:8001"
      cert: "certs/testdomain/proxy.crt"
    main_server:
      url: "https://main.testdomain.com:8000"
    redis:
      queue_prefix: "testdomain"
```

---

## 14. Acceptance Criteria

### Phase 1 Deliverables Checklist

- [x] Design document completed
- [x] System architecture defined
- [x] Component responsibilities documented
- [x] Message schema specified (JSON format)
- [x] Authentication model defined (Mutual TLS + JWT)
- [x] Certificate lifecycle documented
- [x] Queue and persistence design completed
- [x] Multi-domain support approach defined
- [x] Technology stack with rationale
- [x] Scaling considerations (100k msgs/day)
- [x] Sequence diagrams for key flows
- [x] Configuration model defined

### Stakeholder Sign-off

**Review Required By:**
- Technical Lead
- Security Team
- Operations Team
- Project Sponsor

**Sign-off Criteria:**
1. Architecture supports 100k+ messages/day
2. Security model meets privacy requirements
3. Multi-domain support is feasible
4. Technology choices are appropriate
5. Scaling strategy is sound
6. Certificate management is practical

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **AOF** | Append-Only File - Redis persistence mechanism |
| **CA** | Certificate Authority - Issues and manages certificates |
| **CN** | Common Name - Certificate subject identifier |
| **CRL** | Certificate Revocation List - List of revoked certificates |
| **E.164** | International phone number format standard |
| **Mutual TLS** | Two-way TLS authentication (both parties verify certificates) |
| **JWT** | JSON Web Token - Token-based authentication |
| **SHA-256** | Secure Hash Algorithm 256-bit |
| **AES-256** | Advanced Encryption Standard 256-bit |

---

## Appendix B: References

1. [FastAPI Documentation](https://fastapi.tiangolo.com/)
2. [Redis Persistence](https://redis.io/topics/persistence)
3. [OpenSSL Certificate Management](https://www.openssl.org/docs/)
4. [E.164 Phone Number Format](https://www.itu.int/rec/T-REC-E.164/)
5. [Mutual TLS Authentication](https://en.wikipedia.org/wiki/Mutual_authentication)
6. [SQLAlchemy ORM](https://docs.sqlalchemy.org/)
7. [Prometheus Monitoring](https://prometheus.io/docs/)

---

**Document Status:** Ready for Review  
**Next Phase:** Phase 2 - API & Database Specification  
**Questions/Feedback:** Contact development team


