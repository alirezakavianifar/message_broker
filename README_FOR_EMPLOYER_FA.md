# راهنمای تست Thin Client - برای کارفرما

## خلاصه

این بسته شامل تمام فایل‌ها و مستندات لازم برای تست پیاده‌سازی **Thin Client** سیستم Message Broker است.

## فایل ZIP چیست؟

فایل `thin_client_documentation.zip` شامل:
- ✅ مستندات کامل (انگلیسی و فارسی)
- ✅ اسکریپت‌های آماده استفاده (Windows و Linux)
- ✅ فایل‌های نمونه تست
- ✅ راهنمای گام به گام

## چگونه شروع کنیم؟

### مرحله 1: استخراج فایل

فایل `thin_client_documentation.zip` را استخراج کنید.

### مرحله 2: خواندن راهنما

**اگر فارسی را ترجیح می‌دهید:**
1. فایل `README_FA.md` را باز کنید (راهنمای کامل فارسی)
2. یا `QUICK_START_FA.md` را بخوانید (راهنمای سریع)

**اگر انگلیسی را ترجیح می‌دهید:**
1. فایل `README.md` را باز کنید
2. یا `QUICK_START.md` را بخوانید

### مرحله 3: تست

1. مطمئن شوید سرور Proxy در حال اجرا است
2. گواهینامه‌های کلاینت را آماده کنید
3. اسکریپت مناسب پلتفرم خود را اجرا کنید:
   - Windows → `scripts/send_message_windows.ps1`
   - Linux/Mac → `scripts/send_message_linux.sh`

## ساختار فایل‌ها

```
thin_client_package/
├── README_FA.md              ← راهنمای فارسی (شروع از اینجا)
├── QUICK_START_FA.md         ← راهنمای سریع فارسی
├── README.md                 ← راهنمای انگلیسی
├── QUICK_START.md            ← راهنمای سریع انگلیسی
│
├── docs/                     ← مستندات
│   ├── API_REFERENCE.md      ← مستندات API
│   ├── PLATFORM_GUIDE.md     ← راهنمای پلتفرم
│   └── USER_MANUAL.md        ← راهنمای کاربر
│
├── scripts/                  ← اسکریپت‌های آماده
│   ├── send_message_windows.ps1
│   ├── send_message_linux.sh
│   └── send_message_python.py
│
└── tests/                    ← فایل‌های تست
    ├── test_message_valid.json
    └── test_message_invalid.json
```

## پیش‌نیازها

قبل از تست:
- ✅ سرور Proxy باید در حال اجرا باشد
- ✅ Redis باید در حال اجرا باشد
- ✅ گواهینامه‌های کلاینت باید موجود باشد

## مثال تست سریع

### Windows:

```powershell
cd scripts
.\send_message_windows.ps1 -Sender "+989123456789" -Message "تست"
```

### Linux/Mac:

```bash
cd scripts
./send_message_linux.sh "+989123456789" "تست"
```

## اگر مشکلی پیش آمد

1. بخش "خطاهای متداول" در `README_FA.md` را بررسی کنید
2. فایل `docs/PLATFORM_GUIDE.md` را برای راهنمای پلتفرم بخوانید
3. با تیم فنی تماس بگیرید

## نتیجه مورد انتظار

اگر تست موفق باشد، پاسخ JSON زیر را دریافت می‌کنید:

```json
{
  "message_id": "...",
  "status": "queued",
  "client_id": "...",
  "queued_at": "..."
}
```

این یعنی پیام با موفقیت ارسال شد! ✅

---

**نکته مهم**: برای شروع، فایل `README_FA.md` را باز کنید و دستورالعمل‌ها را دنبال کنید.

