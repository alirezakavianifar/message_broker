Below is a clear, step-by-step deliverable plan (phases, tasks, artifacts, and acceptance criteria) based on the original specification and the employer's answers. It assumes: FastAPI backend, Redis queue (persistent), MySQL, Mutual TLS for client → proxy → main-server traffic, Python client script, Windows Server, no Docker, manual testing only, web portal (user + admin), and certificate issuance on the main server via OpenSSL.

---

# Deliverable Plan — Client → Proxy → Main Server (Queue + Workers)

## Phase 0 — Project setup & kickoff

1. **Task:** Create project repository layout and onboarding docs.
   **Artifacts:** Git repo skeleton (backend, workers, client-scripts, web-portal, infra), `README` with setup instructions, coding standards, branch strategy.
   **Acceptance:** Repo exists, instructions to set up a local dev environment on Windows workstations are validated.

---

## Phase 1 — Requirements consolidation & design (deliverable: design doc)

1. **Task:** Produce a short design document describing data flow, components, and configuration driven by domain names (multi-domain support). Include chosen tech stack and rationale (FastAPI, Redis with AOF persistence, MySQL, React/Bootstrap or plain Bootstrap).
2. **Task:** Define message JSON schema (default format):

   ```json
   {
     "sender_number": "+XXXXXXXXXXX",
     "message_body": "string",
     "metadata": { "client_id": "string", "timestamp": "ISO8601" }
   }
   ```
3. **Task:** Define authentication model: Mutual TLS for client→proxy and proxy→main-server; portal uses username/password over HTTPS (TLS). Certificate issuance process specified (OpenSSL on main server, per-client cert).
4. **Artifacts:** Design doc (data formats, sequence diagrams, certificate lifecycle steps, queue choice and persistence settings, scaling notes for up to ~100k msgs/day).
5. **Acceptance:** Stakeholder signoff on design doc.

---

## Phase 2 — API & DB specification (deliverable: API + DB spec)

1. **Task:** Produce OpenAPI/Swagger draft for proxy REST API endpoints (documented). Basic endpoints:

   * `POST /api/v1/messages` — client submits message (mutual TLS required)
   * `GET /api/v1/health` — health check for proxy (no auth or cert-based)
   * Admin endpoints for certificate management (only via main server) — described but implemented on main server side.
2. **Task:** Draft MySQL schema (minimal, privacy-oriented):

   * `users` (admin/portal users)
   * `messages` (id, client_id, encrypted_body, sender_number_hashed, status, created_at, queued_at, delivered_at, attempt_count)
   * `clients` (client_id, cert_fingerprint, domain)
3. **Task:** Define message encryption at rest: AES-256 symmetric encryption of `message_body` before storing; key stored on server (guideline for key management).
4. **Artifacts:** OpenAPI spec file, SQL DDL, encryption design notes.
5. **Acceptance:** API spec renders in Swagger UI; DB schema reviewed.

---

## Phase 3 — Certificate issuance & auth workflow (deliverable: cert tools + docs)

1. **Task:** Implement OpenSSL scripts for: CA creation (if required), per-client certificate generation, certificate revocation list (CRL) process, and simple renewal instructions. The main server will host scripts and instructions.
2. **Artifacts:** `generate_cert.ps1`, `generate_cert.bat`, `revoke_cert.bat`, README for issuing and installing certs.
3. **Acceptance:** Demonstrate generating a client cert and mutual TLS handshake success in local test.

---

## Phase 4 — Proxy server implementation (deliverable: proxy service)

1. **Task:** FastAPI app implementing:

   * `POST /api/v1/messages` (mutual TLS enforcement)
   * client certificate fingerprint extraction and mapping to `client_id`
   * basic validation: `sender_number` format validation per requirement
   * enqueue validated message into Redis (persisted) and create initial DB record in main server DB (or alternative: proxy stores in DB of final server via authenticated call — employer stated “proxy will put in queue and record in main server DB”, so implement proxy to enqueue and also call main server DB API to register the message record, OR the worker will persist on successful delivery — implement DB insert at enqueue time by proxy calling main server internal API using mutual TLS)
