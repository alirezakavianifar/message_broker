# Message Broker System

A secure, scalable message broker system with mutual TLS authentication, persistent queuing, and real-time monitoring. Built for handling high-volume message processing with Redis queuing, MySQL persistence, and comprehensive monitoring via Prometheus and Grafana.

## 🏗️ Architecture

```
Client → Proxy (FastAPI) → Redis Queue → Workers → Main Server (FastAPI) → MySQL
                                                         ↓
                                                   Web Portal
```

**Key Components:**
- **Proxy Server**: Receives messages via mutual TLS, validates, and enqueues
- **Main Server**: Certificate authority, message persistence, and API management
- **Workers**: Consume queue and deliver messages with retry logic
- **Web Portal**: User and admin interface for message viewing and management
- **Monitoring**: Prometheus + Grafana for real-time system metrics

## 📋 Prerequisites

### Required Software (Windows 10/11)
- Python 3.12 or higher
- MySQL 8.0+
- Redis 7.0+
- OpenSSL (for certificate generation)
- Git
- Chocolatey (recommended for package management)

### Optional
- Prometheus & Grafana (for monitoring)

## 🚀 Quick Start

### 1. Clone and Setup Environment

```powershell
# Clone the repository
git clone <repository-url>
cd message_broker

# Create virtual environment
python -m venv venv
.\venv\Scripts\activate

# Install dependencies
pip install -r proxy/requirements.txt
pip install -r main_server/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### 2. Install System Dependencies

Using Chocolatey (run PowerShell as Administrator):

```powershell
choco install mysql redis openssl -y
```

Or install manually:
- MySQL: https://dev.mysql.com/downloads/installer/
- Redis: https://github.com/microsoftarchive/redis/releases
- OpenSSL: https://slproweb.com/products/Win32OpenSSL.html

### 3. Configure MySQL

```powershell
# Start MySQL service
net start MySQL80

# Create database and user
mysql -u root -p
```

```sql
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 4. Configure Redis

```powershell
# Install Redis as Windows service
redis-server --service-install
redis-server --service-start

# Verify Redis is running
redis-cli ping
# Expected output: PONG
```

### 5. Environment Configuration

Copy the template and configure:

```powershell
copy env.template .env
```

Edit `.env` file with your configuration (database credentials, paths, etc.)

### 6. Generate Certificates

Navigate to main_server and generate CA and certificates:

```powershell
cd main_server/certs

# Generate CA (Certificate Authority)
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=MessageBrokerCA"

# Generate server certificate
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -subj "/CN=localhost"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -sha256

# Generate proxy certificate
openssl genrsa -out proxy.key 2048
openssl req -new -key proxy.key -out proxy.csr -subj "/CN=proxy"
openssl x509 -req -in proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out proxy.crt -days 365 -sha256

# Generate worker certificate
openssl genrsa -out worker.key 2048
openssl req -new -key worker.key -out worker.csr -subj "/CN=worker"
openssl x509 -req -in worker.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out worker.crt -days 365 -sha256

cd ../..
```

Copy certificates to appropriate directories:

```powershell
# Copy to proxy
copy main_server\certs\ca.crt proxy\certs\
copy main_server\certs\proxy.key proxy\certs\
copy main_server\certs\proxy.crt proxy\certs\

# Copy to worker
copy main_server\certs\ca.crt worker\certs\
copy main_server\certs\worker.key worker\certs\
copy main_server\certs\worker.crt worker\certs\
```

### 7. Create AES Encryption Key

```powershell
# Create secrets directory
New-Item -ItemType Directory -Path "C:\app_secrets" -Force

# Generate AES key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" > C:\app_secrets\aes.key

# Set permissions (restrict to Administrators only)
icacls "C:\app_secrets" /inheritance:r
icacls "C:\app_secrets" /grant:r "Administrators:F"
```

## 🎯 Running the System

### Start Services (in separate terminals)

**Terminal 1 - Main Server:**
```powershell
.\venv\Scripts\activate
cd main_server
uvicorn api:app --host 0.0.0.0 --port 8000 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt --ssl-ca-certs certs/ca.crt
```

**Terminal 2 - Proxy Server:**
```powershell
.\venv\Scripts\activate
cd proxy
uvicorn app:app --host 0.0.0.0 --port 8001 --ssl-keyfile certs/proxy.key --ssl-certfile certs/proxy.crt --ssl-ca-certs certs/ca.crt
```

**Terminal 3 - Worker:**
```powershell
.\venv\Scripts\activate
cd worker
python worker.py
```

**Terminal 4 - Portal:**
```powershell
.\venv\Scripts\activate
cd portal
uvicorn app:app --host 0.0.0.0 --port 8080 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt
```

### Health Checks

```powershell
# Check proxy (requires client cert)
curl -X GET https://localhost:8001/health --cert proxy/certs/proxy.crt --key proxy/certs/proxy.key --cacert proxy/certs/ca.crt

# Check main server
curl -k -X GET https://localhost:8000/health

# Check portal
curl -k -X GET https://localhost:8080/
```

## 📦 Project Structure

