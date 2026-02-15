# راهنمای تست سیستم Message Broker

این راهنما دستورالعمل‌های گام‌به‌گام برای تست سیستم message broker مستقر شده روی سرور لینوکس شما را ارائه می‌دهد.

## پیش‌نیازها

- دسترسی SSH به سرور (IP: `91.92.206.217`, پورت: `2223`)
- اطلاعات ورود ادمین:
  - ایمیل: `admin@example.com`
  - رمز عبور: `AdminPass123!`

---

## ۱. بررسی وضعیت سرویس‌ها

### بررسی وضعیت سرویس‌ها

```bash
ssh -p 2223 root@91.92.206.217 "systemctl status main_server proxy worker portal --no-pager | grep -E '(●|Active:)'"
```

**خروجی مورد انتظار:**
```
● main_server.service - Active: active (running)
● proxy.service - Active: active (running)
● worker.service - Active: active (running)
● portal.service - Active: active (running)
```

### بررسی لاگ‌های سرویس‌ها

```bash
# لاگ‌های Main Server
ssh -p 2223 root@91.92.206.217 "journalctl -u main_server.service --no-pager -n 20"

# لاگ‌های Proxy
ssh -p 2223 root@91.92.206.217 "journalctl -u proxy.service --no-pager -n 20"

# لاگ‌های Worker
ssh -p 2223 root@91.92.206.217 "journalctl -u worker.service --no-pager -n 20"

# لاگ‌های Portal
ssh -p 2223 root@91.92.206.217 "journalctl -u portal.service --no-pager -n 20"
```

### بررسی پورت‌های در حال گوش دادن

```bash
ssh -p 2223 root@91.92.206.217 "netstat -tlnp | grep -E '(8000|8001|8080)'"
```

**خروجی مورد انتظار:**
```
tcp  0  0  0.0.0.0:8000  LISTEN  <pid>/python3  # Main Server
tcp  0  0  0.0.0.0:8001  LISTEN  <pid>/python3  # Proxy
tcp  0  0  0.0.0.0:8080  LISTEN  <pid>/python3  # Portal
```

---

## ۲. تست ورود به پورتال

### دسترسی به پورتال

1. **مرورگر وب خود را باز کنید** و به آدرس زیر بروید:
   ```
   http://91.92.206.217:8080
   ```

2. **با اطلاعات ادمین وارد شوید:**
   - ایمیل: `admin@example.com`
   - رمز عبور: `AdminPass123!`

3. **نتیجه مورد انتظار:**
   - باید به داشبورد ادمین هدایت شوید
   - باید گزینه‌های زیر را ببینید:
     - مدیریت کاربران
     - پیام‌ها
     - گواهینامه‌ها
     - آمار سیستم

### تست ویژگی‌های پورتال

- **مدیریت کاربران:**
  - رفتن به بخش "Users"
  - ایجاد کاربر جدید
  - مشاهده لیست تمام کاربران
  - ویرایش اطلاعات کاربر

- **پیام‌ها:**
  - مشاهده صف پیام‌ها
  - بررسی وضعیت پیام
  - مشاهده تاریخچه پیام‌ها

- **گواهینامه‌ها:**
  - مشاهده گواهینامه‌های کلاینت
  - تولید گواهینامه جدید
  - لغو گواهینامه‌ها

---

## ۳. تست API سرور اصلی

### بررسی سلامت

```bash
# تست endpoint سلامت (غیرفعال کردن بررسی SSL برای تست)
curl -k https://91.92.206.217:8000/health
```

**پاسخ مورد انتظار:**
```json
{
  "status": "healthy",
  "database": "connected",
  "redis": "connected"
}
```

### مستندات API

1. **باز کردن Swagger UI:**
   ```
   https://91.92.206.217:8000/docs
   ```

2. **باز کردن ReDoc:**
   ```
   https://91.92.206.217:8000/redoc
   ```

### تست احراز هویت

```bash
# ورود و دریافت JWT token
TOKEN=$(curl -k -X POST "https://91.92.206.217:8000/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"AdminPass123!"}' \
  | jq -r '.access_token')

echo "Token: $TOKEN"
```

### تست Endpoint های ادمین

```bash
# لیست تمام کاربران (نیاز به احراز هویت دارد)
curl -k -X GET "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN"

# دریافت آمار سیستم
curl -k -X GET "https://91.92.206.217:8000/admin/stats" \
  -H "Authorization: Bearer $TOKEN"

# لیست تمام کلاینت‌ها
curl -k -X GET "https://91.92.206.217:8000/admin/clients" \
  -H "Authorization: Bearer $TOKEN"
```

