# پاسخ به سوالات پروژه Message Broker

## بر روی سرور پراکسی

### 1. چه پکیج هایی باید نصب باشد؟

**پکیج‌های سیستم:**
- Python 3.12+
- Redis Server
- OpenSSL

**پکیج‌های Python (از `proxy/requirements.txt`):**
```
fastapi==0.115.0
uvicorn[standard]==0.30.6
redis==5.0.8
pyyaml==6.0.2
pydantic==2.9.2
pydantic-settings==2.5.2
httpx==0.27.2
cryptography==43.0.1
python-dotenv==1.0.1
prometheus-client==0.21.0
```

**نصب:**
```bash
pip install -r proxy/requirements.txt
```

---

### 2. در تنظیمات فایل .env مواردی باید باشد؟

فایل `.env` باید در مسیر `/opt/message_broker_proxy/.env` قرار گیرد (یا مسیر نصب پروژه).

**محتویات مورد نیاز (`proxy/env.template`):**
```env
# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Main Server Configuration
MAIN_SERVER_URL=https://173.32.115.223:8000

# Certificate Paths (relative to proxy directory)
SERVER_CERT_PATH=certs/proxy.crt
SERVER_KEY_PATH=certs/proxy.key
CA_CERT_PATH=certs/ca.crt

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE_PATH=/opt/message_broker_proxy/proxy/logs
```

---

### 3. چه پورت ورودی باید روی فایروال باز باشد؟

**پورت 8001 (TCP)** - برای HTTPS API endpoint سرور پراکسی

**دستورات باز کردن پورت:**

**UFW (Ubuntu/Debian):**
```bash
sudo ufw allow 8001/tcp
sudo ufw reload
```

**firewalld (CentOS/RHEL):**
```bash
sudo firewall-cmd --permanent --add-port=8001/tcp
sudo firewall-cmd --reload
```

**iptables:**
```bash
sudo iptables -A INPUT -p tcp --dport 8001 -j ACCEPT
sudo iptables-save
```

**نکته:** همچنین باید پورت Redis (6379) برای دسترسی محلی باز باشد (معمولاً فقط localhost).

---

### 4. آیا دسترسی اوت باند به اینترنت فقط https و مقصد سرور اصلی است؟

**بله، درست است.**

سرور پراکسی فقط نیاز به:
- **HTTPS** به سرور اصلی (پورت 8000) برای ثبت پیام‌ها
- **Redis** محلی (localhost) برای صف پیام‌ها

**تنظیمات در `proxy/app.py`:**
- `MAIN_SERVER_URL` - آدرس سرور اصلی
- `MAIN_SERVER_VERIFY_SSL` - می‌توانید برای self-signed certificates روی `false` تنظیم کنید

**هیچ دسترسی دیگری به اینترنت نیاز نیست.**

---

### 5. گواهینامه‌های لازم برای سرور پراکسی باید برروی سرور اصلی تولید شده باشد؟

**بله، درست است.**

گواهینامه‌های پراکسی باید روی سرور اصلی تولید شوند و سپس به سرور پراکسی منتقل شوند.

**فرآیند:**
1. روی سرور اصلی: `main_server/generate_cert.bat proxy` یا `main_server/generate_certs.ps1 proxy`
2. گواهینامه‌ها در `main_server/certs/clients/proxy/` تولید می‌شوند
3. کپی به سرور پراکسی: `proxy/certs/`

---

### 6. گواهینامه‌ها باید در چه مسیری قرار داده شود؟

**مسیر گواهینامه‌ها در سرور پراکسی:**
```
proxy/certs/
├── proxy.crt      # گواهینامه سرور پراکسی
├── proxy.key      # کلید خصوصی (محرمانه!)
└── ca.crt         # گواهینامه CA
```

**مسیر در تنظیمات:**
- `SERVER_CERT_PATH=certs/proxy.crt`
- `SERVER_KEY_PATH=certs/proxy.key`
- `CA_CERT_PATH=certs/ca.crt`

**دسترسی‌ها:**
```bash
chmod 600 certs/proxy.key
chmod 644 certs/proxy.crt
chmod 644 certs/ca.crt
```

