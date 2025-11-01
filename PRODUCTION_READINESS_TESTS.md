# Production Readiness Test Requirements

**Version**: 1.0  
**Date**: January 2025  
**Status**: Required Before Production Deployment

---

## Overview

This document outlines **ALL** tests that the Message Broker System must pass before production deployment. The system includes 92 documented test cases across 6 categories, plus additional production verification tests.

**Critical**: **100% of critical test cases must pass** before deployment. **95%+ of all test cases must pass** overall.

---

## Test Execution Order

1. **Pre-Flight Checks** - Environment validation (MUST PASS)
2. **Functional Tests** - Component functionality (MUST PASS)
3. **Integration Tests** - End-to-end flows (MUST PASS)
4. **Load Tests** - Performance verification (MUST PASS)
5. **Security Tests** - Security validation (MUST PASS)
6. **Smoke Tests** - Post-deployment verification (MUST PASS)

---

## 1. Pre-Flight Checks (Environment Validation)

**Script**: `tests/preflight_check.py`  
**Status**: ✅ **MUST PASS ALL** (7/7 checks)

### Required Checks:

- [ ] ✅ **Python Version**: Python 3.8+ installed and accessible
- [ ] ✅ **Dependencies**: All required Python packages installed (httpx, redis, pymysql, etc.)
- [ ] ✅ **MySQL Connection**: Database `message_system` accessible with correct credentials
- [ ] ✅ **Redis Connection**: Redis/Memurai running and responding to PING
- [ ] ✅ **Database Schema**: All required tables exist (users, clients, messages, audit_log, alembic_version)
- [ ] ✅ **Certificates**: All certificate files present (CA, server, proxy, worker, test clients)
- [ ] ✅ **Project Structure**: All component directories exist (proxy, main_server, worker, portal)

**Run Command**:
```powershell
cd tests
python preflight_check.py
```

**Success Criteria**: All 7 checks must pass (100%)

---

## 2. Functional Tests (50 Test Cases)

**Test Suite**: Component-level functionality verification  
**Status**: ✅ **100% of critical test cases MUST PASS**

### 2.1 Proxy Server Tests (10 cases)

- [ ] **TC-P-001**: Submit valid message with proper E.164 phone number
- [ ] **TC-P-002**: Invalid phone number format rejected (e.g., missing +, letters)
- [ ] **TC-P-003**: Invalid message body length rejected (empty or >1000 chars)
- [ ] **TC-P-004**: Request without client certificate rejected
- [ ] **TC-P-005**: Revoked certificate rejected
- [ ] **TC-P-006**: Health check endpoint (`/api/v1/health`) responds correctly
- [ ] **TC-P-007**: Metrics endpoint (`/metrics`) exposes Prometheus metrics
- [ ] **TC-P-008**: Redis connection failure handled gracefully (fallback behavior)
- [ ] **TC-P-009**: Main server connection failure handled gracefully
- [ ] **TC-P-010**: Concurrent message submissions work correctly

**Run Command**:
```powershell
cd tests
.\run_functional_tests.ps1
```

### 2.2 Main Server Tests (15 cases)

- [ ] **TC-M-001**: Message registration via `/internal/messages/register` works
- [ ] **TC-M-002**: Message delivery marking via `/internal/messages/deliver` works
- [ ] **TC-M-003**: Status updates via `/internal/messages/status` work
- [ ] **TC-M-004**: User login via `/portal/auth/login` generates valid JWT
- [ ] **TC-M-005**: Token refresh via `/portal/auth/refresh` works
- [ ] **TC-M-006**: Get messages via `/portal/messages` returns user's messages
- [ ] **TC-M-007**: Get profile via `/portal/profile` returns user data
- [ ] **TC-M-008**: Create user via `/admin/users/create` (admin only)
- [ ] **TC-M-009**: Generate certificate via `/admin/certificates/generate` works
- [ ] **TC-M-010**: Revoke certificate via `/admin/certificates/revoke` works
- [ ] **TC-M-011**: Get statistics via `/admin/stats` returns system metrics
- [ ] **TC-M-012**: Health check (`/health`) responds correctly
- [ ] **TC-M-013**: Message encryption/decryption works (AES-256)
- [ ] **TC-M-014**: Phone number hashing works (SHA-256)
- [ ] **TC-M-015**: Role-based access control (RBAC) enforced correctly

### 2.3 Worker Tests (10 cases)

