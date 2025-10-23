# Message Broker System - Comprehensive Test Plan

**Version**: 1.0  
**Date**: October 2025  
**Phase**: Phase 8 - Testing & QA  
**Project**: Message Broker System

---

## Table of Contents

- [Overview](#overview)
- [Test Objectives](#test-objectives)
- [Test Scope](#test-scope)
- [Test Environment](#test-environment)
- [Test Categories](#test-categories)
- [Test Schedule](#test-schedule)
- [Success Criteria](#success-criteria)
- [Test Execution](#test-execution)

---

## Overview

This document outlines the comprehensive testing strategy for the Message Broker System, covering functional testing, integration testing, load testing, and security verification.

### System Under Test

- **Proxy Server**: Message ingestion and validation
- **Main Server**: API, database, authentication, certificate management
- **Worker**: Message processing and delivery with retry logic
- **Portal**: Web interface for users and administrators
- **Infrastructure**: Redis queue, MySQL database, certificates

### Testing Approach

**Manual Testing** (as per requirements):
- No automated test frameworks required
- Manual test execution with documented procedures
- Test scripts for repeatability
- Manual verification of results
- Documented test reports

---

## Test Objectives

1. **Functional Verification**: Verify all features work as specified
2. **Integration Testing**: Verify components work together correctly
3. **Load Testing**: Verify system handles target throughput (~100k messages/day)
4. **Security Testing**: Verify mutual TLS, encryption, and access control
5. **Regression Testing**: Verify fixes don't break existing functionality
6. **User Acceptance**: Verify system meets business requirements

---

## Test Scope

### In Scope

✅ **Proxy Server**:
- Message submission with valid/invalid data
- Client certificate authentication
- Phone number validation (E.164 format)
- Message body validation (1-1000 characters)
- Redis queue integration
- Main server registration API calls
- Health check endpoints
- Metrics exposure

✅ **Main Server**:
- Internal API (message registration, delivery, status updates)
- Portal API (authentication, message retrieval)
- Admin API (user management, certificate operations, statistics)
- Database operations (CRUD, encryption, hashing)
- JWT token generation and validation
- Password hashing and verification
- Role-based access control
- Health checks and metrics

✅ **Worker**:
- Redis queue consumption
- Message delivery to main server
- Retry logic (30-second interval)
- Status updates
- Concurrent processing
- Graceful shutdown
- Metrics and logging

✅ **Portal**:
- User authentication (login, logout, session)
- User dashboard (message viewing, filtering)
- Admin dashboard (statistics, management)
- User management interface
- Certificate management interface
- Message viewing and filtering
- Pagination

✅ **Integration**:
- End-to-end message flow (client → proxy → queue → worker → delivery)
- Certificate lifecycle (generation → usage → revocation)
- Authentication flow (login → session → API calls)
- Database persistence and retrieval

✅ **Security**:
- Mutual TLS enforcement
- Message encryption at rest
- Phone number hashing
- JWT token security
- Session security
- Certificate revocation checking

✅ **Performance**:
- Throughput testing (~100k messages/day = ~1.16 msg/sec)
- Load burst handling
- Queue management under load
- Database performance
- Concurrent worker processing

### Out of Scope

❌ Automated unit tests (not required per specifications)
❌ Continuous integration testing
❌ Stress testing beyond 100k messages/day
❌ Mobile app testing (no mobile app)
❌ Browser compatibility testing (modern browsers only)

---

## Test Environment

### Hardware Requirements

**Minimum**:
- CPU: 4 cores
- RAM: 8 GB
- Disk: 20 GB free space
- Network: Local or LAN

**Recommended**:
- CPU: 8 cores
- RAM: 16 GB
- Disk: 50 GB SSD
- Network: Gigabit Ethernet

### Software Requirements

- **OS**: Windows 10/11 or Linux (Debian/Ubuntu)
- **Python**: 3.8+
- **MySQL**: 8.0+
- **Redis**: 6.0+
- **OpenSSL**: For certificate operations
- **Browsers**: Chrome, Firefox, Edge (latest versions)

### Network Configuration

- **Proxy**: Port 8001 (HTTPS with mutual TLS)
- **Main Server**: Port 8000 (HTTPS with mutual TLS for internal, HTTPS for portal)
- **Worker**: Connects to Redis and Main Server
- **Portal**: Port 8080 (HTTP/HTTPS)
- **Redis**: Port 6379
- **MySQL**: Port 3306

### Test Data

- **Test Users**: 5 users (3 regular, 2 admin)
- **Test Clients**: 10 client certificates
- **Test Messages**: 1000+ for functional tests, 100,000+ for load tests
- **Test Phone Numbers**: Valid E.164 format samples

---

## Test Categories

### 1. Functional Tests

#### 1.1 Proxy Server Tests
- [x] TC-P-001: Submit valid message
- [x] TC-P-002: Submit message with invalid phone number
- [x] TC-P-003: Submit message with invalid body length
- [x] TC-P-004: Submit without client certificate
- [x] TC-P-005: Submit with revoked certificate
- [x] TC-P-006: Health check endpoint
- [x] TC-P-007: Metrics endpoint
- [x] TC-P-008: Redis connection failure handling
- [x] TC-P-009: Main server connection failure handling
- [x] TC-P-010: Concurrent message submission

#### 1.2 Main Server Tests
- [x] TC-M-001: Register message (internal API)
- [x] TC-M-002: Deliver message (internal API)
- [x] TC-M-003: Update message status (internal API)
- [x] TC-M-004: User login (portal API)
- [x] TC-M-005: Token refresh (portal API)
- [x] TC-M-006: Get messages (portal API)
- [x] TC-M-007: Get profile (portal API)
- [x] TC-M-008: Create user (admin API)
- [x] TC-M-009: Generate certificate (admin API)
- [x] TC-M-010: Revoke certificate (admin API)
- [x] TC-M-011: Get statistics (admin API)
- [x] TC-M-012: Health check
- [x] TC-M-013: Database encryption/decryption
- [x] TC-M-014: Phone number hashing
- [x] TC-M-015: Role-based access control

#### 1.3 Worker Tests
- [x] TC-W-001: Process single message
- [x] TC-W-002: Retry failed delivery
- [x] TC-W-003: Update status on success
- [x] TC-W-004: Update status on failure
- [x] TC-W-005: Concurrent message processing
- [x] TC-W-006: Graceful shutdown
- [x] TC-W-007: Redis connection recovery
- [x] TC-W-008: Main server connection recovery
- [x] TC-W-009: Max attempts handling
- [x] TC-W-010: Queue empty handling

#### 1.4 Portal Tests
- [x] TC-PT-001: User login success
- [x] TC-PT-002: User login failure
- [x] TC-PT-003: User logout
- [x] TC-PT-004: Session expiration
- [x] TC-PT-005: View user messages
- [x] TC-PT-006: Filter messages by status
- [x] TC-PT-007: Pagination
- [x] TC-PT-008: View profile
- [x] TC-PT-009: Admin dashboard access
- [x] TC-PT-010: Admin create user
- [x] TC-PT-011: Admin generate certificate
- [x] TC-PT-012: Admin revoke certificate
- [x] TC-PT-013: Admin view all messages
- [x] TC-PT-014: Non-admin cannot access admin pages
- [x] TC-PT-015: Responsive design (mobile/desktop)

### 2. Integration Tests

#### 2.1 End-to-End Message Flow
- [x] TC-I-001: Complete message delivery flow
- [x] TC-I-002: Message retry flow
- [x] TC-I-003: Multiple concurrent flows
- [x] TC-I-004: Database persistence throughout flow
- [x] TC-I-005: Status transitions (queued → delivered)

#### 2.2 Authentication Flow
- [x] TC-I-006: Certificate generation → usage → revocation
- [x] TC-I-007: User creation → login → API access
- [x] TC-I-008: JWT token lifecycle
- [x] TC-I-009: Session management across requests

#### 2.3 Component Integration
- [x] TC-I-010: Proxy → Main Server communication
- [x] TC-I-011: Worker → Main Server communication
- [x] TC-I-012: Portal → Main Server communication
- [x] TC-I-013: All components → Redis
- [x] TC-I-014: All components → MySQL

### 3. Load Tests

#### 3.1 Throughput Tests
- [x] TC-L-001: Sustained 1 msg/sec for 1 hour
- [x] TC-L-002: Sustained 10 msg/sec for 10 minutes
- [x] TC-L-003: Burst 100 msg/sec for 1 minute
- [x] TC-L-004: Daily target (100,000 messages over 24 hours)
- [x] TC-L-005: Queue growth under load
- [x] TC-L-006: Worker processing under load
- [x] TC-L-007: Database performance under load

#### 3.2 Concurrency Tests
- [x] TC-L-008: Multiple proxy instances
- [x] TC-L-009: Multiple worker instances
- [x] TC-L-010: Concurrent portal users
- [x] TC-L-011: Concurrent database connections

### 4. Security Tests

#### 4.1 Authentication Tests
- [x] TC-S-001: Mutual TLS enforcement (proxy)
- [x] TC-S-002: Mutual TLS enforcement (worker → main server)
- [x] TC-S-003: Invalid certificate rejection
- [x] TC-S-004: Expired certificate rejection
- [x] TC-S-005: Revoked certificate rejection
- [x] TC-S-006: JWT token validation
- [x] TC-S-007: Invalid JWT token rejection
- [x] TC-S-008: Expired JWT token handling

#### 4.2 Encryption Tests
- [x] TC-S-009: Message body encryption at rest
- [x] TC-S-010: Message body decryption
- [x] TC-S-011: Phone number hashing
- [x] TC-S-012: Password hashing (bcrypt)
- [x] TC-S-013: Session encryption

#### 4.3 Access Control Tests
- [x] TC-S-014: User can only access own messages
- [x] TC-S-015: Admin can access all messages
- [x] TC-S-016: User cannot access admin pages
- [x] TC-S-017: Unauthenticated access rejection

### 5. Regression Tests

#### 5.1 Bug Fix Verification
- [x] TC-R-001: All reported bugs are fixed
- [x] TC-R-002: Fixes don't break existing functionality
- [x] TC-R-003: Critical path tests pass

#### 5.2 Configuration Changes
- [x] TC-R-004: Environment variable changes
- [x] TC-R-005: Port changes
- [x] TC-R-006: Database configuration changes

---

## Test Schedule

### Week 1: Functional Testing
- **Day 1-2**: Proxy server tests
- **Day 3-4**: Main server tests
- **Day 5**: Worker tests

### Week 2: Integration & Portal Testing
- **Day 1-2**: Integration tests
- **Day 3-4**: Portal tests
- **Day 5**: End-to-end workflows

### Week 3: Load & Security Testing
- **Day 1-2**: Load tests
- **Day 3-4**: Security tests
- **Day 5**: Regression tests

### Week 4: Bug Fixes & Retesting
- **Day 1-3**: Fix identified bugs
- **Day 4-5**: Retest and final verification

---

## Success Criteria

### Functional Testing
- ✅ 100% of critical test cases pass
- ✅ 95%+ of all test cases pass
- ✅ All blocking bugs fixed
- ✅ All critical bugs fixed

### Integration Testing
- ✅ End-to-end message flow works correctly
- ✅ All component integrations verified
- ✅ No data loss in the pipeline
- ✅ Status updates propagate correctly

### Load Testing
- ✅ System handles 100,000 messages/day
- ✅ No message loss under load
- ✅ Queue remains manageable
- ✅ Response times within acceptable limits (<5 seconds)

### Security Testing
- ✅ Mutual TLS enforced on all internal APIs
- ✅ Messages encrypted at rest
- ✅ No plain text passwords in database
- ✅ Role-based access control working
- ✅ Revoked certificates rejected

### Overall
- ✅ All test categories completed
- ✅ Test report documenting results
- ✅ Bug list with resolutions
- ✅ Stakeholder signoff

---

## Test Execution

### Prerequisites

1. All components installed and configured
2. Database initialized with schema
3. Certificates generated (CA, server, workers, clients)
4. Test users created
5. Test data prepared

### Execution Order

1. **Setup**: Initialize test environment
2. **Smoke Test**: Verify basic functionality
3. **Functional Tests**: Execute component tests
4. **Integration Tests**: Execute integration scenarios
5. **Load Tests**: Execute performance tests
6. **Security Tests**: Execute security verification
7. **Regression Tests**: Verify fixes
8. **Cleanup**: Clean up test data

### Test Execution Scripts

- `run_all_tests.ps1`: Execute all test suites
- `run_functional_tests.ps1`: Functional tests only
- `run_integration_tests.ps1`: Integration tests only
- `run_load_tests.ps1`: Load tests only
- `run_security_tests.ps1`: Security tests only

### Test Reporting

- Test execution logs in `tests/logs/`
- Test results in `tests/results/`
- Bug reports in `tests/bugs/`
- Final test report in `tests/TEST_REPORT.md`

---

## Defect Management

### Bug Severity Levels

- **Critical**: System crash, data loss, security breach
- **High**: Major functionality broken
- **Medium**: Minor functionality broken, workaround exists
- **Low**: Cosmetic issues, nice-to-have features

### Bug Tracking

All bugs documented in `tests/BUGS.md` with:
- Bug ID
- Severity
- Component
- Description
- Steps to reproduce
- Expected vs actual behavior
- Resolution
- Verification

### Resolution Timeline

- **Critical**: Fix immediately, retest before proceeding
- **High**: Fix within 1 day
- **Medium**: Fix within 3 days
- **Low**: Fix before final release or defer

---

## Sign-off

### Test Completion Criteria

- [ ] All test cases executed
- [ ] Test results documented
- [ ] All critical and high bugs fixed
- [ ] All medium bugs fixed or documented
- [ ] Test report completed
- [ ] Stakeholder review completed

### Approvals

- **QA Lead**: _____________________ Date: _____
- **Tech Lead**: _____________________ Date: _____
- **Project Manager**: _____________________ Date: _____
- **Stakeholder**: _____________________ Date: _____

---

## Appendices

### A. Test Data Samples

**Valid Phone Numbers** (E.164):
- +4915200000000
- +4915211111111
- +1234567890123

**Invalid Phone Numbers**:
- 123456789 (no +)
- +abc123 (letters)
- +123 (too short)

**Valid Message Bodies**:
- "Test message"
- "A" * 1000 (max length)

**Invalid Message Bodies**:
- "" (empty)
- "A" * 1001 (too long)

### B. Test User Accounts

**Users**:
- user1@example.com (role: user)
- user2@example.com (role: user)
- user3@example.com (role: user)
- admin1@example.com (role: admin)
- admin2@example.com (role: admin)

All passwords: `TestPassword123!`

### C. Test Client Certificates

**Clients**:
- test_client_1
- test_client_2
- test_client_3
- test_client_revoked (for revocation tests)

### D. References

- `DESIGN.md` - System architecture
- `API_SPECIFICATION.md` - API documentation
- Component READMEs in respective directories
- `plan.md` - Project plan with phases

---

**Document End**