---

### 7. محل تنظیمات ارتباط سرور پراکسی با سرور اصلی کجاست؟

**1. فایل `.env`:**
```env
MAIN_SERVER_URL=https://173.32.115.223:8000
```

**2. فایل `proxy/config.yaml`:**
```yaml
main_server:
  url: "${MAIN_SERVER_URL}"
  register_endpoint: "/internal/messages/register"
  timeout: 30
```

**3. کد در `proxy/app.py`:**
- کلاس `MainServerClient` - خط 251-295
- متد `register_message()` - برای ثبت پیام در سرور اصلی

**4. تنظیمات SSL verification:**
```env
MAIN_SERVER_VERIFY_SSL=true  # یا false برای self-signed
```

---

### 8. مجاز بودن پیام دریافتی بر اساس سرتیفیکیت بررسی می‌شود، تنظیمات این مکانیسم کجاست؟

**1. فایل `proxy/config.yaml`:**
```yaml
tls:
  enabled: true
  verify_client: true  # ← این تنظیم
```

**2. کد در `proxy/app.py`:**
- تابع `extract_client_certificate()` - خط 365-419
- تابع `validate_client_certificate()` - خط 422-452
- در endpoint `/api/v1/messages` - خط 464-600

**3. تنظیمات uvicorn:**
```bash
uvicorn app:app \
  --ssl-keyfile certs/proxy.key \
  --ssl-certfile certs/proxy.crt \
  --ssl-ca-certs certs/ca.crt  # ← برای verify client certs
```

---

### 9. چطور می‌تونم سرتیفیکیت کاربر را در سرور پراکسی غیر فعال کنم؟

**روش 1: تغییر `config.yaml`:**
```yaml
tls:
  verify_client: false  # ← تغییر به false
```

**روش 2: تغییر کد در `proxy/app.py`:**
در endpoint `/api/v1/messages` (خط 479-493)، می‌توانید بررسی را skip کنید:
```python
# کامنت کردن یا حذف این بخش:
# cert_info = extract_client_certificate(request)
# is_valid, client_id = validate_client_certificate(cert_info)
# if not is_valid:
#     raise HTTPException(...)
```

**⚠️ هشدار:** غیرفعال کردن بررسی سرتیفیکیت امنیت را کاهش می‌دهد!

---

### 10. چطور می‌تونم دسترسی کاربر برای ارسال پیام رو در سرور پراکسی غیر فعال کنم؟

**روش 1: غیرفعال کردن endpoint:**
در `proxy/app.py` می‌توانید endpoint را کامنت کنید یا خطا برگردانید.

**روش 2: استفاده از Rate Limiting:**
در `proxy/config.yaml`:
```yaml
rate_limiting:
  enabled: true
  max_requests: 0  # ← غیرفعال کردن
  window_seconds: 60
```

**روش 3: بررسی در کد:**
می‌توانید یک لیست سیاه از `client_id` ها در کد اضافه کنید و در `validate_client_certificate()` بررسی کنید.

**روش 4: Revoke کردن سرتیفیکیت:**
روی سرور اصلی، سرتیفیکیت کاربر را revoke کنید (در CRL اضافه می‌شود).

---

### 11. مکانیسمی برای مدیریت سشن وجود دارد؟ تا از بروز جملات احتمالی جلوگیری کنیم؟

**❌ در حال حاضر مکانیسم session management برای جلوگیری از replay attacks در سرور پراکسی پیاده‌سازی نشده است.**

**پیشنهادات برای پیاده‌سازی:**
1. **Nonce/Timestamp:** اضافه کردن nonce یا timestamp به هر درخواست
2. **Redis-based session tracking:** ذخیره nonce های استفاده شده در Redis با TTL
3. **Message ID uniqueness:** بررسی اینکه `message_id` قبلاً استفاده نشده باشد

**کد فعلی:**
- در `proxy/app.py` هر پیام یک `message_id` منحصر به فرد دارد (UUID) - خط 474
- اما بررسی replay attack وجود ندارد

