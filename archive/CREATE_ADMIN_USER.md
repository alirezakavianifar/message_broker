# How to Create a New Admin User

## Quick Command

```bash
# 1. Transfer the script to the server
scp -P 2223 create_admin_user.py root@91.92.206.217:/tmp/create_admin_user.py

# 2. Run it to create the admin user
ssh -p 2223 root@91.92.206.217 "cd /opt/message_broker && source venv/bin/activate && python3 /tmp/create_admin_user.py <email> '<password>'"

# 3. Clean up (optional)
ssh -p 2223 root@91.92.206.217 "rm /tmp/create_admin_user.py"
```

## Example

```bash
# Create admin user with email "admin2@example.com" and password "SecurePass123!"
scp -P 2223 create_admin_user.py root@91.92.206.217:/tmp/create_admin_user.py
ssh -p 2223 root@91.92.206.217 "cd /opt/message_broker && source venv/bin/activate && python3 /tmp/create_admin_user.py admin2@example.com 'SecurePass123!'"
```

## Requirements

- Password must be at least 8 characters long
- Email must be unique (not already in the database)
- Script uses the same password hashing method as the API (bcrypt directly)

## Alternative: Using the API

If you already have an admin token, you can also create users via the API:

**Using curl:**
```bash
TOKEN="your_jwt_token_here"
curl -k -X POST "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newadmin@example.com",
    "password": "SecurePass123!",
    "role": "admin"
  }'
```

**Using PowerShell:**
```powershell
$headers = @{
    Authorization = "Bearer $TOKEN"
}
$body = @{
    email = "newadmin@example.com"
    password = "SecurePass123!"
    role = "admin"
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://91.92.206.217:8000/admin/users" `
    -Method POST `
    -Headers $headers `
    -Body $body `
    -ContentType "application/json" `
    -SkipCertificateCheck
```

## Notes

- The `create_admin_user.py` script uses bcrypt directly (same as the API), avoiding the passlib 72-byte limit issue
- The script automatically loads the `.env` file from `/opt/message_broker/.env`
- The script checks if the user already exists before creating