2. **Task:** Implement logging: minimal logs: message queued time, message persisted, user last login events (portal side), and errors. Logging goes to a daily rotating file.
3. **Artifacts:** FastAPI app, Swagger UI endpoint, config files (TLS cert paths, Redis/MYSQL connection config), PowerShell startup scripts and Windows Service configuration files.
4. **Acceptance:** Client script can POST a message; proxy validates and enqueues; message row exists in MySQL (encrypted body) and Swagger is available.

---

## Phase 5 — Redis queue & Worker implementation (deliverable: workers)

1. **Task:** Implement Redis-based queue using Redis lists or Redis Streams with AOF persistence; implement worker(s) in Python that:

   * pop message from queue atomically
   * attempt deliver to main server HTTP endpoint (mutual TLS)
   * on success: update message status to `delivered_at` in MySQL via main server API
   * on failure: increment attempt_count, re-queue or leave in queue, and retry every 30s as requested. (Because employer asked for fixed 30s retry, worker will sleep 30s before reattempt; no exponential backoff.)
   * support multiple concurrent worker processes (via configuration) and safe concurrent consumption (use Redis atomic operations / consumer groups if Streams used).
2. **Task:** Provide configuration param to set retry interval (default 30s) and max attempts (configurable; e.g. 10000 or unlimited if desired). Employer said keep in queue until delivered. Implement ability to keep indefinitely (but track attempts).
3. **Artifacts:** Worker code, PowerShell startup script for worker(s), batch files for starting workers, configuration sample, concurrency instructions.
4. **Acceptance:** With multiple workers running, messages are delivered and DB updated on success; failed deliveries are retried every 30s until success.

---

## Phase 6 — Main server implementation (deliverable: main server API + DB)

1. **Task:** Implement main server FastAPI endpoints:

   * `POST /internal/messages/register` — (mutual TLS, called by proxy) to create message record in MySQL (encrypted) when proxy enqueues (if chosen design).
   * `POST /internal/messages/deliver` — endpoint worker calls to mark delivered (or worker directly updates DB if mutual TLS + DB access is allowed).
   * internal health and certificate management endpoints (admin only).
2. **Task:** Implement MySQL migrations and encryption/decryption helpers. Store only encrypted message bodies; optionally store hash of sender_number for search/filtering without storing raw number in plain text.
3. **Artifacts:** Main server app, DB migration scripts, admin CLI for certificate revocation listing.
4. **Acceptance:** Proxy & workers can successfully create and update records in the main server DB via mutual TLS authenticated calls.

---

## Phase 7 — Web portal (deliverable: user + admin portal)

1. **Task:** Build a simple web portal (React + Bootstrap or server-side HTML+Bootstrap per preference):

   * **User panel:** login (username/password), view own messages only, search & filter by date/status, minimal metadata (message timestamp, status). Message bodies stored encrypted; when user requests their own message, portal obtains decrypted body server-side (authorization check).
   * **Admin panel:** manage users, view messages across clients, manage DB (basic tools for maintenance), manage user accounts, view last login times. No edit/export required (employer said no).
2. **Security:** Portal served over HTTPS (TLS). Portal auth separate from client certs. Admin access limited by roles.
3. **Artifacts:** Portal source, build steps, IIS or self-hosted configuration for Windows, credentials bootstrap doc.
4. **Acceptance:** User can login and see only their messages; admin can manage users and view messages.

---

## Phase 8 — Testing & QA (deliverable: test report)

1. **Task:** Manual test plan and execution:

   * Functional tests: sending message from client script, validation failures (bad number), mutual TLS failure, queue enqueue, worker delivery, DB persistence, portal auth and message visibility.
   * Load sanity test: enqueue up to a simulated burst and verify system handles sustained ~100k/day (~1–2 msgs/sec average). (Note: no automated tests required as per employer; provide documented manual tests and result logs.)
   * Security checks: verify mutual TLS is enforced and messages encrypted at rest.