**برای پیاده‌سازی:**
```python
# در submit_message():
message_id = str(uuid.uuid4())
# بررسی در Redis:
if redis_queue.client.exists(f"msg:{message_id}"):
    raise HTTPException(400, "Duplicate message")
redis_queue.client.setex(f"msg:{message_id}", 3600, "1")
```

---

## بر روی سرور اصلی

### 12. چه پکیج هایی باید نصب باشد؟

**پکیج‌های سیستم:**
- Python 3.8+
- MySQL 8.0+ یا MariaDB
- OpenSSL

**پکیج‌های Python (از `main_server/requirements.txt`):**
```
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
pymysql==1.1.1
cryptography==43.0.1
pydantic==2.9.2
pydantic-settings==2.5.2
alembic==1.13.3
pyyaml==6.0.2
python-dotenv==1.0.1
prometheus-client==0.21.0
passlib[bcrypt]==1.7.4
pyjwt==2.9.0
httpx==0.27.2
tabulate==0.9.0
```

---

### 13. در تنظیمات فایل .env مواردی باید باشد (حذف موارد اضافی)؟

**فایل `.env` باید در مسیر `/opt/message_broker/.env` قرار گیرد.**

**محتویات ضروری برای Main Server:**
```env
# Database Configuration
# روش 1: استفاده از DATABASE_URL (توصیه می‌شود - در کد استفاده می‌شود)
DATABASE_URL=mysql+pymysql://systemuser:StrongPass123!@localhost/message_system

# یا روش 2: استفاده از متغیرهای جداگانه (در env.template موجود است اما در کد استفاده نمی‌شود)
# DB_HOST=localhost
# DB_PORT=3306
# DB_NAME=message_system
# DB_USER=systemuser
# DB_PASSWORD=StrongPass123!

# Security - AES Encryption
ENCRYPTION_KEY_PATH=/opt/message_broker/main_server/secrets/encryption.key
# نکته: در env.template از AES_KEY_PATH استفاده شده، اما در کد (main_server/api.py خط 73) از ENCRYPTION_KEY_PATH استفاده می‌شود

# JWT Configuration
JWT_SECRET=SuperSecretJWTKey_ChangeInProduction
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=30

# TLS/Certificate Paths
CA_CERT_PATH=/opt/message_broker/main_server/certs/ca.crt
SERVER_KEY_PATH=/opt/message_broker/main_server/certs/server.key
SERVER_CERT_PATH=/opt/message_broker/main_server/certs/server.crt

# Service Endpoints
MAIN_SERVER_URL=https://localhost:8000

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=/opt/message_broker/main_server/logs
```

**محتویات اضافی که می‌توان حذف کرد (برای Main Server):**
- `REDIS_HOST`, `REDIS_PORT` - اختیاری (برای enqueue کردن پیام‌ها استفاده می‌شود اما اجباری نیست - خط 302-319 در api.py)
- `PROXY_URL` - فقط برای Worker نیاز است
- `PORTAL_URL` - فقط برای Portal نیاز است
- `WORKER_*` - فقط برای Worker نیاز است
- `PROMETHEUS_PORT`, `GRAFANA_PORT` - اختیاری

---

### 14. چه پورت ورودی باید روی فایروال باز باشد؟

**پورت 8000 (TCP)** - برای HTTPS API endpoint سرور اصلی

**دستورات:**
```bash
# UFW
sudo ufw allow 8000/tcp

# firewalld
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload
```

**نکته:** پورت MySQL (3306) باید فقط برای localhost باز باشد (نه از خارج).

---

### 15. آیا دسترسی اوت باند به اینترنت یا سرور پراکسی نیاز است؟

**خیر، سرور اصلی نیاز به دسترسی اوت باند ندارد.**

سرور اصلی:
- فقط **دریافت** درخواست‌ها از Proxy و Worker (inbound)
- **نیازی به اتصال به اینترنت ندارد**
- فقط نیاز به دسترسی به MySQL محلی

**تنها در صورتی که:**
- Worker روی سرور دیگری باشد → نیاز به دسترسی به Worker
- Portal روی سرور دیگری باشد → نیاز به دسترسی به Portal