---

## ۴. تست API سرور Proxy

### بررسی سلامت

```bash
curl -k https://91.92.206.217:8001/health
```

### مستندات API

```
https://91.92.206.217:8001/docs
```

### تست ارسال پیام (با گواهینامه کلاینت)

**توجه:** Proxy نیاز به احراز هویت TLS متقابل با گواهینامه کلاینت معتبر دارد.

```bash
# تست با گواهینامه کلاینت (اگر دارید)
curl -k -X POST "https://91.92.206.217:8001/messages" \
  --cert /path/to/client.crt \
  --key /path/to/client.key \
  --cacert /path/to/ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+1234567890",
    "message_body": "Test message"
  }'
```

---

## ۵. تست اتصال به پایگاه داده

### بررسی اتصال به پایگاه داده

```bash
ssh -p 2223 root@91.92.206.217 'mysql -u systemuser -p"MsgBrckr#TnN$2025" -D message_system -e "SELECT COUNT(*) as user_count FROM users;"'
```

### بررسی وجود کاربر ادمین

```bash
ssh -p 2223 root@91.92.206.217 'mysql -u systemuser -p"MsgBrckr#TnN$2025" -D message_system -e "SELECT id, email, role, is_active FROM users WHERE role=\"ADMIN\";"'
```

**خروجی مورد انتظار:**
```
+----+-------------------+-------+-----------+
| id | email             | role  | is_active |
+----+-------------------+-------+-----------+
|  1 | admin@example.com | admin |         1 |
+----+-------------------+-------+-----------+
```

---

## ۶. تست اتصال به Redis

### بررسی اتصال به Redis

```bash
ssh -p 2223 root@91.92.206.217 "redis-cli ping"
```

**خروجی مورد انتظار:**
```
PONG
```

### بررسی صف Redis

```bash
ssh -p 2223 root@91.92.206.217 "redis-cli LLEN message_queue"
```

---

## ۷. تست سرویس Worker

### بررسی وضعیت Worker

```bash
ssh -p 2223 root@91.92.206.217 "systemctl status worker.service --no-pager | head -15"
```

### مانیتورینگ لاگ‌های Worker

```bash
ssh -p 2223 root@91.92.206.217 "journalctl -u worker.service -f"
```

Worker باید به طور مداوم Redis را برای پیام‌ها بررسی کرده و آن‌ها را پردازش کند.

---

## ۸. تست جریان کامل پیام (End-to-End)

### مرحله ۱: تولید گواهینامه کلاینت

```bash
# اتصال SSH به سرور
ssh -p 2223 root@91.92.206.217

# رفتن به دایرکتوری main_server
cd /opt/message_broker/main_server
source ../venv/bin/activate

# تولید گواهینامه کلاینت تست
python3 admin_cli.py cert generate test_client

# گواهینامه در مسیر زیر ایجاد می‌شود:
# /opt/message_broker/main_server/certs/clients/test_client/
```

### مرحله ۲: دانلود فایل‌های گواهینامه

```bash
# از ماشین محلی خود، فایل‌های گواهینامه را دانلود کنید
scp -P 2223 root@91.92.206.217:/opt/message_broker/main_server/certs/clients/test_client/test_client.crt ./
scp -P 2223 root@91.92.206.217:/opt/message_broker/main_server/certs/clients/test_client/test_client.key ./
scp -P 2223 root@91.92.206.217:/opt/message_broker/main_server/certs/ca.crt ./
```

### مرحله ۳: ارسال پیام از طریق Proxy

```bash
curl -k -X POST "https://91.92.206.217:8001/messages" \
  --cert test_client.crt \
  --key test_client.key \
  --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+1234567890",
    "message_body": "Test message from client"
  }'
```

**پاسخ مورد انتظار:**
```json
{
  "message_id": "uuid-here",
  "status": "queued",
  "phone_number": "+1234567890",
  "message_body": "Test message from client",
  "created_at": "2025-11-08T..."
}
```

### مرحله ۴: بررسی پردازش پیام

```bash
# بررسی اینکه پیام پردازش شده است (از طریق API)
curl -k -X GET "https://91.92.206.217:8000/admin/messages" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.'
```

---

## ۹. تست مدیریت کاربران

### ایجاد کاربر جدید از طریق API

```bash
curl -k -X POST "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "password": "TestPass123!",
    "role": "user"
  }'
```

### لیست تمام کاربران

```bash
curl -k -X GET "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.'
```

---

## ۱۰. تست عملکرد

