# API Specification - Message Broker System

**Version:** 1.0.0  
**Date:** October 2025  
**Status:** Phase 2 - Complete

---

## Table of Contents

1. [Overview](#overview)
2. [Authentication](#authentication)
3. [Proxy API](#proxy-api)
4. [Main Server API](#main-server-api)
5. [Portal API](#portal-api)
6. [Error Handling](#error-handling)
7. [Rate Limiting](#rate-limiting)
8. [API Versioning](#api-versioning)

---

## Overview

The Message Broker System provides three distinct APIs:

1. **Proxy API** - Message submission endpoint for clients (Mutual TLS)
2. **Main Server API** - Internal and admin endpoints (Mutual TLS)
3. **Portal API** - Web portal access for users (JWT)

All APIs follow RESTful principles and use JSON for request/response payloads.

---

## Authentication

### Mutual TLS (mTLS)

Used for:
- Client → Proxy communication
- Proxy → Main Server communication
- Worker → Main Server communication
- Admin → Main Server communication

**Requirements:**
- Valid X.509 client certificate issued by Message Broker CA
- Certificate must not be expired
- Certificate must not be revoked (CRL check)
- Certificate fingerprint must match registered client

**Certificate Format:**
```
Subject: CN=client_name, O=Organization
Issuer: CN=MessageBrokerCA
Validity: 365 days
Key Size: 2048-bit RSA
Signature: SHA-256
```

### JWT Authentication

Used for:
- Portal web interface access

**Token Format:**
```json
{
  "sub": "user@example.com",
  "role": "admin",
  "client_id": "client_001",
  "exp": 1698765432,
  "iat": 1698763632
}
```

**Token Lifetime:** 30 minutes  
**Algorithm:** HS256  
**Header:** `Authorization: Bearer <token>`

---

## Proxy API

### Base URL
```
https://proxy.example.com:8001/api/v1
```

### Endpoints

#### POST /messages
Submit a message for processing.

**Authentication:** Mutual TLS (required)

**Request:**
```json
{
  "sender_number": "+1234567890",
  "message_body": "Message content here",
  "metadata": {
    "timestamp": "2025-10-20T12:34:56.789Z"
  }
}
```

**Request Fields:**
- `sender_number` (required, string): Phone number in E.164 format
  - Pattern: `^\+[1-9]\d{1,14}$`
  - Min length: 8 characters
  - Max length: 16 characters
- `message_body` (required, string): Message content
  - Min length: 1 character
  - Max length: 1000 characters
- `metadata` (optional, object): Additional metadata
  - `timestamp` (optional, string): ISO 8601 timestamp

**Response (202 Accepted):**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "client_id": "client_001",
  "queued_at": "2025-10-20T12:34:56.789Z",
  "position": 5
}
```

**Response Fields:**
- `message_id` (string): UUID v4 identifier
- `status` (string): Always "queued" on success
- `client_id` (string): Extracted from certificate
- `queued_at` (string): ISO 8601 timestamp
- `position` (integer, optional): Position in queue

**Error Responses:**
- `400` - Invalid request (bad phone number, message too long)
- `401` - Authentication failed (invalid certificate)
- `403` - Certificate revoked
- `429` - Rate limit exceeded
- `500` - Internal server error
- `503` - Service unavailable (Redis down)

**Rate Limit:** 100 requests per 60 seconds per client

---

#### GET /health
Check proxy server health.

**Authentication:** None

**Response (200 OK):**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-10-20T12:34:56.789Z",
  "checks": {
    "redis": "healthy",
    "main_server": "healthy",
    "certificate": "valid"
  },
  "uptime_seconds": 86400
}
```

**Status Values:**
- `healthy` - All systems operational
- `degraded` - Some components have issues
- `unhealthy` - Critical components down

---

#### GET /metrics
Prometheus metrics endpoint.

**Authentication:** None (or basic auth in production)

**Response (200 OK):**
```
# HELP proxy_requests_total Total number of requests
# TYPE proxy_requests_total counter
proxy_requests_total{method="POST",endpoint="/api/v1/messages",status="202"} 1234

# HELP proxy_request_duration_seconds Request duration in seconds
# TYPE proxy_request_duration_seconds histogram
proxy_request_duration_seconds_bucket{le="0.1"} 1000
proxy_request_duration_seconds_bucket{le="0.5"} 1200

# HELP redis_queue_size Current queue size
# TYPE redis_queue_size gauge
redis_queue_size 42
```

---

## Main Server API

### Base URL
```
https://main.example.com:8000
```

### Internal API Endpoints

#### POST /internal/messages/register
Register a new message in the database.

**Authentication:** Mutual TLS (proxy only)

**Request:**
```json
{
  "sender_number": "+1234567890",
  "message_body": "Message content",
  "client_id": "client_001",
  "domain": "example.com",
  "metadata": {}
}
```

**Response (201 Created):**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "created_at": "2025-10-20T12:34:56.789Z"
}
```

---

#### POST /internal/messages/deliver
Mark message as delivered.

**Authentication:** Mutual TLS (workers only)

**Request:**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "worker_id": "worker-01"
}
```

**Response (200 OK):**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "delivered",
  "delivered_at": "2025-10-20T12:35:12.345Z"
}
```

---

#### PUT /internal/messages/{message_id}/status
Update message status and attempt count.

**Authentication:** Mutual TLS (workers only)

**Request:**
```json
{
  "status": "failed",
  "attempt_count": 3,
  "error_message": "Connection timeout"
}
```

**Response (200 OK):**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "failed",
  "attempt_count": 3,
  "updated_at": "2025-10-20T12:35:45.678Z"
}
```

---

### Admin API Endpoints

#### POST /admin/certificates/generate
Generate a new client certificate.

**Authentication:** Mutual TLS (admin certificate)

**Request:**
```json
{
  "client_name": "client_002",
  "domain": "example.com",
  "validity_days": 365
}
```

**Response (201 Created):**
```json
{
  "client_id": "client_002",
  "certificate": "-----BEGIN CERTIFICATE-----\n...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "fingerprint": "SHA256:abc123...",
  "expires_at": "2026-10-20T12:34:56.789Z",
  "ca_certificate": "-----BEGIN CERTIFICATE-----\n..."
}
```

**⚠️ Important:** Private key is only returned once. Store securely.

---

#### POST /admin/certificates/revoke
Revoke a client certificate.

**Authentication:** Mutual TLS (admin certificate)

**Request:**
```json
{
  "client_id": "client_002",
  "reason": "Certificate compromised"
}
```

**Response (200 OK):**
```json
{
  "client_id": "client_002",
  "status": "revoked",
  "revoked_at": "2025-10-20T12:34:56.789Z"
}
```

---

#### GET /admin/certificates
List all certificates.

**Authentication:** Mutual TLS (admin certificate)

**Query Parameters:**
- `status` (string, optional): Filter by status (active, revoked, expired, all)
- `domain` (string, optional): Filter by domain
- `page` (integer, optional): Page number (default: 1)
- `per_page` (integer, optional): Items per page (default: 50, max: 100)

**Response (200 OK):**
```json
{
  "certificates": [
    {
      "client_id": "client_001",
      "fingerprint": "SHA256:abc123...",
      "status": "active",
      "domain": "example.com",
      "created_at": "2025-01-01T00:00:00Z",
      "expires_at": "2026-01-01T00:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 100,
    "pages": 2
  }
}
```

---

#### GET /admin/stats
Get system statistics.

**Authentication:** Mutual TLS (admin certificate)

**Query Parameters:**
- `period` (string, optional): Time period (hour, day, week, month)

**Response (200 OK):**
```json
{
  "messages": {
    "total": 100000,
    "queued": 42,
    "delivered": 99850,
    "failed": 108
  },
  "performance": {
    "avg_delivery_time_seconds": 15.3,
    "success_rate": 0.998,
    "queue_size": 42
  },
  "clients": {
    "total": 50,
    "active": 48,
    "revoked": 2
  }
}
```

---

#### GET /admin/users
List portal users.

**Authentication:** Mutual TLS (admin certificate)

**Response (200 OK):**
```json
{
  "users": [
    {
      "user_id": 1,
      "email": "admin@example.com",
      "role": "admin",
      "client_id": null,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 10,
    "pages": 1
  }
}
```

---

#### POST /admin/users
Create a new portal user.

**Authentication:** Mutual TLS (admin certificate)

**Request:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "role": "user",
  "client_id": "client_001"
}
```

**Response (201 Created):**
```json
{
  "user_id": 2,
  "email": "user@example.com",
  "role": "user",
  "client_id": "client_001",
  "created_at": "2025-10-20T12:34:56.789Z"
}
```

---

#### DELETE /admin/users/{user_id}
Delete a portal user.

**Authentication:** Mutual TLS (admin certificate)

**Response (204 No Content)**

---

## Portal API

### Base URL
```
https://portal.example.com:8080
```

### Authentication Endpoints

#### POST /portal/auth/login
Authenticate and obtain JWT token.

**Authentication:** None

**Request:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
```

**Response (200 OK):**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "expires_in": 1800,
  "user": {
    "user_id": 2,
    "email": "user@example.com",
    "role": "user",
    "client_id": "client_001",
    "last_login": "2025-10-20T12:34:56.789Z",
    "created_at": "2025-01-01T00:00:00Z"
  }
}
```

---

#### POST /portal/auth/refresh
Refresh JWT token.

**Authentication:** Bearer token

**Response (200 OK):**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "expires_in": 1800
}
```

---

### Message Endpoints

#### GET /portal/messages
Get messages for authenticated user.

**Authentication:** Bearer token

**Query Parameters:**
- `status` (string, optional): Filter by status (queued, delivered, failed, all)
- `from_date` (string, optional): Start date (ISO 8601)
- `to_date` (string, optional): End date (ISO 8601)
- `search` (string, optional): Search in sender_number (hashed comparison)
- `page` (integer, optional): Page number (default: 1)
- `per_page` (integer, optional): Items per page (default: 50, max: 100)

**Response (200 OK):**
```json
{
  "messages": [
    {
      "message_id": "550e8400-e29b-41d4-a716-446655440000",
      "sender_number_masked": "+123****7890",
      "status": "delivered",
      "created_at": "2025-10-20T12:34:56.789Z",
      "delivered_at": "2025-10-20T12:35:12.345Z",
      "attempt_count": 1
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 1000,
    "pages": 20
  }
}
```

---

#### GET /portal/messages/{message_id}
Get detailed information about a specific message.

**Authentication:** Bearer token

**Authorization:** User can only view own messages (admin can view all)

**Response (200 OK):**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "sender_number_masked": "+123****7890",
  "message_body": "Decrypted message content",
  "status": "delivered",
  "created_at": "2025-10-20T12:34:56.789Z",
  "queued_at": "2025-10-20T12:34:56.789Z",
  "delivered_at": "2025-10-20T12:35:12.345Z",
  "attempt_count": 1,
  "domain": "example.com"
}
```

---

#### GET /portal/profile
Get user profile information.

**Authentication:** Bearer token

**Response (200 OK):**
```json
{
  "user_id": 2,
  "email": "user@example.com",
  "role": "user",
  "client_id": "client_001",
  "last_login": "2025-10-20T12:34:56.789Z",
  "created_at": "2025-01-01T00:00:00Z"
}
```

---

## Error Handling

### Standard Error Response

All errors follow this format:

```json
{
  "error": "error_code",
  "message": "Human-readable error message",
  "details": {
    "field": "sender_number",
    "value": "1234567890"
  },
  "timestamp": "2025-10-20T12:34:56.789Z",
  "request_id": "req_abc123"
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `validation_error` | 400 | Request validation failed |
| `authentication_error` | 401 | Authentication required or failed |
| `authorization_error` | 403 | Insufficient permissions |
| `not_found` | 404 | Resource not found |
| `conflict` | 409 | Resource already exists |
| `rate_limit_exceeded` | 429 | Rate limit exceeded |
| `internal_error` | 500 | Internal server error |
| `service_unavailable` | 503 | Service temporarily unavailable |

### Error Details by Endpoint

#### Message Validation Errors

**Invalid phone number:**
```json
{
  "error": "validation_error",
  "message": "Invalid sender_number format. Must be E.164 format.",
  "details": {
    "field": "sender_number",
    "value": "1234567890",
    "expected_format": "^\\+[1-9]\\d{1,14}$"
  }
}
```

**Message too long:**
```json
{
  "error": "validation_error",
  "message": "message_body exceeds maximum length of 1000 characters",
  "details": {
    "field": "message_body",
    "length": 1234,
    "max_length": 1000
  }
}
```

---

## Rate Limiting

### Proxy API

- **Limit:** 100 requests per 60 seconds
- **Scope:** Per client certificate
- **Headers:**
  - `X-RateLimit-Limit`: Maximum requests allowed
  - `X-RateLimit-Remaining`: Requests remaining in window
  - `X-RateLimit-Reset`: Unix timestamp when limit resets

**Rate Limit Exceeded Response (429):**
```json
{
  "error": "rate_limit_exceeded",
  "message": "Rate limit of 100 requests per 60 seconds exceeded",
  "retry_after": 45,
  "timestamp": "2025-10-20T12:34:56.789Z"
}
```

### Portal API

- **Limit:** 1000 requests per hour
- **Scope:** Per user account

### Admin API

- **Limit:** No limit (trusted internal network)

---

## API Versioning

### Current Version
`v1` (1.0.0)

### Version Format
URL path versioning: `/api/v1/endpoint`

### Version Support Policy
- Major version supported for minimum 12 months after new version release
- Deprecated endpoints will have 6-month notice period
- Breaking changes only in major versions

### Deprecation Headers
Deprecated endpoints include:
```
X-API-Deprecation: true
X-API-Sunset: 2026-01-01T00:00:00Z
X-API-Alternative: /api/v2/endpoint
```

---

## OpenAPI/Swagger Documentation

Interactive API documentation is available at:

- **Proxy API:** https://proxy.example.com:8001/docs
- **Main Server API:** https://main.example.com:8000/docs
- **Portal API:** https://portal.example.com:8080/docs

OpenAPI specification files:
- `proxy/openapi.yaml`
- `main_server/openapi.yaml`

---

## Testing

### Example cURL Requests

**Submit a message (with client certificate):**
```bash
curl -X POST https://localhost:8001/api/v1/messages \
  -H "Content-Type: application/json" \
  --cert client.crt \
  --key client.key \
  --cacert ca.crt \
  -d '{
    "sender_number": "+1234567890",
    "message_body": "Test message"
  }'
```

**Portal login:**
```bash
curl -X POST https://localhost:8080/portal/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePass123!"
  }'
```

**Get messages (with JWT):**
```bash
curl -X GET "https://localhost:8080/portal/messages?status=delivered" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

---

## Support

For API issues or questions:
- Create an issue in the repository
- Contact: support@messagebroker.example.com
- Documentation: [DESIGN.md](DESIGN.md)

---

**Document Version:** 1.0.0  
**Last Updated:** October 2025  
**Phase:** Phase 2 Complete