---

### 16. گواهینامه‌های لازم برای Main_server و Portal باید در چه مسیری قرار داده شود؟

**Main Server:**
```
/opt/message_broker/main_server/certs/
├── ca.crt          # CA certificate
├── ca.key          # CA private key (محرمانه!)
├── server.crt      # Server certificate
└── server.key      # Server private key (محرمانه!)
└── clients/        # Client certificates
    ├── proxy/
    │   ├── proxy.crt
    │   └── proxy.key
    └── [client_id]/
        ├── [client_id].crt
        └── [client_id].key
```

**Portal:**
Portal از گواهینامه‌های Main Server استفاده نمی‌کند (HTTP است، نه HTTPS).

**اگر Portal را با HTTPS می‌خواهید:**
- گواهینامه‌های Let's Encrypt باید در مسیر nginx/apache قرار گیرند (نه در پوشه portal)

---

### 17. آیا تنظیمات فایل .env برای سرور اصلی و پورتال متفاوت است؟

**خیر، Portal و Main Server از یک فایل `.env` مشترک استفاده می‌کنند.**

**فایل:** `/opt/message_broker/.env`

**متغیرهای مشترک:**
- Database settings
- JWT settings
- Logging settings

**متغیرهای مخصوص Portal:**
```env
# Portal-specific
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_VERIFY_SSL=false
PORTAL_HOST=0.0.0.0
PORTAL_PORT=8080
SESSION_SECRET=change_this_session_secret_in_production
SESSION_MAX_AGE=3600
MESSAGES_PER_PAGE=20
```

**متغیرهای مخصوص Main Server:**
```env
# Main Server-specific
CA_CERT_PATH=/opt/message_broker/main_server/certs/ca.crt
SERVER_CERT_PATH=/opt/message_broker/main_server/certs/server.crt
SERVER_KEY_PATH=/opt/message_broker/main_server/certs/server.key
ENCRYPTION_KEY_PATH=/opt/message_broker/main_server/secrets/encryption.key
```

---

### 18. محل تنظیمات ارتباط سرور اصلی با سرور پراکسی کجاست؟

**سرور اصلی به صورت passive عمل می‌کند** - یعنی فقط درخواست‌ها را دریافت می‌کند.

**تنظیمات در Main Server:**
1. **Endpoint برای Proxy:** `/internal/messages/register` (در `main_server/api.py`)
2. **Mutual TLS:** Proxy باید با سرتیفیکیت معتبر به Main Server متصل شود
3. **تنظیمات در `main_server/api.py`:**
   - تابع `get_client_from_cert()` - خط 381-407
   - Endpoint `/internal/messages/register` - خط 650-750

**هیچ تنظیمات URL برای Proxy در Main Server وجود ندارد** - Proxy خودش به Main Server متصل می‌شود.

---

### 19. اینکه از چه نسخه TLS استفاده کنم چطور انجام میشه و آیا ارتقای نسخه TLS امکان پذیره؟

**تنظیمات TLS در uvicorn:**

**در `main_server/main_server.service`:**
```ini
ExecStart=/opt/message_broker/venv/bin/uvicorn main_server.api:app \
    --host 0.0.0.0 \
    --port 8000 \
    --ssl-keyfile /opt/message_broker/main_server/certs/server.key \
    --ssl-certfile /opt/message_broker/main_server/certs/server.crt \
    --ssl-ca-certs /opt/message_broker/main_server/certs/ca.crt
```

**⚠️ uvicorn به صورت مستقیم تنظیمات TLS version را پشتیبانی نمی‌کند.**

**برای کنترل TLS version:**

**روش 1: استفاده از reverse proxy (nginx):**
```nginx
server {
    listen 443 ssl http2;
    ssl_protocols TLSv1.2 TLSv1.3;  # ← کنترل نسخه TLS
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass https://localhost:8000;
    }
}
```

**روش 2: استفاده از Python SSL context:**
در `main_server/api.py` می‌توانید SSL context را تنظیم کنید:
```python
import ssl

ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
ssl_context.maximum_version = ssl.TLSVersion.TLSv1_3
```