### بررسی منابع سیستم

```bash
ssh -p 2223 root@91.92.206.217 "top -bn1 | head -20"
```

### بررسی استفاده از منابع سرویس‌ها

```bash
ssh -p 2223 root@91.92.206.217 "systemctl status main_server proxy worker portal --no-pager | grep -E '(Memory:|CPU:)'"
```

### مانیتورینگ فایل‌های لاگ

```bash
# لاگ‌های سرور اصلی
ssh -p 2223 root@91.92.206.217 "tail -f /opt/message_broker/logs/main_server.log"

# لاگ‌های Proxy
ssh -p 2223 root@91.92.206.217 "tail -f /opt/message_broker/logs/proxy.log"

# لاگ‌های Worker
ssh -p 2223 root@91.92.206.217 "tail -f /opt/message_broker/logs/worker.log"
```

---

## ۱۱. عیب‌یابی

### سرویس راه‌اندازی نمی‌شود

```bash
# بررسی وضعیت سرویس
ssh -p 2223 root@91.92.206.217 "systemctl status <service_name>"

# بررسی لاگ‌های تفصیلی
ssh -p 2223 root@91.92.206.217 "journalctl -u <service_name> -n 50 --no-pager"

# راه‌اندازی مجدد سرویس
ssh -p 2223 root@91.92.206.217 "systemctl restart <service_name>"
```

### مشکلات اتصال به پایگاه داده

```bash
# تست اتصال به پایگاه داده
ssh -p 2223 root@91.92.206.217 'mysql -u systemuser -p"MsgBrckr#TnN$2025" -D message_system -e "SELECT 1;"'

# بررسی وضعیت پایگاه داده
ssh -p 2223 root@91.92.206.217 "systemctl status mysql"
```

### مشکلات اتصال به Redis

```bash
# تست اتصال به Redis
ssh -p 2223 root@91.92.206.217 "redis-cli ping"

# بررسی وضعیت Redis
ssh -p 2223 root@91.92.206.217 "systemctl status redis"
```

### پورتال قابل دسترسی نیست

1. **بررسی اینکه فایروال پورت 8080 را مسدود کرده است:**
   - بررسی قوانین فایروال ارائه‌دهنده ابری
   - اطمینان از باز بودن پورت 8080 برای ترافیک ورودی

2. **بررسی اینکه سرویس در حال اجرا است:**
   ```bash
   ssh -p 2223 root@91.92.206.217 "systemctl status portal"
   ```

3. **بررسی اینکه پورت در حال گوش دادن است:**
   ```bash
   ssh -p 2223 root@91.92.206.217 "netstat -tlnp | grep 8080"
   ```

### مشکلات گواهینامه

```bash
# بررسی وجود گواهینامه‌ها
ssh -p 2223 root@91.92.206.217 "ls -la /opt/message_broker/main_server/certs/"

# بررسی اعتبار گواهینامه
ssh -p 2223 root@91.92.206.217 "openssl x509 -in /opt/message_broker/main_server/certs/server.crt -text -noout | head -20"
```

---

## ۱۲. چک‌لیست سریع تست

- [ ] تمام سرویس‌ها در حال اجرا هستند (`systemctl status`)
- [ ] پورت‌های 8000، 8001، 8080 در حال گوش دادن هستند (`netstat`)
- [ ] پورتال قابل دسترسی است (`http://91.92.206.217:8080`)
- [ ] می‌توان با اطلاعات ادمین به پورتال وارد شد
- [ ] تست سلامت API سرور اصلی موفق است (`/health`)
- [ ] تست سلامت API Proxy موفق است (`/health`)
- [ ] اتصال به پایگاه داده کار می‌کند (MySQL)
- [ ] اتصال به Redis کار می‌کند (`redis-cli ping`)
- [ ] می‌توان کاربران را از طریق API ایجاد کرد
- [ ] می‌توان گواهینامه کلاینت تولید کرد
- [ ] می‌توان پیام را از طریق Proxy ارسال کرد (با گواهینامه)
- [ ] Worker پیام‌ها را از صف پردازش می‌کند

---

## ۱۳. نمونه‌های تست API

### اسکریپت کامل تست API

