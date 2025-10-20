
Perfect — below is the **unified developer checklist for Windows environment**, containing:
✅ Full implementation roadmap (proxy + worker + main server + portal)
✅ Exact file names and folder layout
✅ Real-time monitoring (Prometheus + Grafana)
✅ Authentication (JWT + FastAPI Users)
✅ Command examples adapted for **Windows 10/11 with Python 3.12 + MySQL + Redis + Grafana**

---

# 🧭 Unified Developer Implementation Checklist (Windows Environment)

## 📁 0. Folder Structure

```
project_root/
│
├── proxy/
│   ├── app.py
│   ├── config.yaml
│   ├── certs/
│   │   ├── ca.crt
│   │   ├── proxy.key
│   │   └── proxy.crt
│   └── requirements.txt
│
├── main_server/
│   ├── api.py
│   ├── models.py
│   ├── database.py
│   ├── certs/
│   │   ├── ca.crt
│   │   ├── server.key
│   │   └── server.crt
│   ├── generate_cert.bat
│   ├── revoke_cert.bat
│   ├── crl/
│   │   └── revoked.pem
│   └── requirements.txt
│
├── worker/
│   ├── worker.py
│   ├── config.yaml
│   ├── certs/
│   │   ├── ca.crt
│   │   ├── worker.key
│   │   └── worker.crt
│   └── requirements.txt
│
├── portal/
│   ├── app.py
│   ├── templates/
│   ├── static/
│   ├── requirements.txt
│   └── system_dashboard.json
│
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
│       ├── dashboards/
│       │   └── system_dashboard.json
│       └── datasources/
│           └── prometheus.yml
│
└── .env
```

---

## ⚙️ 1. Environment Setup (Windows)

```bash
# Run from PowerShell as Administrator
python -m venv venv
.\venv\Scripts\activate
pip install -r proxy/requirements.txt -r main_server/requirements.txt -r worker/requirements.txt -r portal/requirements.txt
choco install redis mysql prometheus grafana -y
```

### MySQL

```bash
mysql -u root -p
CREATE DATABASE message_system CHARACTER SET utf8mb4;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
```

### Redis (Windows Service)

```bash
redis-server --service-install redis.windows.conf
redis-server --service-start
```

---

## 🔐 2. Certificate Management (OpenSSL for Windows)

In `main_server/certs`:

```bash
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=MainCA"
```

### Client/Proxy/Worker Certs

Use batch files:
**generate_cert.bat**

```bat
@echo off
set CN=%1
openssl genrsa -out %CN%.key 2048
openssl req -new -key %CN%.key -out %CN%.csr -subj "/CN=%CN%"
openssl x509 -req -in %CN%.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out %CN%.crt -days 365 -sha256
```

**revoke_cert.bat**

```bat
@echo off
set CN=%1
echo %CN% >> crl\revoked.pem
```

---

## 🧱 3. Proxy Service (`proxy/app.py`)

**Purpose:**
Accept JSON payloads → Validate sender number → Enqueue in Redis →
Send record to main_server `/register` endpoint over mutual TLS.

**Example run command:**

```bash
uvicorn proxy.app:app --host 0.0.0.0 --port 8001 --ssl-keyfile certs/proxy.key --ssl-certfile certs/proxy.crt --ssl-ca-certs certs/ca.crt
```

**Test POST Example:**

```bash
curl -X POST https://localhost:8001/submit \
 -H "Content-Type: application/json" \
 -d "{\"sender_number\": \"+4915200000000\", \"message_body\": \"Test message\"}" \
 --cert proxy/certs/proxy.crt --key proxy/certs/proxy.key --cacert proxy/certs/ca.crt
```

---

## 🖥️ 4. Main Server (`main_server/api.py`)

**Endpoints:**

* `/register` – store message in MySQL (AES-256 encryption)
* `/status_update` – update delivery status
* `/generate_cert` – issue client certificates
* `/revoke_cert` – mark revoked certificates

**Run:**

```bash
uvicorn main_server.api:app --port 8000 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt --ssl-ca-certs certs/ca.crt
```

---

## ⚙️ 5. Worker (`worker/worker.py`)

**Task:**
Continuously consume Redis queue → send payloads to main server via HTTPS (Mutual TLS) → retry every 30 seconds until success.

```bash
python worker/worker.py
```

Add Windows Task Scheduler entry:

```
Program: python.exe
Args: "C:\project_root\worker\worker.py"
Trigger: At system startup
```

---

## 🧩 6. Portal (`portal/app.py`)

**Purpose:**
View/search/filter messages (no edit/export).
JWT + FastAPI Users authentication.
HTTPS enabled (TLS only, no mutual auth).

```bash
uvicorn portal.app:app --port 8080 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

Admin credentials stored in `.env`:

```
ADMIN_USER=admin@example.com
ADMIN_PASS=AdminPass123!
JWT_SECRET=SuperSecretJWTKey
```

---

## 📈 7. Real-Time Monitoring (Prometheus + Grafana)

**Prometheus config (`monitoring/prometheus.yml`):**

```yaml
global:
  scrape_interval: 10s
scrape_configs:
  - job_name: 'fastapi_proxy'
    static_configs:
      - targets: ['localhost:8001']
  - job_name: 'fastapi_main_server'
    static_configs:
      - targets: ['localhost:8000']
  - job_name: 'worker_metrics'
    static_configs:
      - targets: ['localhost:9100']
```

**Grafana setup (Windows service):**

```bash
net start grafana
```

Open [http://localhost:3000](http://localhost:3000) → Import dashboard:
`portal/system_dashboard.json`

**`system_dashboard.json`** includes panels for:

* Request rate per endpoint
* Queue size over time
* Worker success/failure counts
* Average response latency

---

## 🔍 8. Manual Test Plan

1. Run all services (`main_server`, `proxy`, `worker`, `portal`).
2. `curl` POST messages → Verify queue in Redis.
3. Confirm message appears in MySQL (`SELECT * FROM messages;`).
4. Stop worker → Re-start after 1 min → Confirm retry logic.
5. Revoke proxy cert → Ensure access denied next call.
6. Login to portal → Search for sender number → Verify result display.
7. View Grafana dashboard → Confirm metrics visible.

---

## 🔒 9. Security & Maintenance Notes

* AES-256 key stored at: `C:\app_secrets\aes.key` (chmod 600 equivalent: restrict NTFS to Administrators only).
* CRL checked on each TLS handshake in `main_server/api.py`.
* Add Windows `Task Scheduler` for weekly backup of MySQL & Redis AOF.
* Log rotation via `loguru` or PowerShell script to keep 7 days of logs.

---

## ✅ 10. Final Deliverables

| Component   | File(s)                                                         | Output                           |
| ----------- | --------------------------------------------------------------- | -------------------------------- |
| Proxy       | `proxy/app.py`                                                | Receives and enqueues messages   |
| Main Server | `main_server/api.py`                                          | Stores messages & manages certs  |
| Worker      | `worker/worker.py`                                            | Dispatches messages with retries |
| Portal      | `portal/app.py`                                               | Displays messages (JWT secured)  |
| Monitoring  | `monitoring/prometheus.yml`, `portal/system_dashboard.json` | Real-time system metrics         |

---

Would you like me to generate the **ready-to-use `system_dashboard.json` template** (Prometheus + Grafana panels) so you can import it directly?