2. **Artifacts:** Test checklist and test execution report, list of bugs found & fixed, final signoff.
3. **Acceptance:** All critical and high bugs fixed; system works in manual regression steps; stakeholder confirms “bugs fixed and program works without problems.”

---

## Phase 9 — Deployment & handover (deliverable: running test server + deployment guide)

1. **Task:** Prepare deployment scripts for Windows Server (no Docker):

   * PowerShell scripts and batch files for proxy, workers, main server, and portal; Windows Service configuration or scheduled tasks; IIS or self-hosted configuration for portal; TLS certificate placement instructions.
   * DB setup instructions, secure MySQL connection (bind, user config).
   * Redis config for AOF persistence enabled and recommended maxmemory policy.
2. **Task:** Deploy to a test Windows Server (provided domain name), configure domains as requested (parameterize domain so same code works for multiple domains).
3. **Task:** Provide backup and restore instructions for MySQL and Redis.
4. **Artifacts:** Deployment guide (step-by-step), PowerShell scripts, batch files, Windows Service setup instructions, IIS config snippets (if applicable), production config examples.
5. **Acceptance:** System deployed on test server reachable via given domains; mutual TLS handshake proven with a client cert; portal accessible over HTTPS; stakeholders can run a demo.

---

## Phase 10 — Documentation, training & final delivery (deliverable: final package)

1. **Task:** Provide developer & admin documentation: architecture overview, API docs (Swagger/OpenAPI), DB schema, certificate issuance/revocation guide, runbook for starting/stopping services, log locations, and how to add domains & clients.
2. **Task:** Final code delivery: push all code to repo, tag release, include test report. Provide credentials and instructions for the test server.
3. **Artifacts:** Final source code, Swagger doc, deployment/runbook, test report, certificate scripts, sample client script.
4. **Acceptance:** Employer confirms receipt, verifies major flows (send message → queued → delivered → appears in portal) and signs off for payment.

---

## Operational & non-functional considerations included

* **Message format:** Default JSON as above (per employer “any format ok”; we choose JSON). Client sends two variables: `sender_number` and `message_body`.
* **Retry strategy:** Fixed retry interval every **30 seconds** (no exponential backoff, per employer). Messages remain until delivered. Provide config option to change interval later.
* **Certificates:** Per-client certificates generated on main server with OpenSSL; CRL and revocation scripts included. Mutual TLS enforced both at proxy and worker→main-server calls.
* **Encryption at rest:** AES-256 encryption for message bodies; only decrypted server-side when authorized. Provide key-management note (store key with restricted permissions).
* **Queue choice:** Redis (with AOF) chosen for simplicity and adequate throughput for ~100k/day; design allows switching to RabbitMQ later if needed.
* **Scaling:** Support multi-worker concurrent processes; config-driven worker count. Design is domain-configurable so system can be deployed for multiple domains.
* **Logging:** Minimal logging only (queued/delivered timestamps, user last login). Logs rotated daily.
* **No Docker & no automated tests:** Implementation uses PowerShell scripts and Windows Services on Windows Server; testing is manual per employer request.
* **Admin web features:** DB & user management UI for admin; no export/edit features for messages (per employer).

---

## Final deliverables (summary)

* Full source code (proxy, workers, main server, portal) in Git.
* OpenAPI/Swagger documentation.
* MySQL DDL and migration scripts.
* Redis configuration recommendations (AOF enabled).
* Certificate generation and revocation scripts (`openssl` based - PowerShell and batch files).
* Client Python example script that posts messages (two variables).
* Deployment guide for Windows Server (PowerShell scripts, batch files, Windows Service setup, IIS configuration if applicable).
* Manual test plan and test report with sign-offs.
* Runbook and admin/user manuals.
* Demo instance on provided test server (configured per domain).

---

If you want, I can now transform the above deliverables into a checklist with command snippets and exact file names (e.g., `proxy/app.py`, `worker/worker.py`, `main_server/api.py`, `portal/`) so the developer can start implementing immediately. Which would you prefer next?