```bash
#!/bin/bash

SERVER="91.92.206.217"
PORT_MAIN="8000"
PORT_PROXY="8001"
PORTAL="8080"
EMAIL="admin@example.com"
PASSWORD="AdminPass123!"

echo "=== Testing Message Broker System ==="

# 1. Health Checks
echo -e "\n1. Testing Health Endpoints..."
curl -k -s "https://${SERVER}:${PORT_MAIN}/health" | jq '.'
curl -k -s "https://${SERVER}:${PORT_PROXY}/health" | jq '.'

# 2. Login and Get Token
echo -e "\n2. Authenticating..."
TOKEN=$(curl -k -s -X POST "https://${SERVER}:${PORT_MAIN}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" \
  | jq -r '.access_token')

if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
  echo "✓ Authentication successful"
else
  echo "✗ Authentication failed"
  exit 1
fi

# 3. Get User Info
echo -e "\n3. Getting Current User Info..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/auth/me" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

# 4. List Users
echo -e "\n4. Listing All Users..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/admin/users" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

# 5. Get System Statistics
echo -e "\n5. Getting System Statistics..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/admin/stats" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

# 6. List Clients
echo -e "\n6. Listing Clients..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/admin/clients" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

echo -e "\n=== Testing Complete ==="
```

این فایل را به عنوان `test_api.sh` ذخیره کنید، آن را قابل اجرا کنید و اجرا کنید:

```bash
chmod +x test_api.sh
./test_api.sh
```

---

## ۱۴. مانیتورینگ و لاگ‌ها

### مانیتورینگ بلادرنگ لاگ‌ها

```bash
# مانیتورینگ تمام سرویس‌ها
ssh -p 2223 root@91.92.206.217 "journalctl -f -u main_server -u proxy -u worker -u portal"

# مانیتورینگ سرویس خاص
ssh -p 2223 root@91.92.206.217 "journalctl -u main_server -f"
```

### بررسی فایل‌های لاگ

```bash
# لیست فایل‌های لاگ
ssh -p 2223 root@91.92.206.217 "ls -lh /opt/message_broker/logs/"

# مشاهده لاگ‌های اخیر
ssh -p 2223 root@91.92.206.217 "tail -100 /opt/message_broker/logs/main_server.log"
```

---

## ۱۵. تست امنیت

### تست پیکربندی SSL/TLS

```bash
# تست اتصال SSL
openssl s_client -connect 91.92.206.217:8000 -servername 91.92.206.217

# بررسی جزئیات گواهینامه
echo | openssl s_client -connect 91.92.206.217:8000 2>/dev/null | openssl x509 -noout -text
```

### تست احراز هویت

- تلاش برای دسترسی به endpoint های محافظت شده بدون token
- بررسی انقضای JWT token
- تست با اطلاعات نامعتبر

---

## ۱۶. تست بار (اختیاری)

### تست بار ساده با Apache Bench

```bash
# نصب ab (Apache Bench) اگر موجود نیست
# در Ubuntu/Debian: sudo apt install apache2-utils

# تست endpoint سلامت
ab -n 100 -c 10 -k https://91.92.206.217:8000/health

# تست endpoint احراز هویت شده (نیاز به token دارد)
ab -n 100 -c 10 -k -H "Authorization: Bearer $TOKEN" https://91.92.206.217:8000/admin/stats
```

---

## خلاصه

پس از تکمیل این تست‌ها، باید موارد زیر را تأیید کرده باشید:

1. ✅ تمام سرویس‌ها در حال اجرا و سالم هستند
2. ✅ پورتال قابل دسترسی است و ورود کار می‌کند
3. ✅ endpoint های API به درستی پاسخ می‌دهند
4. ✅ اتصالات پایگاه داده و Redis کار می‌کنند
5. ✅ ارسال و پردازش پیام کار می‌کند
6. ✅ مدیریت کاربران به درستی عمل می‌کند
7. ✅ تولید و مدیریت گواهینامه کار می‌کند

اگر هر تستی ناموفق بود، به بخش عیب‌یابی مراجعه کنید یا لاگ‌های سرویس را برای پیام‌های خطای تفصیلی بررسی کنید.

---

## مراحل بعدی

- **سخت‌سازی تولید:**
  - به‌روزرسانی فایل `.env` با رمزهای تولید
  - تغییر رمز عبور پیش‌فرض ادمین
  - پیکربندی گواهینامه‌های SSL مناسب
  - تنظیم قوانین فایروال
  - پیکربندی استراتژی پشتیبان‌گیری

- **تنظیم مانیتورینگ:**
  - تنظیم تجمیع لاگ
  - پیکربندی هشدارها
  - تنظیم مانیتورینگ عملکرد

- **مقیاس‌پذیری:**
  - پیکربندی چندین نمونه Worker
  - تنظیم load balancing برای Proxy
  - پیکربندی replication پایگاه داده در صورت نیاز

