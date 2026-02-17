# Implementation Plan - Dockerization of Message Broker App

This plan outlines the steps to containerize the Message Broker application, allowing it to run as a set of Docker containers that can be deployed on a single machine (using `docker-compose`) or across separate servers.

## User Review Required

> [!IMPORTANT]
> **Environment Variables**: The current services rely on `.env` files and environment variables. For multi-server deployment, you must ensure that each server's environment is correctly configured with the IP/hostname of the other services (e.g., `MAIN_SERVER_URL` on the proxy server should point to the main server's IP).

> [!WARNING]
> **Certificates**: Mutual TLS is used between services. You will need to manage the distribution of certificates (`ca.crt`, `server.crt/key`, `client.crt/key`) across the separate servers. I will provide a way to mount these as volumes.

## Proposed Changes

### Docker Infrastructure

#### [NEW] [Dockerfile](file:///e:/projects/from-old-pc/message_broker/main_server/Dockerfile)
#### [NEW] [Dockerfile](file:///e:/projects/from-old-pc/message_broker/portal/Dockerfile)
#### [NEW] [Dockerfile](file:///e:/projects/from-old-pc/message_broker/proxy/Dockerfile)
#### [NEW] [Dockerfile](file:///e:/projects/from-old-pc/message_broker/worker/Dockerfile)
Create standard Python-based Dockerfiles for each service, fulfilling their specific requirements (FastAPI, Redis, etc.).

#### [NEW] [docker-compose.yml](file:///e:/projects/from-old-pc/message_broker/docker-compose.yml)
Create a root-level compose file for local development and single-server deployment. It will include:
- `db` (MySQL)
- `redis`
- `main_server`
- `portal`
- `proxy`
- `worker`

### Configuration and Scripting

#### [MODIFY] [.env](file:///e:/projects/from-old-pc/message_broker/.env)
Update `.env.template` (and `.env`) to include Docker-friendly defaults (e.g., `DB_HOST=db` instead of `localhost` when running in Compose).

#### [NEW] [docker-entrypoint.sh](file:///e:/projects/from-old-pc/message_broker/main_server/docker-entrypoint.sh)
A script to handle database migrations (Alembic) before starting the server.

---

## Multi-Server Deployment Strategy

To run services on separate servers:

1.  **Build and Push**: Build images for each service and push them to a private Docker registry (e.g., Docker Hub, AWS ECR, or a local registry).
2.  **Configuration**:
    - **Server A (Database & Redis)**: Run MySQL and Redis containers.
    - **Server B (Main Server)**: Run the `main_server` image, pointing `DB_HOST` and `REDIS_HOST` to Server A's IP.
    - **Server C (Proxy)**: Run the `proxy` image, pointing `MAIN_SERVER_URL` and `REDIS_HOST` to Server B and Server A respectively.
    - **Server D (Portal)**: Run the `portal` image, pointing `MAIN_SERVER_URL` to Server B.
    - **Server E (Worker)**: Run one or more `worker` containers, pointing `MAIN_SERVER_URL` and `REDIS_HOST` to Server B and Server A.
3.  **Networking**: Ensure ports 3306, 6379, 8000, 8001, and 8080 are accessible between servers according to their communication needs.
4.  **Volumes**: Use Docker volumes or bind mounts on each server to provide the necessary certificates and logs.

## Verification Plan

### Automated Tests
- Run `docker-compose up -d` locally.
- Use existing test scripts:
    - [test_server.py](file:///e:/projects/from-old-pc/message_broker/main_server/test_server.py)
    - [test_message_broker.py](file:///e:/projects/from-old-pc/message_broker/test_message_broker.py)
- Verify that each service's `/health` (or equivalent) endpoint returns 200.

### Manual Verification
- Log in to the Portal at `http://localhost:8080`.
- Send a test message via the Proxy at `https://localhost:8001/api/v1/messages`.
- Verify the message appears in the Portal and is processed by the Worker.