**بله، ارتقای TLS امکان‌پذیر است** - فقط باید تنظیمات را تغییر دهید.

---

## بر روی پورتال

### 20. روی پورتال ادمین نیاز دارم بتونم یک یوزر رو فعال/غیرفعال کنم یا پسوردش رو تغییر بدم.

**✅ تغییر پسورد: بله، از طریق Admin CLI (نه Portal UI)**

**❌ فعال/غیرفعال کردن: در حال حاضر در Portal UI و API موجود نیست، اما فیلد `is_active` در Database وجود دارد**

**روش‌های موجود:**

**1. تغییر پسورد از Admin CLI:**
```bash
cd main_server
# استفاده از user_id (عدد، نه email)
python admin_cli.py user password <user_id> --password NewPass123!
# یا بدون --password برای prompt
python admin_cli.py user password <user_id>
```

**نکته:** در Admin CLI باید `user_id` (عدد) استفاده کنید، نه email. برای پیدا کردن user_id:
```bash
python admin_cli.py user list
```

**⚠️ باگ در کد:** در `admin_cli.py` خط 106 از `user.last_login_at` استفاده شده، اما در مدل (`models.py` خط 99) فیلد `last_login` است. این یک باگ است که باید اصلاح شود (باید `user.last_login` باشد).

**نکته:** در `main_server/api.py` خط 524، کامنت نشان می‌دهد که `UserResponse` از `last_login_at` به `last_login` تغییر یافته است، اما `admin_cli.py` هنوز به‌روز نشده است.

**2. فعال/غیرفعال کردن از Database:**
```sql
-- غیرفعال کردن
UPDATE users SET is_active = 0 WHERE email = 'user@example.com';

-- فعال کردن
UPDATE users SET is_active = 1 WHERE email = 'user@example.com';
```

**3. اضافه کردن به Portal UI:**
می‌توانید endpoint های زیر را به Portal اضافه کنید:
- `PUT /admin/users/{user_id}/activate`
- `PUT /admin/users/{user_id}/deactivate`
- `PUT /admin/users/{user_id}/password`

**کد موجود:**
- مدل `User` دارای فیلد `is_active` است (`main_server/models.py` خط 98)
- اما endpoint برای تغییر آن در API موجود نیست (فقط `POST /admin/users` برای ایجاد و `GET /admin/users` برای لیست)
- Admin CLI نیز قابلیت تغییر `is_active` ندارد

---

### 21. روی پورتال ادمین نیاز دارم رول یک یوزر رو بتونم تغییر بدم.

**❌ در حال حاضر در Portal UI موجود نیست**

**روش‌های موجود:**

**1. از Database:**
```sql
UPDATE users SET role = 'admin' WHERE email = 'user@example.com';
-- یا
UPDATE users SET role = 'user' WHERE email = 'user@example.com';
```

**2. از Admin CLI:**
```bash
# در حال حاضر این قابلیت در admin_cli.py موجود نیست
# باید اضافه شود
```

**3. اضافه کردن به Portal:**
می‌توانید endpoint `PUT /admin/users/{user_id}/role` را اضافه کنید.

**کد موجود:**
- در `main_server/api.py` - خط 1078-1149: فقط `POST /admin/users` برای ایجاد کاربر وجود دارد
- `PUT` endpoint برای تغییر role وجود ندارد

---

### 22. روی پورتال ادمین می‌تونم رول های بیشتری داشته باشم؟ مثلا رول مدیریت کاربران

**❌ در حال حاضر فقط دو رول وجود دارد: `admin` و `user`**

**کد موجود در `main_server/models.py`:**
```python
class UserRole(str, Enum):
    ADMIN = "admin"
    USER = "user"
```

**برای اضافه کردن رول جدید:**

**1. تغییر `models.py`:**
```python
class UserRole(str, Enum):
    ADMIN = "admin"
    USER = "user"
    USER_MANAGER = "user_manager"  # ← رول جدید
```

