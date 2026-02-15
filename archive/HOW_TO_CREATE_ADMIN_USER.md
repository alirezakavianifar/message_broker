# How to Create an Admin User

This guide will help you create a new admin user for the Message Broker system.

## Prerequisites

- SSH access to the server (IP: `91.92.206.217`, Port: `2223`)
- The `create_admin_user.py` script file

## Step-by-Step Instructions

### Step 1: Transfer the Script to the Server

From your local machine, run:

```bash
scp -P 2223 create_admin_user.py root@91.92.206.217:/tmp/create_admin_user.py
```

You will be prompted for the root password.

### Step 2: Run the Script

Execute the following command to create the admin user:

```bash
ssh -p 2223 root@91.92.206.217 "cd /opt/message_broker && source venv/bin/activate && python3 /tmp/create_admin_user.py <EMAIL> '<PASSWORD>'"
```

**Replace:**
- `<EMAIL>` with the email address for the new admin user (e.g., `admin@example.com`)
- `<PASSWORD>` with the desired password (must be at least 8 characters)

**Example:**
```bash
ssh -p 2223 root@91.92.206.217 "cd /opt/message_broker && source venv/bin/activate && python3 /tmp/create_admin_user.py admin@mycompany.com 'MySecurePass123!'"
```

### Step 3: Verify Success

If successful, you should see output like:

```
[OK] Admin user created successfully!
     Email: admin@mycompany.com
     ID: 3
     Role: admin
     Active: True
```

### Step 4: Clean Up (Optional)

After creating the user, you can remove the temporary script:

```bash
ssh -p 2223 root@91.92.206.217 "rm /tmp/create_admin_user.py"
```

## Important Notes

- **Password Requirements:** The password must be at least 8 characters long
- **Email Uniqueness:** The email address must be unique (not already in the database)
- **Password Security:** Choose a strong password for production use
- **Access:** The new admin user can immediately log in to the portal at `http://91.92.206.217:8080`

## Troubleshooting

### Error: "User with email ... already exists"
- The email address is already registered. Use a different email or check existing users.

### Error: "Password must be at least 8 characters"
- Your password is too short. Use a password with at least 8 characters.

### Error: "DATABASE_URL not found in environment"
- The `.env` file is missing or in the wrong location. Contact the system administrator.

### Error: "Access denied for user 'systemuser'"
- Database connection issue. Verify the database is running and credentials are correct.

## Alternative: Using the Web Portal

If you already have admin access to the portal:

1. Log in to `http://91.92.206.217:8080`
2. Navigate to **Users** → **Add User**
3. Fill in the form:
   - Email
   - Password (min 8 characters)
   - Role: Select **Admin**
4. Click **Create User**

## Alternative: Using the API

If you have an admin JWT token, you can create users via the API:

```bash
curl -k -X POST "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "SecurePass123!",
    "role": "admin"
  }'
```

## Need Help?

If you encounter any issues, contact your system administrator or refer to the main documentation.

