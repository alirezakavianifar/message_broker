# Troubleshooting MySQL Authentication Error

## Error Message
```
pymysql.err.OperationalError: (1045, "Access denied for user 'systemuser'@'localhost' (using password: YES)")
```

## Common Causes

1. **MySQL user doesn't exist**
2. **Wrong password**
3. **Environment variables not set**
4. **.env file missing or incorrect**

## Step-by-Step Fix

### Step 1: Verify MySQL is Running

```bash
sudo systemctl status mysql
# or
sudo systemctl status mariadb
```

If not running:
```bash
sudo systemctl start mysql
sudo systemctl enable mysql
```

### Step 2: Check if Database User Exists

```bash
sudo mysql -u root -p
```

In MySQL prompt:
```sql
SELECT user, host FROM mysql.user WHERE user = 'systemuser';
```

If the user doesn't exist, you'll see an empty result. Continue to Step 3.

### Step 3: Create Database and User

If the user doesn't exist, create it:

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create user (replace 'YourPassword123!' with your actual password)
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'YourPassword123!';

-- Grant privileges
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;

-- Verify
SELECT user, host FROM mysql.user WHERE user = 'systemuser';

-- Exit
EXIT;
```

### Step 4: Test Connection Manually

```bash
mysql -u systemuser -p message_system
# Enter the password you just set
# If successful, type EXIT; to leave
```

If this fails, the user/password is incorrect. Go back to Step 3.

### Step 5: Create or Update .env File

```bash
cd /opt/message_broker

# Create .env file with correct credentials
cat > .env << 'EOF'
# Database Configuration
DATABASE_URL=mysql+pymysql://systemuser:YourPassword123!@localhost:3306/message_system
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=YourPassword123!
EOF

# Set secure permissions
chmod 600 .env
```

**⚠️ IMPORTANT**: Replace `YourPassword123!` with the actual password you set in Step 3!

### Step 6: Set Environment Variables

Before running Alembic, export the environment variables:

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Set database environment variables
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=message_system
export DB_USER=systemuser
export DB_PASSWORD=YourPassword123!  # Use your actual password!

# Now run migrations
alembic upgrade head
```

### Step 7: Alternative - Use Migration Script

The `run_migrations.sh` script automatically loads from .env:

```bash
cd /opt/message_broker
source venv/bin/activate
export PYTHONPATH=/opt/message_broker
bash run_migrations.sh
```

## Quick Fix Script

Run this complete setup script:

```bash
#!/bin/bash
# Complete MySQL setup for Message Broker

# Get password from user
read -sp "Enter MySQL root password: " ROOT_PASS
echo
read -sp "Enter password for 'systemuser' database user: " DB_PASS
echo

# Login to MySQL and create user
mysql -u root -p"$ROOT_PASS" << EOF
CREATE DATABASE IF NOT EXISTS message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'systemuser'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EOF

# Create .env file
cat > /opt/message_broker/.env << ENVEOF
DATABASE_URL=mysql+pymysql://systemuser:${DB_PASS}@localhost:3306/message_system
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=${DB_PASS}
ENVEOF

chmod 600 /opt/message_broker/.env

echo "Database setup complete!"
echo "Now run: cd /opt/message_broker/main_server && source ../venv/bin/activate && export PYTHONPATH=/opt/message_broker && alembic upgrade head"
```

## Verify Everything Works

```bash
# Test MySQL connection
mysql -u systemuser -p message_system -e "SHOW TABLES;"

# If tables exist, you're good!
# If no tables, run migrations:
cd /opt/message_broker/main_server
source ../venv/bin/activate
export PYTHONPATH=/opt/message_broker
export DB_USER=systemuser
export DB_PASSWORD=YourPassword123!  # Your actual password
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=message_system
alembic upgrade head
```

## Common Issues

### Issue: "Access denied" even with correct password

**Solution**: The user might exist but with wrong password. Reset it:
```sql
ALTER USER 'systemuser'@'localhost' IDENTIFIED BY 'NewPassword123!';
FLUSH PRIVILEGES;
```

### Issue: User exists but can't access database

**Solution**: Re-grant privileges:
```sql
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
```

### Issue: Environment variables not being read

**Solution**: Make sure you're exporting them in the same shell session:
```bash
# Don't do this:
export DB_PASSWORD=pass
# Then open new terminal and run alembic

# Do this:
export DB_PASSWORD=pass
alembic upgrade head  # In same session
```

### Issue: .env file not being read

**Solution**: The `run_migrations.sh` script reads .env, but if running `alembic` directly, you need to export variables manually or use `python-dotenv` to load .env.

## Still Having Issues?

1. Check MySQL error log: `sudo tail -f /var/log/mysql/error.log`
2. Verify MySQL is listening: `sudo netstat -tlnp | grep 3306`
3. Test connection with mysql client: `mysql -u systemuser -p`
4. Check .env file exists and has correct format: `cat /opt/message_broker/.env`