**2. تغییر Database:**
```sql
ALTER TABLE users MODIFY role ENUM('admin', 'user', 'user_manager') NOT NULL;
```

**3. تغییر منطق دسترسی در `main_server/api.py`:**
```python
# به جای:
if current_user.role != UserRole.ADMIN:
    
# استفاده از:
if current_user.role not in [UserRole.ADMIN, UserRole.USER_MANAGER]:
```

**4. تغییر Portal UI:**
- اضافه کردن رول جدید به dropdown در `portal/templates/admin/users.html`

---

### 23. روی پورتال می‌تونیم برای کاربران مکانیسم تغییر پسورد پیاده سازی کنیم تا از طریق ایمیل براشون ارسال بشه؟

**❌ در حال حاضر این قابلیت پیاده‌سازی نشده است**

**برای پیاده‌سازی نیاز است:**

**1. تنظیمات SMTP در `.env`:**
```env
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=noreply@example.com
SMTP_PASSWORD=password
SMTP_FROM=noreply@example.com
```

**2. اضافه کردن endpoint:**
```python
# در main_server/api.py:
@app.post("/portal/auth/forgot-password")
async def forgot_password(email: str, db: Session = Depends(get_db)):
    # تولید token
    # ارسال ایمیل
    # ذخیره token در database
```

**3. اضافه کردن صفحه در Portal:**
- `portal/templates/forgot_password.html`
- `portal/templates/reset_password.html`

**4. استفاده از کتابخانه email:**
```python
import smtplib
from email.mime.text import MIMEText
```

**پیشنهاد:** از سرویس‌های email مانند SendGrid، Mailgun، یا AWS SES استفاده کنید.

---

### 24. روی پورتال ادمین می‌تونم مدیریت دیتابیس تا فایل تنظیمات رو هم داشته باشم؟

**❌ در حال حاضر این قابلیت موجود نیست**

**برای پیاده‌سازی:**

**1. مدیریت Database:**
- نمایش جداول و داده‌ها
- اجرای query های ساده
- Backup/Restore

**2. مدیریت فایل تنظیمات:**
- نمایش `.env` (بدون نمایش password)
- ویرایش تنظیمات
- اعمال تغییرات

**⚠️ هشدار امنیتی:** این قابلیت‌ها بسیار حساس هستند و باید با احتیاط پیاده‌سازی شوند:
- دسترسی فقط برای super admin
- Audit logging کامل
- Validation شدید برای query ها
- Backup قبل از تغییرات

**پیشنهاد:** از ابزارهای جداگانه مانند phpMyAdmin یا Adminer برای مدیریت Database استفاده کنید.

---

### 25. روی پورتال ادمین می‌تونم مدیریت بک آپ داشته باشم؟

**❌ در حال حاضر این قابلیت در Portal موجود نیست**

**روش‌های موجود:**

**1. از Command Line:**
```bash
# Backup database
mysqldump -u systemuser -p message_system > backup.sql

# Backup certificates
tar -czf certs_backup.tar.gz main_server/certs/

# Backup encryption keys
tar -czf secrets_backup.tar.gz main_server/secrets/
```

**2. اسکریپت خودکار:**
می‌توانید cron job تنظیم کنید:
```bash
0 2 * * * /opt/message_broker/backup.sh
```

**برای اضافه کردن به Portal:**
- صفحه Backup Management
- دکمه "Create Backup"
- لیست Backup های موجود
- دکمه "Download" و "Restore"

**⚠️ نکته:** Backup ها باید در مسیر امن ذخیره شوند و دسترسی محدود داشته باشند.

---

### 26. برای اینکه پورتال برای کاربران روی اینترنت منتشر بشه باید ssl از Letsencrypt بگیرم، گواهینامه ها کجا باید قرار داده بشه تا کار کنه و آیا تداخلی با گواهینامه های قبلی بوجود نمیاد؟

**✅ بله، می‌توانید از Let's Encrypt استفاده کنید**

**مسیر گواهینامه‌های Let's Encrypt:**
```
/etc/letsencrypt/live/your-domain.com/
├── fullchain.pem  # گواهینامه + chain
├── privkey.pem    # کلید خصوصی
└── cert.pem        # فقط گواهینامه
```

