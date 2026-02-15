# راهنمای راه‌اندازی سیستم کارگزار پیام

**نسخه**: 1.0.0  
**سیستم عامل**: ویندوز سرور / لینوکس  
**تاریخ**: نوامبر 2025

---

## فهرست مطالب

1. [معرفی سیستم](#معرفی-سیستم)
2. [پیش‌نیازها](#پیش-نیازها)
3. [راه‌اندازی در ویندوز](#راه-اندازی-در-ویندوز)
4. [راه‌اندازی در لینوکس](#راه-اندازی-در-لینوکس)
5. [پیکربندی](#پیکربندی)
6. [مدیریت گواهی‌نامه](#مدیریت-گواهی-نامه)
7. [اجرای سیستم](#اجرای-سیستم)
8. [مدیریت سرویس](#مدیریت-سرویس)
9. [عیب‌یابی](#عیب-یابی)

---

## معرفی سیستم

سیستم کارگزار پیام از 4 بخش اصلی تشکیل شده است:

- **سرور اصلی** (پورت 8000): رابط برنامه‌نویسی مرکزی، پایگاه داده، احراز هویت
- **سرور پروکسی** (پورت 8001): رابط برنامه‌نویسی سمت کلاینت با احراز هویت دوطرفه
- **کارگر** (Worker): پردازش پیام‌ها از صف Redis
- **پورتال وب** (پورت 5000): رابط وب برای مشاهده پیام‌ها

### معماری سیستم

```
کلاینت -> پروکسی (8001) -> صف Redis -> کارگر -> سرور اصلی (8000) -> MySQL
                                                          ↓
                                                     پورتال وب (5000)
```

---

## پیش‌نیازها

### نرم‌افزارهای مورد نیاز

**برای هر دو پلتفرم:**
- Python 3.8 یا بالاتر
- MySQL 8.0 یا بالاتر
- Redis 6.0 یا بالاتر (یا Memurai در ویندوز)
- OpenSSL 3.0 یا بالاتر

**ویندوز اضافی:**
- PowerShell 5.1 یا بالاتر

**لینوکس اضافی:**
- systemd (برای مدیریت سرویس)

### پورت‌های شبکه

- **8000**: سرور اصلی (HTTPS)
- **8001**: سرور پروکسی (HTTPS با احراز هویت دوطرفه)
- **5000**: پورتال وب (HTTP)
- **3306**: MySQL
- **6379**: Redis
- **9100+**: متریک‌های کارگر (اختیاری)

---

## راه‌اندازی در ویندوز

### مرحله 1: نصب وابستگی‌ها

#### روش اول: استفاده از Chocolatey (توصیه می‌شود)

```powershell
# نصب Chocolatey در صورت عدم وجود
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# نصب وابستگی‌ها
choco install mysql redis-64 openssl python3 -y
```

#### روش دوم: نصب دستی

1. دانلود و نصب MySQL 8.0 از سایت mysql.com
2. دانلود و نصب Memurai (سازگار با Redis) از سایت memurai.com
3. دانلود و نصب OpenSSL از سایت slproweb.com/products/Win32OpenSSL.html
4. دانلود و نصب Python 3.8 یا بالاتر از سایت python.org

### مرحله 2: راه‌اندازی پایگاه داده

```powershell
# راه‌اندازی MySQL
net start MySQL80

# ایجاد پایگاه داده
mysql -u root -p
```

```sql
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'YourStrongPassword123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### مرحله 3: راه‌اندازی محیط Python

```powershell
# رفتن به دایرکتوری پروژه
cd C:\MessageBroker

# ایجاد محیط مجازی
python -m venv venv

# فعال‌سازی محیط مجازی
.\venv\Scripts\Activate.ps1

# نصب وابستگی‌ها
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### مرحله 4: مقداردهی اولیه ساختار پایگاه داده

```powershell
cd main_server
alembic upgrade head
```

### مرحله 5: تولید گواهی‌نامه‌ها

```powershell
cd main_server

# مقداردهی اولیه مرجع گواهی
.\init_ca.bat

# تولید گواهی‌نامه‌های سرور
.\generate_cert.bat server
.\generate_cert.bat proxy
.\generate_cert.bat worker

# تولید گواهی‌نامه کلاینت تست
.\generate_cert.bat test_client
```

کپی گواهی‌نامه‌ها به دایرکتوری‌های مناسب:
- `proxy.crt` و `proxy.key` -> `proxy/certs/`
- `worker.crt` و `worker.key` -> `worker/certs/`
- کپی `ca.crt` به `proxy/certs/` و `worker/certs/`

### مرحله 6: ایجاد کاربر مدیر

```powershell
cd main_server
python admin_cli.py users create --email admin@example.com --password AdminPass123! --role admin
```

### مرحله 7: پیکربندی محیط

ایجاد فایل `.env` در ریشه پروژه:

```env
# پایگاه داده
DATABASE_URL=mysql+pymysql://systemuser:YourStrongPassword123!@localhost/message_system

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# رمزهای عبور (در محیط تولید حتما تغییر دهید!)
JWT_SECRET=your-production-secret-key-min-32-chars
HASH_SALT=your-production-salt-change-this

# سرور اصلی
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# لاگ
LOG_LEVEL=INFO
LOG_FILE_PATH=logs
```

---

## راه‌اندازی در لینوکس

### مرحله 1: نصب وابستگی‌ها

**اوبونتو/دبیان:**
```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv mysql-server redis-server openssl
```

**CentOS/RHEL:**
```bash
sudo yum install -y python3 python3-pip mysql-server redis openssl
```

### مرحله 2: راه‌اندازی پایگاه داده

```bash
# راه‌اندازی MySQL
sudo systemctl start mysql
sudo systemctl enable mysql

# امن‌سازی نصب MySQL
sudo mysql_secure_installation

# ایجاد پایگاه داده
sudo mysql -u root -p
```

```sql
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'YourStrongPassword123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### مرحله 3: راه‌اندازی محیط Python

```bash
# رفتن به دایرکتوری پروژه
cd /opt/message_broker

# ایجاد محیط مجازی
python3 -m venv venv

# فعال‌سازی محیط مجازی
source venv/bin/activate

# نصب وابستگی‌ها
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### مرحله 4: مقداردهی اولیه ساختار پایگاه داده

```bash
cd main_server
alembic upgrade head
```

### مرحله 5: تولید گواهی‌نامه‌ها

```bash
cd main_server/certs

# تولید کلید خصوصی مرجع گواهی
openssl genrsa -out ca.key 4096
chmod 600 ca.key

# تولید گواهی مرجع گواهی
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
    -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"
chmod 644 ca.crt

# تولید گواهی‌نامه سرور
mkdir -p ../certs
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
    -subj "/CN=server/O=MessageBroker/C=US"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 365 -sha256
chmod 600 server.key
chmod 644 server.crt

# تولید گواهی‌نامه پروکسی
cd ../proxy/certs
openssl genrsa -out proxy.key 2048
openssl req -new -key proxy.key -out proxy.csr \
    -subj "/CN=proxy/O=MessageBroker/C=US"
openssl x509 -req -in proxy.csr -CA ../../main_server/certs/ca.crt \
    -CAkey ../../main_server/certs/ca.key -CAcreateserial \
    -out proxy.crt -days 365 -sha256
chmod 600 proxy.key
chmod 644 proxy.crt

# کپی گواهی مرجع به پروکسی
cp ../../main_server/certs/ca.crt .

# تولید گواهی‌نامه کارگر
cd ../../worker/certs
openssl genrsa -out worker.key 2048
openssl req -new -key worker.key -out worker.csr \
    -subj "/CN=worker/O=MessageBroker/C=US"
openssl x509 -req -in worker.csr -CA ../../main_server/certs/ca.crt \
    -CAkey ../../main_server/certs/ca.key -CAcreateserial \
    -out worker.crt -days 365 -sha256
chmod 600 worker.key
chmod 644 worker.crt

# کپی گواهی مرجع به کارگر
cp ../../main_server/certs/ca.crt .
```

**یا استفاده از CLI مدیریتی:**
```bash
cd main_server
source ../venv/bin/activate
python admin_cli.py certificates generate server
python admin_cli.py certificates generate proxy
python admin_cli.py certificates generate worker
python admin_cli.py certificates generate test_client
```

### مرحله 6: ایجاد کاربر مدیر

```bash
cd main_server
source ../venv/bin/activate
python admin_cli.py users create --email admin@example.com --password AdminPass123! --role admin
```

### مرحله 7: پیکربندی محیط

ایجاد فایل `.env` در ریشه پروژه (`/opt/message_broker/.env`):

```env
# پایگاه داده
DATABASE_URL=mysql+pymysql://systemuser:YourStrongPassword123!@localhost/message_system

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# رمزهای عبور (در محیط تولید حتما تغییر دهید!)
JWT_SECRET=your-production-secret-key-min-32-chars
HASH_SALT=your-production-salt-change-this

# سرور اصلی
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# لاگ
LOG_LEVEL=INFO
LOG_FILE_PATH=/opt/message_broker/logs
```

---

## اجرای سیستم

### ویندوز - راه‌اندازی دستی

#### روش اول: استفاده از اسکریپت راه‌اندازی (ساده‌ترین روش)

```powershell
# راه‌اندازی همه سرویس‌ها به صورت همزمان
.\start_all_services.ps1

# یا راه‌اندازی در حالت خاموش (پس‌زمینه)
.\start_all_services.ps1 -Silent
```

#### روش دوم: راه‌اندازی جداگانه

باز کردن 4 پنجره PowerShell جداگانه:

**ترمینال 1 - سرور اصلی:**
```powershell
cd main_server
..\venv\Scripts\Activate.ps1
.\start_server.ps1
```

**ترمینال 2 - پروکسی:**
```powershell
cd proxy
..\venv\Scripts\Activate.ps1
.\start_proxy.ps1
```

**ترمینال 3 - کارگر:**
```powershell
cd worker
..\venv\Scripts\Activate.ps1
.\start_worker.ps1
```

**ترمینال 4 - پورتال:**
```powershell
cd portal
..\venv\Scripts\Activate.ps1
.\start_portal.ps1
```

### لینوکس - راه‌اندازی دستی

باز کردن 4 پنجره ترمینال جداگانه:

**ترمینال 1 - سرور اصلی:**
```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
uvicorn main_server.api:app --host 0.0.0.0 --port 8000 \
    --ssl-keyfile certs/server.key \
    --ssl-certfile certs/server.crt \
    --ssl-ca-certs certs/ca.crt
```

**ترمینال 2 - پروکسی:**
```bash
cd /opt/message_broker/proxy
source ../venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 8001 \
    --ssl-keyfile certs/proxy.key \
    --ssl-certfile certs/proxy.crt \
    --ssl-ca-certs certs/ca.crt \
    --workers 4
```

**ترمینال 3 - کارگر:**
```bash
cd /opt/message_broker/worker
source ../venv/bin/activate
python worker.py
```

**ترمینال 4 - پورتال:**
```bash
cd /opt/message_broker/portal
source ../venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 5000
```

### بررسی صحت اجرای سرویس‌ها

**ویندوز:**
```powershell
# بررسی پورت‌ها
Get-NetTCPConnection -LocalPort 8000,8001,5000

# بررسی نقاط سلامت
Invoke-WebRequest -Uri https://localhost:8000/health -SkipCertificateCheck
Invoke-WebRequest -Uri https://localhost:8001/api/v1/health -SkipCertificateCheck
Invoke-WebRequest -Uri http://localhost:5000
```

**لینوکس:**
```bash
# بررسی پورت‌ها
sudo netstat -tlnp | grep -E '8000|8001|5000'

# بررسی نقاط سلامت
curl -k https://localhost:8000/health
curl -k https://localhost:8001/api/v1/health
curl http://localhost:5000
```

---

## مدیریت سرویس

### ویندوز - نصب به عنوان سرویس

```powershell
# نصب همه سرویس‌ها
cd deployment/services
.\install_all_services.ps1

# راه‌اندازی سرویس‌ها
net start MessageBrokerMainServer
net start MessageBrokerProxy
net start MessageBrokerWorker
net start MessageBrokerPortal

# توقف سرویس‌ها
net stop MessageBrokerPortal
net stop MessageBrokerWorker
net stop MessageBrokerProxy
net stop MessageBrokerMainServer

# بررسی وضعیت
Get-Service MessageBroker*
```

### لینوکس - نصب به عنوان سرویس systemd

```bash
# کپی فایل‌های سرویس
sudo cp main_server/main_server.service /etc/systemd/system/
sudo cp proxy/proxy.service /etc/systemd/system/
sudo cp worker/worker.service /etc/systemd/system/
sudo cp portal/portal.service /etc/systemd/system/

# ایجاد کاربر سرویس
sudo useradd -r -s /bin/false messagebroker
sudo chown -R messagebroker:messagebroker /opt/message_broker

# تنظیم دسترسی‌ها
sudo chmod 700 /opt/message_broker/main_server/certs
sudo chmod 600 /opt/message_broker/main_server/certs/*.key
sudo chmod 600 /opt/message_broker/main_server/secrets/*

# فعال‌سازی و راه‌اندازی
sudo systemctl daemon-reload
sudo systemctl enable main_server proxy worker portal
sudo systemctl start main_server proxy worker portal

# بررسی وضعیت
sudo systemctl status main_server
sudo systemctl status proxy
sudo systemctl status worker
sudo systemctl status portal

# مشاهده لاگ‌ها
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f
```

---

## مدیریت گواهی‌نامه

### تولید گواهی‌نامه کلاینت

**ویندوز:**
```powershell
cd main_server
.\generate_cert.bat client_name
```

**لینوکس:**
```bash
cd main_server
mkdir -p certs/clients/client_name
cd certs/clients/client_name

# تولید کلید خصوصی
openssl genrsa -out client_name.key 2048

# تولید درخواست امضا
openssl req -new -key client_name.key -out client_name.csr \
    -subj "/CN=client_name/O=MessageBroker/C=US"

# امضا با مرجع گواهی
openssl x509 -req -in client_name.csr \
    -CA ../../ca.crt -CAkey ../../ca.key -CAcreateserial \
    -out client_name.crt -days 365 -sha256

# کپی گواهی مرجع
cp ../../ca.crt .
```

### باطل کردن گواهی‌نامه

**ویندوز:**
```powershell
cd main_server
.\revoke_cert.bat client_name
```

**لینوکس:**
```bash
cd main_server
openssl ca -revoke certs/clients/client_name/client_name.crt \
    -keyfile certs/ca.key -cert certs/ca.crt
openssl ca -gencrl -out crl/revoked.pem -keyfile certs/ca.key -cert certs/ca.crt
```

### لیست گواهی‌نامه‌ها

**ویندوز:**
```powershell
cd main_server
.\list_certs.bat
```

**لینوکس:**
```bash
cd main_server/certs/clients
for dir in */; do
    echo "کلاینت: $dir"
    openssl x509 -in ${dir}${dir%/}.crt -noout -subject -dates
done
```

---

## تست سیستم

### 1. دسترسی به پورتال وب

باز کردن مرورگر: `http://localhost:5000`

ورود با اطلاعات مدیر ایجاد شده قبلی.

### 2. ارسال پیام تست

**استفاده از کلاینت Python:**

```python
import httpx

cert = ("client-scripts/certs/test_client.crt", "client-scripts/certs/test_client.key")
ca = "client-scripts/certs/ca.crt"

response = httpx.post(
    "https://localhost:8001/api/v1/messages",
    json={
        "sender_number": "+1234567890",
        "message_body": "پیام تست"
    },
    cert=cert,
    verify=ca
)

print(response.json())
```

**استفاده از curl (در صورت فرمت PEM):**

```bash
curl -k --cert client-scripts/certs/test_client.crt \
     --key client-scripts/certs/test_client.key \
     --cacert client-scripts/certs/ca.crt \
     -X POST https://localhost:8001/api/v1/messages \
     -H "Content-Type: application/json" \
     -d '{"sender_number": "+1234567890", "message_body": "پیام تست"}'
```

### 3. مشاهده پیام در پورتال

1. ورود به پورتال در آدرس `http://localhost:5000`
2. رفتن به بخش پیام‌ها
3. پیام تست شما باید نمایش داده شود

---

## عیب‌یابی

### سرویس‌ها راه‌اندازی نمی‌شوند

**بررسی لاگ‌ها:**
- ویندوز: `Get-Content logs\*.log -Tail 50`
- لینوکس: `sudo journalctl -u <service_name> -n 50`

**مشکلات رایج:**
- پورت قبلا استفاده شده: `netstat -ano | findstr :8000` (ویندوز) یا `sudo lsof -i :8000` (لینوکس)
- اتصال پایگاه داده ناموفق: بررسی اجرای MySQL و صحت اطلاعات
- اتصال Redis ناموفق: بررسی اجرای Redis (`redis-cli ping`)
- خطاهای گواهی‌نامه: تولید مجدد گواهی‌نامه‌ها با استفاده از `init_ca.bat` (ویندوز) یا دستورات OpenSSL (لینوکس)

### خطاهای گواهی‌نامه

**خطا**: "Certificate verify failed"
- راه حل: تولید مجدد گواهی‌نامه‌ها با استفاده از `init_ca.bat` (ویندوز) یا دستورات OpenSSL (لینوکس)
- اطمینان از هماهنگی گواهی مرجع در همه بخش‌ها

**خطا**: "Invalid or missing client certificate"
- راه حل: اطمینان از معتبر بودن گواهی‌نامه کلاینت و امضا شدن آن توسط مرجع گواهی
- بررسی عدم انقضای گواهی‌نامه: `openssl x509 -in cert.crt -noout -dates`

### خطاهای اتصال پایگاه داده

**خطا**: "Can't connect to MySQL"
- بررسی اجرای MySQL: `net start MySQL80` (ویندوز) یا `sudo systemctl status mysql` (لینوکس)
- بررسی اطلاعات در فایل `.env`
- بررسی وجود پایگاه داده: `mysql -u systemuser -p -e "SHOW DATABASES;"`

### خطاهای اتصال Redis

**خطا**: "Connection refused"
- راه‌اندازی Redis: `redis-server --service-start` (ویندوز) یا `sudo systemctl start redis` (لینوکس)
- بررسی گوش دادن Redis: `redis-cli ping` (باید PONG برگرداند)

### کارگر پیام‌ها را پردازش نمی‌کند

**بررسی:**
1. اجرای کارگر
2. وجود پیام در صف Redis: `redis-cli LLEN message_queue`
3. دسترسی‌پذیری سرور اصلی از کارگر
4. معتبر بودن گواهی‌نامه کارگر

### مشکلات ورود به پورتال

**خطا**: "Invalid credentials"
- ایجاد کاربر مدیر: `python admin_cli.py users create --email admin@example.com --password AdminPass123! --role admin`
- بررسی وجود کاربر: `python admin_cli.py users list`

---

## چک‌لیست تولید

قبل از راه‌اندازی در محیط تولید:

- تغییر همه رمزهای عبور پیش‌فرض (JWT_SECRET، HASH_SALT، رمزهای پایگاه داده)
- تولید مرجع گواهی و گواهی‌نامه‌های جدید (استفاده نکردن از گواهی‌نامه‌های تست)
- تنظیم قوانین فایروال (اجازه پورت‌های 8000، 8001، 5000)
- تنظیم گواهی‌نامه‌های SSL/TLS برای دامنه تولید
- تنظیم چرخش لاگ
- تنظیم روش‌های پشتیبان‌گیری پایگاه داده
- تنظیم پایداری Redis (فعال‌سازی AOF)
- تنظیم مانیتورینگ (Prometheus/Grafana)
- تنظیم failover و افزونگی
- بازبینی و سخت‌سازی تنظیمات امنیتی
- تست روش‌های پشتیبان‌گیری و بازیابی
- مستندسازی امن اطلاعات تولید

---

## پشتیبانی و مستندات

### مستندات API

- API سرور اصلی: `https://localhost:8000/docs`
- API پروکسی: `https://localhost:8001/api/v1/docs`

### بررسی سلامت

- سرور اصلی: `https://localhost:8000/health`
- پروکسی: `https://localhost:8001/api/v1/health`
- متریک‌ها: `https://localhost:8000/metrics`

### محل لاگ‌ها

**ویندوز:**
- سرور اصلی: `logs/main_server.log`
- پروکسی: `logs/proxy.log`
- کارگر: `logs/worker.log`
- پورتال: `logs/portal.log`

**لینوکس:**
- لاگ‌های systemd: `sudo journalctl -u <service_name>`
- لاگ‌های برنامه: `/opt/message_broker/logs/*.log`

---

## دستورات مرجع سریع

### ویندوز

```powershell
# راه‌اندازی همه سرویس‌ها
.\start_all_services.ps1

# توقف همه سرویس‌ها
.\stop_all_services.ps1

# بررسی وضعیت سرویس
Get-Service MessageBroker*

# مشاهده لاگ‌ها
Get-Content logs\*.log -Tail 50
```

### لینوکس

```bash
# راه‌اندازی همه سرویس‌ها
sudo systemctl start main_server proxy worker portal

# توقف همه سرویس‌ها
sudo systemctl stop portal worker proxy main_server

# بررسی وضعیت
sudo systemctl status main_server proxy worker portal

# مشاهده لاگ‌ها
sudo journalctl -u main_server -f
```

---

**پایان راهنمای راه‌اندازی**

