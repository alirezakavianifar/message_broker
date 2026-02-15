# Fix: Missing DB_PASSWORD Environment Variable

## Problem

When running migrations or starting services, you get a database connection error even though:
- ✅ MySQL/MariaDB user exists (`systemuser`)
- ✅ Environment variables are set (DB_HOST, DB_PORT, DB_NAME, DB_USER)
- ❌ **DB_PASSWORD is missing or incorrect**

## Root Cause

The Alembic migration script (`main_server/alembic/env.py`) requires `DB_PASSWORD` environment variable. If it's not set, it defaults to `"StrongPass123!"`, which may not match your actual database password.

## Solution

### Step 1: Verify Your Actual Database Password

First, test if you can connect with the password you set:

```bash
# Test connection with your password
mysql -u systemuser -p message_system
# Enter your password when prompted
# If successful, type EXIT; to leave
```

If this fails, you need to reset the password (see Step 2).

### Step 2: Set or Reset Database Password (if needed)

If you don't know the password or it's incorrect:

```bash
# Login as root
sudo mysql -u root -p
# or for MariaDB
sudo mariadb -u root -p
```

In MySQL/MariaDB prompt:

```sql
-- Reset password for systemuser
ALTER USER 'systemuser'@'localhost' IDENTIFIED BY 'YourActualPassword123!';

-- Verify privileges
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;

-- Test the new password
SELECT user, host FROM mysql.user WHERE user = 'systemuser';

EXIT;
```

### Step 3: Set DB_PASSWORD Environment Variable

**Option A: Export in Current Session**

```bash
cd /opt/message_broker
source venv/bin/activate

# Set the password (replace with your actual password)
export DB_PASSWORD='YourActualPassword123!'

# Verify it's set
echo $DB_PASSWORD

# Now try running migrations
cd main_server
alembic upgrade head
```

**Option B: Add to .env File (Recommended)**

```bash
cd /opt/message_broker

# Edit .env file
nano .env
```

Add or update these lines in `.env`:

```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=YourActualPassword123!  # <-- ADD THIS LINE

# Also add DATABASE_URL for API services
DATABASE_URL=mysql+pymysql://systemuser:YourActualPassword123!@localhost:3306/message_system
```

**Important:** Replace `YourActualPassword123!` with your actual database password.

Save the file (Ctrl+X, then Y, then Enter in nano).

### Step 4: Load .env File and Run Migrations

```bash
cd /opt/message_broker
source venv/bin/activate

# Load .env file
export $(cat .env | grep -v '^#' | xargs)

# Verify all variables are set
echo "DB_HOST: $DB_HOST"
echo "DB_PORT: $DB_PORT"
echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"
echo "DB_PASSWORD: $DB_PASSWORD"  # Should show your password

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Run migrations
cd main_server
alembic upgrade head
```

### Step 5: Alternative - Use DATABASE_URL Instead

If you prefer using `DATABASE_URL` instead of individual variables:

```bash
cd /opt/message_broker

# Edit .env file
nano .env
```

Add this line (replace password with your actual password):

```bash
DATABASE_URL=mysql+pymysql://systemuser:YourActualPassword123!@localhost:3306/message_system
```

Then modify the migration script to use DATABASE_URL, or use this workaround:

```bash
cd /opt/message_broker
source venv/bin/activate

# Extract components from DATABASE_URL
export $(cat .env | grep DATABASE_URL | sed 's/DATABASE_URL=mysql+pymysql:\/\///' | sed 's/@/ /' | awk -F'[:/]' '{print "DB_USER="$1" DB_PASSWORD="$2" DB_HOST="$3" DB_PORT="$4" DB_NAME="$5}')

# Verify
echo "DB_USER: $DB_USER"
echo "DB_PASSWORD: $DB_PASSWORD"
echo "DB_HOST: $DB_HOST"
echo "DB_PORT: $DB_PORT"
echo "DB_NAME: $DB_NAME"

# Run migrations
cd main_server
export PYTHONPATH=/opt/message_broker
alembic upgrade head
```

## Quick Fix Script

Create a helper script to load environment and run migrations:

```bash
cd /opt/message_broker
cat > run_migrations_with_env.sh << 'EOF'
#!/bin/bash
# Script to run migrations with proper environment loading

cd /opt/message_broker
source venv/bin/activate

# Load .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Verify required variables
if [ -z "$DB_PASSWORD" ]; then
    echo "[ERROR] DB_PASSWORD is not set in .env file"
    echo "Please add DB_PASSWORD=your_password to .env"
    exit 1
fi

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Run migrations
cd main_server
alembic upgrade head
EOF

chmod +x run_migrations_with_env.sh

# Run it
./run_migrations_with_env.sh
```

## Verification

After setting DB_PASSWORD, verify the connection works:

```bash
cd /opt/message_broker
source venv/bin/activate
export $(cat .env | grep -v '^#' | xargs)
export PYTHONPATH=/opt/message_broker

# Test database connection
python3 -c "
import os
from main_server.database import build_database_url, test_connection

url = build_database_url(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '3306')),
    database=os.getenv('DB_NAME', 'message_system'),
    user=os.getenv('DB_USER', 'systemuser'),
    password=os.getenv('DB_PASSWORD', 'StrongPass123!')
)

if test_connection(url):
    print('[OK] Database connection successful!')
else:
    print('[FAIL] Database connection failed!')
"
```

## Common Issues

### Issue 1: Password Contains Special Characters

If your password contains special characters like `!`, `@`, `#`, `$`, etc., you need to:

1. **Quote the password in .env:**
   ```bash
   DB_PASSWORD='MyP@ssw0rd!#'
   ```

2. **Or URL-encode special characters in DATABASE_URL:**
   ```bash
   # Password: MyP@ssw0rd!#
   # URL-encoded: MyP%40ssw0rd%21%23
   DATABASE_URL=mysql+pymysql://systemuser:MyP%40ssw0rd%21%23@localhost:3306/message_system
   ```

### Issue 2: .env File Not Being Loaded

Make sure you're loading the .env file:

```bash
# Method 1: Export all variables
export $(cat .env | grep -v '^#' | xargs)

# Method 2: Source a script that loads .env
source <(cat .env | grep -v '^#' | sed 's/^/export /')

# Method 3: Use python-dotenv (if installed)
python3 -c "from dotenv import load_dotenv; import os; load_dotenv(); print(os.getenv('DB_PASSWORD'))"
```

### Issue 3: MariaDB vs MySQL Differences

MariaDB is compatible with MySQL, but if you encounter issues:

```bash
# Check which one you're using
mysql --version
# or
mariadb --version

# Both should work, but if you have issues, try:
# In .env, use mysql+pymysql:// (works for both)
DATABASE_URL=mysql+pymysql://systemuser:password@localhost:3306/message_system
```

## Summary

The fix is simple:

1. ✅ **Set DB_PASSWORD** in your `.env` file with your actual database password
2. ✅ **Load the .env file** before running migrations: `export $(cat .env | grep -v '^#' | xargs)`
3. ✅ **Verify** the password is correct by testing: `mysql -u systemuser -p message_system`

After this, your migrations should work!