**تنظیمات Nginx:**
```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    # Let's Encrypt certificates
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    location / {
        proxy_pass http://localhost:8080;  # Portal
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

**❌ تداخلی با گواهینامه‌های قبلی وجود ندارد:**
- گواهینامه‌های Let's Encrypt برای **HTTPS Portal** استفاده می‌شوند
- گواهینامه‌های self-signed برای **Mutual TLS** بین Proxy و Main Server استفاده می‌شوند
- این دو کاملاً جدا هستند

**نصب Let's Encrypt:**
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

**Auto-renewal:**
```bash
sudo certbot renew --dry-run
# یا در crontab:
0 0 * * * certbot renew --quiet
```

---

### 27. برای اینکه دیتابیس زیاد بزرگ نشه، میشه مکانیسمی برای نگهداری اخرین پیامهای هر یوزر در مثلا شش ماه گذشته رو داشته باشیم؟

**✅ بله، این قابلیت در Database موجود است**

**Stored Procedure موجود در `main_server/schema.sql`:**
```sql
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
END
```

**استفاده (برای 6 ماه = 180 روز):**
```sql
CALL sp_cleanup_old_messages(180);
```

**تنظیم Cron Job:**
```bash
# هر هفته اجرا شود
0 2 * * 0 mysql -u systemuser -p message_system -e "CALL sp_cleanup_old_messages(180);"
```

**⚠️ هشدار:** این عملیات **غیرقابل بازگشت** است. قبل از اجرا Backup بگیرید!

**برای اضافه کردن به Portal:**
- صفحه "Data Retention"
- تنظیم retention period
- دکمه "Run Cleanup Now"
- نمایش تعداد پیام‌های حذف شده

---

### 28. روی پورتال ادمین میشه تعداد پیام های دریافتی روزانه، هفتگی و ماهانه رو داشته باشیم؟

**✅ آمار روزانه و هفتگی موجود است**
**❌ آمار ماهانه در Portal موجود نیست (اما Stored Procedure پشتیبانی می‌کند)**

**1. در Admin Dashboard (`portal/templates/admin/dashboard.html`):**
- نمایش `messages_last_24h` - خط 145-153
- نمایش `messages_last_7d` - خط 156-167
- **آمار ماهانه موجود نیست**

**2. API Endpoint موجود (`main_server/api.py` خط 1162-1214):**
```python
@app.get("/admin/stats")
async def get_stats(...):
    # Messages last 24 hours (خط 1195-1198)
    messages_last_24h = ...
    # Messages last 7 days (خط 1200-1204)
    messages_last_7d = ...
    # آمار ماهانه در API موجود نیست
```

**3. Stored Procedure در Database (`main_server/schema.sql` خط 213-247):**
```sql
CREATE PROCEDURE `sp_get_stats`(
  IN p_period VARCHAR(10), -- 'hour', 'day', 'week', 'month'
  IN p_domain VARCHAR(255)
)
```

**استفاده از Stored Procedure:**
```sql
CALL sp_get_stats('day', NULL);   -- آمار روزانه
CALL sp_get_stats('week', NULL); -- آمار هفتگی
CALL sp_get_stats('month', NULL); -- آمار ماهانه (از طریق Database)
```

**برای اضافه کردن آمار ماهانه به Portal:**
باید در `main_server/api.py` (تابع `get_stats`) و `portal/templates/admin/dashboard.html` اضافه کنید.

---

### 29. روی پورتال ادمین میشه وضعیت ارتباط با پراکسی ها رو انلاین ببینیم؟

**❌ در حال حاضر این قابلیت موجود نیست**

**برای پیاده‌سازی:**

**1. Health Check Endpoint در Proxy:**
```python
# در proxy/app.py - خط 602-633
@app.get("/api/v1/health")
async def health_check():
    return {
        "status": "healthy",
        "redis": "healthy" if redis_queue.health_check() else "unhealthy"
    }