- [ ] **TC-W-001**: Single message processing from Redis queue works
- [ ] **TC-W-002**: Retry logic works with 30-second interval
- [ ] **TC-W-003**: Status updated to "delivered" on successful delivery
- [ ] **TC-W-004**: Status updated to "failed" after max attempts
- [ ] **TC-W-005**: Concurrent message processing works (multiple workers)
- [ ] **TC-W-006**: Graceful shutdown handles in-flight messages
- [ ] **TC-W-007**: Redis connection recovery after network interruption
- [ ] **TC-W-008**: Main server connection recovery after server restart
- [ ] **TC-W-009**: Max attempts (default: 5) respected and not exceeded
- [ ] **TC-W-010**: Empty queue handled correctly (no errors, continues polling)

### 2.4 Portal Tests (15 cases)

- [ ] **TC-PT-001**: User login success redirects to dashboard
- [ ] **TC-PT-002**: User login failure shows error message
- [ ] **TC-PT-003**: User logout clears session and redirects to login
- [ ] **TC-PT-004**: Session expiration redirects to login after timeout
- [ ] **TC-PT-005**: View user messages displays only user's messages
- [ ] **TC-PT-006**: Filter messages by status works (queued, delivered, failed)
- [ ] **TC-PT-007**: Pagination works for large message lists
- [ ] **TC-PT-008**: View profile displays user information
- [ ] **TC-PT-009**: Admin dashboard accessible only to admin users
- [ ] **TC-PT-010**: Admin create user form works
- [ ] **TC-PT-011**: Admin generate certificate form works
- [ ] **TC-PT-012**: Admin revoke certificate form works
- [ ] **TC-PT-013**: Admin view all messages shows all users' messages
- [ ] **TC-PT-014**: Non-admin users cannot access admin pages (403)
- [ ] **TC-PT-015**: Responsive design works on mobile and desktop

**Success Criteria**: 
- ✅ 100% of critical test cases pass
- ✅ 95%+ of all test cases pass
- ✅ All blocking bugs fixed

---

## 3. Integration Tests (14 Test Cases)

**Test Suite**: End-to-end system integration  
**Status**: ✅ **MUST PASS ALL** - No data loss acceptable

### 3.1 End-to-End Message Flow (5 cases)

- [ ] **TC-I-001**: Complete message delivery flow:
  - Client sends message → Proxy validates → Redis queue → Worker processes → Main server marks delivered → Database updated
- [ ] **TC-I-002**: Message retry flow:
  - Worker fails delivery → Message requeued → Worker retries after 30s → Eventually succeeds/fails after max attempts
- [ ] **TC-I-003**: Multiple concurrent flows:
  - 10+ simultaneous messages processed correctly with no data loss
- [ ] **TC-I-004**: Database persistence throughout flow:
  - Message status transitions recorded correctly (queued → delivered/failed)
- [ ] **TC-I-005**: Status transitions correct:
  - Messages transition from "queued" → "delivered" or "failed" correctly

### 3.2 Authentication Flow (4 cases)

- [ ] **TC-I-006**: Certificate lifecycle:
  - Generate certificate → Use certificate to send messages → Revoke certificate → Revoked certificate rejected
- [ ] **TC-I-007**: User creation flow:
  - Admin creates user → User logs in → User accesses portal API with JWT
- [ ] **TC-I-008**: JWT token lifecycle:
  - Login generates token → Token valid for API calls → Token expires → Refresh generates new token
- [ ] **TC-I-009**: Session management:
  - User logs in → Session maintained across requests → Logout clears session

### 3.3 Component Integration (5 cases)

- [ ] **TC-I-010**: Proxy → Main Server communication:
  - Proxy registers messages via mTLS successfully
- [ ] **TC-I-011**: Worker → Main Server communication:
  - Worker delivers messages via mTLS successfully
- [ ] **TC-I-012**: Portal → Main Server communication:
  - Portal API calls authenticated and authorized correctly
- [ ] **TC-I-013**: All components → Redis:
  - Proxy, Worker, Main Server all interact with Redis queue correctly
- [ ] **TC-I-014**: All components → MySQL:
  - All database operations from all components work correctly

**Run Command**:
```powershell
cd tests
.\run_integration_tests.ps1
# OR
python integration_test.py
```

**Success Criteria**:
- ✅ End-to-end message flow works correctly
- ✅ All component integrations verified
- ✅ **No data loss in the pipeline**
- ✅ Status updates propagate correctly

---

## 4. Load Tests (11 Test Cases)

**Test Suite**: Performance and throughput verification  
**Status**: ✅ **MUST MEET TARGETS** - 100k messages/day capacity

### 4.1 Throughput Tests (7 cases)

- [ ] **TC-L-001**: Sustained 1 msg/sec for 1 hour (3,600 messages)
  - Success rate ≥ 95%
  - Average response time < 1 second
  - P99 response time < 5 seconds
