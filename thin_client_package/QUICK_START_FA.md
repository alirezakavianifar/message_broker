# راهنمای سریع - Thin Client Testing

## شروع سریع در 3 مرحله

### مرحله 1: آماده‌سازی

```bash
# 1. بررسی سرور (Windows)
curl.exe http://localhost:8001/api/v1/health

# یا (Linux/Mac)
curl http://localhost:8001/api/v1/health
```

اگر پاسخ گرفتید ✅، سرور در حال اجرا است.

### مرحله 2: انتخاب و اجرای اسکریپت

#### Windows:

```powershell
cd scripts
.\send_message_windows.ps1 -Sender "+989123456789" -Message "تست"
```

#### Linux/Mac:

```bash
cd scripts
chmod +x send_message_linux.sh
./send_message_linux.sh "+989123456789" "تست"
```

### مرحله 3: بررسی نتیجه

اگر موفق بودید، پاسخ زیر را می‌بینید:

```json
{
  "message_id": "...",
  "status": "queued",
  ...
}
```

## فرمت شماره تلفن

شماره تلفن باید:
- ✅ با `+` شروع شود
- ✅ کد کشور داشته باشد (مثال: `+98` برای ایران)
- ✅ فقط اعداد باشد (بدون فاصله یا خط تیره)

**مثال صحیح**: `+989123456789`  
**مثال اشتباه**: `09123456789` (بدون +)

## نیاز به کمک؟

- خطا دارید؟ → `README_FA.md` را بخوانید (بخش خطاهای متداول)
- جزئیات بیشتر؟ → `docs/API_REFERENCE.md` را ببینید
- مشکل پلتفرم؟ → `docs/PLATFORM_GUIDE.md` را بررسی کنید