```

**2. Monitoring در Main Server:**
```python
# در main_server/api.py
@app.get("/admin/proxies/status")
async def get_proxy_statuses():
    proxies = [
        {"url": "https://proxy1:8001", "status": "online"},
        {"url": "https://proxy2:8001", "status": "offline"}
    ]
    # Check health endpoint of each proxy
    return proxies
```

**3. اضافه کردن به Portal:**
- صفحه "Proxy Status"
- لیست تمام Proxy ها
- نمایش وضعیت (Online/Offline)
- Last check time

**پیشنهاد:** از Prometheus + Grafana برای monitoring استفاده کنید.

---

### 30. روی پورتال ادمین میشه سرتیفیکیت ها و کاربرانی که در 30 روز آینده منقضی میشن رو ببینم؟

**❌ در حال حاضر این قابلیت در Portal موجود نیست**

**اما در Admin CLI موجود است:**

**1. بررسی سرتیفیکیت:**
```bash
cd main_server
.\verify_cert.bat client_name
# این اسکریپت بررسی می‌کند که آیا در 30 روز آینده منقضی می‌شود
```

**2. لیست تمام سرتیفیکیت‌ها:**
```bash
.\list_certs.bat
```

**برای پیاده‌سازی در Portal:**

**1. API Endpoint (باید اضافه شود):**
```python
# در main_server/api.py
@app.get("/admin/certificates/expiring")
async def get_expiring_certificates(
    days: int = 30,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    # استفاده از expires_at در Database (فیلد موجود در Client model)
    cutoff_date = datetime.utcnow() + timedelta(days=days)
    expiring_certs = db.query(Client).filter(
        Client.status == ClientStatus.ACTIVE,
        Client.expires_at <= cutoff_date,
        Client.expires_at > datetime.utcnow()
    ).all()
    return [{"client_id": c.client_id, "expires_at": c.expires_at.isoformat()} for c in expiring_certs]
```

**2. اضافه کردن به Portal:**
- صفحه "Certificates" → تب "Expiring Soon"
- لیست سرتیفیکیت‌هایی که در 30 روز آینده منقضی می‌شوند
- دکمه "Renew Certificate"

**کد موجود:**
- در `main_server/models.py` خط 172: فیلد `expires_at` در جدول `clients` موجود است
- در `main_server/models.py` خط 215-221: متد `is_valid()` بررسی expiration می‌کند (خط 219: `if self.expires_at < datetime.utcnow()`)
- در `main_server/api.py` خط 965: هنگام ایجاد سرتیفیکیت، `expires_at` تنظیم می‌شود
- در `main_server/verify_cert.bat` خط 97-107: بررسی expiration within 30 days (فقط برای CLI)
- در `main_server/admin_cli.py` خط 254: نمایش `expires_at` در لیست سرتیفیکیت‌ها
- **هیچ API endpoint برای لیست کردن سرتیفیکیت‌ها یا سرتیفیکیت‌های در حال انقضا وجود ندارد**

---

## خلاصه

### قابلیت‌های موجود ✅
- مدیریت کاربران (ایجاد)
- مدیریت سرتیفیکیت (ایجاد/revoke)
- آمار پیام‌ها (روزانه/هفتگی)
- Cleanup پیام‌های قدیمی
- Health check endpoints

### قابلیت‌های موجود نیست ❌
- فعال/غیرفعال کردن کاربر از Portal یا API
- تغییر role از Portal یا API
- تغییر پسورد از Portal (فقط از Admin CLI)
- آمار ماهانه در Portal (فقط روزانه و هفتگی)
- Password reset via email
- مدیریت Database از Portal
- مدیریت Backup از Portal
- نمایش وضعیت Proxy ها
- نمایش سرتیفیکیت‌های در حال انقضا
- Session management برای جلوگیری از replay attacks
- رول‌های اضافی (مثل user_manager)

### پیشنهادات
1. اضافه کردن endpoint های PUT برای تغییر کاربران
2. پیاده‌سازی password reset via email
3. اضافه کردن monitoring برای Proxy ها
4. اضافه کردن alert برای سرتیفیکیت‌های در حال انقضا
5. پیاده‌سازی session management برای replay attack prevention