- [ ] **TC-L-002**: Sustained 10 msg/sec for 10 minutes (6,000 messages)
  - Success rate ≥ 95%
  - Queue remains stable (doesn't grow indefinitely)
- [ ] **TC-L-003**: Burst 100 msg/sec for 1 minute (6,000 messages)
  - Success rate ≥ 90% (more lenient for bursts)
  - System recovers gracefully after burst
- [ ] **TC-L-004**: Daily target simulation (100k messages over 24 hours)
  - System handles sustained load without degradation
  - No message loss
- [ ] **TC-L-005**: Queue growth under load
  - Queue grows during peak but drains during normal load
  - No queue overflow or message loss
- [ ] **TC-L-006**: Worker processing under load
  - Multiple workers process queue efficiently
  - No duplicate processing
- [ ] **TC-L-007**: Database performance under load
  - Database queries complete in reasonable time (<2s)
  - No connection pool exhaustion

### 4.2 Concurrency Tests (4 cases)

- [ ] **TC-L-008**: Multiple proxy instances
  - 2+ proxy instances handle load sharing correctly
- [ ] **TC-L-009**: Multiple worker instances
  - 3+ worker instances process queue concurrently without conflicts
- [ ] **TC-L-010**: Concurrent portal users
  - 10+ simultaneous portal users can access system
- [ ] **TC-L-011**: Concurrent database connections
  - Connection pool handles all component connections

**Run Command**:
```powershell
cd tests
.\run_load_tests.ps1
# OR
python load_test.py
```

**Success Criteria**:
- ✅ System handles **100,000 messages/day** (target: ~1.16 msg/sec sustained)
- ✅ **No message loss** under load
- ✅ Queue remains manageable (drains faster than it fills)
- ✅ Response times within acceptable limits:
  - Average < 1 second
  - P95 < 3 seconds
  - P99 < 5 seconds
- ✅ Success rate ≥ 95% under sustained load
- ✅ Success rate ≥ 90% under burst load

---

## 5. Security Tests (17 Test Cases)

**Test Suite**: Security validation and verification  
**Status**: ✅ **MUST PASS ALL** - Security is critical

### 5.1 Authentication Tests (8 cases)

- [ ] **TC-S-001**: Mutual TLS enforced on proxy
  - Requests without valid client certificate rejected (401/403)
- [ ] **TC-S-002**: Mutual TLS enforced on internal APIs (worker → main server)
  - Worker cannot connect without valid certificate
- [ ] **TC-S-003**: Invalid certificates rejected
  - Certificates not signed by CA rejected
- [ ] **TC-S-004**: Expired certificates rejected
  - Certificates past expiration date rejected
- [ ] **TC-S-005**: Revoked certificates rejected
  - Certificates in CRL rejected
- [ ] **TC-S-006**: JWT token validation
  - Valid JWT tokens accepted, invalid signatures rejected
- [ ] **TC-S-007**: Invalid JWT tokens rejected
  - Malformed tokens, wrong secret, etc. rejected
- [ ] **TC-S-008**: Expired JWT tokens handled
  - Expired tokens rejected, refresh token required

### 5.2 Encryption Tests (5 cases)

- [ ] **TC-S-009**: Message body encryption at rest
  - Messages stored in database are encrypted (AES-256)
  - Plain text messages NOT visible in database
- [ ] **TC-S-010**: Message body decryption
  - Authorized users (admins) can decrypt messages correctly
  - Regular users see "[encrypted]" placeholder
- [ ] **TC-S-011**: Phone number hashing
  - Sender numbers stored as SHA-256 hashes
  - Plain text phone numbers NOT visible in database
- [ ] **TC-S-012**: Password hashing (bcrypt)
  - Passwords stored with bcrypt (12 rounds)
  - Plain text passwords NOT visible in database
- [ ] **TC-S-013**: Session encryption
  - Session cookies encrypted/signed

### 5.3 Access Control Tests (4 cases)

- [ ] **TC-S-014**: Users can only access own messages
  - Regular users cannot see other users' messages
- [ ] **TC-S-015**: Admins can access all messages
  - Admin users can view all messages in system
- [ ] **TC-S-016**: Users cannot access admin pages
  - Regular users receive 403 on admin endpoints
- [ ] **TC-S-017**: Unauthenticated access rejected
  - All protected endpoints require authentication

**Run Command**:
```powershell
cd tests
.\run_security_tests.ps1
# OR
python security_test.py
```

**Success Criteria**:
- ✅ **Mutual TLS enforced** on all internal APIs
- ✅ **Messages encrypted at rest** (AES-256)
- ✅ **No plain text passwords** in database
- ✅ **Role-based access control** working correctly
- ✅ **Revoked certificates rejected**
- ✅ No plain text sensitive data in database

---

## 6. Smoke Tests (Post-Deployment Verification)

**Script**: `deployment/tests/smoke_test.ps1`  
**Status**: ✅ **MUST PASS ALL** - Run after deployment

### Required Checks (9 tests):

- [ ] **Service Status**: All Windows Services running
  - MessageBrokerMainServer
  - MessageBrokerProxy
  - MessageBrokerWorker
  - MessageBrokerPortal
  - MySQL
  - Memurai (Redis)
- [ ] **MySQL Connectivity**: Database accessible and responsive
- [ ] **Redis Connectivity**: Queue accessible and responsive
- [ ] **Main Server Health**: `/health` endpoint returns 200
- [ ] **Proxy Health**: `/api/v1/health` endpoint returns 200
- [ ] **Portal Health**: `/health` endpoint returns 200
- [ ] **Worker Metrics**: `/metrics` endpoint accessible (if enabled)
- [ ] **Certificates**: All certificate files present and valid
- [ ] **Log Files**: Log directory exists and writable

**Run Command**:
```powershell
cd deployment/tests
.\smoke_test.ps1
```

**Success Criteria**: All 9 checks must pass (100%)

---

## 7. Regression Tests

**Status**: Run after bug fixes or configuration changes

### After Bug Fixes:

- [ ] All reported bugs fixed and verified
- [ ] Original test cases still pass (fixes don't break existing functionality)
- [ ] No new bugs introduced
- [ ] Critical path tests still pass

### Configuration Changes:

- [ ] Environment variable changes work correctly
- [ ] Port changes work correctly
- [ ] Database configuration changes work correctly

---

## Test Execution Summary

### Quick Test Run (Skip Load & Security)

For faster iteration during development:

```powershell
cd tests
.\run_all_tests.ps1 -Quick
```

### Full Test Run (Production Readiness)

For production deployment verification:

```powershell
cd tests

# Step 1: Pre-flight checks
python preflight_check.py

# Step 2: Functional tests
.\run_functional_tests.ps1

# Step 3: Integration tests
.\run_integration_tests.ps1

# Step 4: Load tests (takes 10+ minutes)
.\run_load_tests.ps1

# Step 5: Security tests
.\run_security_tests.ps1

# OR run all at once:
.\run_all_tests.ps1
```

---

## Success Criteria Summary

### Critical (MUST PASS):

1. ✅ **Pre-Flight Checks**: 7/7 (100%)
2. ✅ **Functional Tests**: 100% of critical cases, 95%+ overall
3. ✅ **Integration Tests**: 100% pass (no data loss)
4. ✅ **Security Tests**: 100% pass (security is critical)
5. ✅ **Smoke Tests**: 9/9 (100%)

### Performance (MUST MEET TARGETS):

6. ✅ **Load Tests**: 
   - Handles 100,000 messages/day
   - No message loss
   - Success rate ≥ 95%
   - Response times: P99 < 5 seconds

---

## Production Deployment Gating

**DO NOT DEPLOY** if:

- ❌ Any pre-flight check fails
- ❌ Any critical functional test fails
- ❌ Any integration test fails (data loss risk)
- ❌ Any security test fails
- ❌ Smoke tests fail after deployment
- ❌ Load tests don't meet performance targets
- ❌ Message loss detected under load

**DEPLOY ONLY IF**:

- ✅ All pre-flight checks pass
- ✅ 100% of critical functional tests pass
- ✅ 95%+ of all functional tests pass
- ✅ 100% of integration tests pass
- ✅ 100% of security tests pass
- ✅ Load tests meet all performance targets
- ✅ Smoke tests pass after deployment
- ✅ All blocking bugs resolved
- ✅ Documentation complete

---

## Test Documentation

For detailed test procedures, see:
- `tests/TEST_PLAN.md` - Complete test plan with 92 test cases
- `tests/QA_CHECKLIST.md` - QA verification checklist
- `tests/README.md` - Test suite overview
- `tests/SETUP.md` - Test environment setup guide

---

## Post-Deployment Monitoring

After deployment, monitor:

1. **Health Endpoints**: All services returning 200
2. **Queue Size**: Redis queue draining normally
3. **Message Status**: Messages transitioning queued → delivered
4. **Error Rates**: Logs showing no critical errors
5. **Performance**: Response times within targets
6. **Security**: No unauthorized access attempts

---

**Last Updated**: January 2025  
**Version**: 1.0  
**Status**: Production Ready Test Requirements