```
message_broker/
├── proxy/                      # Proxy server (message ingestion)
│   ├── app.py                 # FastAPI application
│   ├── config.yaml            # Configuration
│   ├── certs/                 # TLS certificates
│   └── requirements.txt
│
├── main_server/               # Main server (persistence & CA)
│   ├── api.py                 # FastAPI application
│   ├── models.py              # Database models
│   ├── database.py            # Database connection
│   ├── certs/                 # TLS certificates & CA
│   ├── crl/                   # Certificate revocation list
│   └── requirements.txt
│
├── worker/                    # Message processor workers
│   ├── worker.py              # Worker implementation
│   ├── config.yaml            # Configuration
│   ├── certs/                 # TLS certificates
│   └── requirements.txt
│
├── portal/                    # Web portal
│   ├── app.py                 # FastAPI application
│   ├── templates/             # Jinja2 templates
│   ├── static/                # CSS, JS, images
│   └── requirements.txt
│
├── client-scripts/            # Example client scripts
│   ├── send_message.py        # Sample message sender
│   └── requirements.txt
│
├── monitoring/                # Monitoring configuration
│   ├── prometheus.yml         # Prometheus config
│   └── grafana/              # Grafana dashboards
│
├── infra/                     # Infrastructure scripts
│   ├── setup_windows.ps1      # Windows setup script
│   └── backup.ps1             # Backup script
│
├── env.template               # Environment variables template
├── .gitignore                # Git ignore rules
└── README.md                 # This file
```

## 🔒 Security Features

- **Mutual TLS Authentication**: Client ↔ Proxy ↔ Main Server
- **AES-256 Encryption**: Message bodies encrypted at rest
- **Hashed Sender Numbers**: Phone numbers hashed in database
- **JWT Authentication**: Portal user authentication
- **Certificate Revocation**: CRL support for compromised certificates
- **Secure Key Storage**: Restricted filesystem permissions

## 📊 Monitoring & Observability

### Prometheus Setup (Optional)

```powershell
# Download and install Prometheus
choco install prometheus -y

# Copy config
copy monitoring\prometheus.yml C:\ProgramData\chocolatey\lib\prometheus\tools\

# Start Prometheus
prometheus --config.file=C:\ProgramData\chocolatey\lib\prometheus\tools\prometheus.yml
```

Access Prometheus at: http://localhost:9090

### Grafana Setup (Optional)

```powershell
# Install Grafana
choco install grafana -y

# Start Grafana service
net start grafana

# Access Grafana
# URL: http://localhost:3000
# Default credentials: admin / admin
```

Import dashboard from `monitoring/grafana/dashboards/system_dashboard.json`

## 🧪 Testing

### Send Test Message

```powershell
cd client-scripts
python send_message.py --sender "+1234567890" --message "Test message"
```

### Verify Message in Database

```sql
USE message_system;
SELECT id, client_id, sender_number_hashed, status, created_at FROM messages ORDER BY created_at DESC LIMIT 10;
```

### Check Redis Queue

```powershell
redis-cli
LLEN message_queue
LRANGE message_queue 0 -1
```

## 📝 Configuration Files

### Proxy Config (`proxy/config.yaml`)
- Redis connection settings
- TLS certificate paths
- Validation rules
- Rate limiting

### Worker Config (`worker/config.yaml`)
- Retry interval (default: 30 seconds)
- Max attempts (default: 10,000)
- Concurrency settings
- Main server endpoint

### Main Server Config
- Database connection
- Certificate management
- Encryption settings
- API rate limits

## 🔧 Development

### Code Standards
- Python 3.12+ with type hints
- PEP 8 style guide
- FastAPI best practices
- Comprehensive error handling
- Logging for all operations

### Branch Strategy
- `main` - Production-ready code
- `develop` - Integration branch
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `hotfix/*` - Emergency fixes

### Commit Convention
```
type(scope): brief description

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## 🐛 Troubleshooting

### Redis Connection Issues
```powershell
# Check Redis status
sc query Redis
# Restart Redis
redis-server --service-stop
redis-server --service-start
```

### MySQL Connection Issues
```powershell
# Check MySQL status
sc query MySQL80
# Check port
netstat -ano | findstr :3306
```

### Certificate Issues
- Verify certificate paths in `.env`
- Check certificate validity: `openssl x509 -in cert.crt -text -noout`
- Ensure CA certificate is accessible to all services

### Worker Not Processing Messages
- Check Redis queue: `redis-cli LLEN message_queue`
- Verify worker logs in `logs/worker.log`
- Confirm main server is accessible
- Validate worker certificate

## 📚 Additional Resources

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Redis Documentation](https://redis.io/documentation)
- [MySQL Documentation](https://dev.mysql.com/doc/)
- [OpenSSL Documentation](https://www.openssl.org/docs/)

## 🤝 Contributing

1. Create a feature branch from `develop`
2. Make your changes with appropriate tests
3. Ensure code follows project standards
4. Submit pull request with detailed description

## 📄 License

[Specify your license here]

## 👥 Support

For issues and questions:
- Create an issue in the repository
- Contact the development team
- Refer to project documentation in `docs/`

---

**Version**: 1.0.0
**Last Updated**: October 2025

