
**21. I need to change a user’s role on the admin portal.**

❌ Not available in **Portal UI** – currently present in:

**Existing methods:**

**1. From Database:**

```sql
UPDATE users SET role = 'admin' WHERE email = 'user@example.com';
-- or --
UPDATE users SET role = 'user' WHERE email = 'user@example.com';
```

**2. From Admin CLI:**

```bash
# Currently not available in admin_cli.py
# Needs to be added
```

**3. Adding to Portal:**
You can add the endpoint:

```
PUT /admin/users/{user_id}/role
```

**Existing code:**

* In `main_server/api.py` – lines 1078–1149 only:
  `POST /admin/users` exists to create a user.
* There is no `PUT` endpoint to change the role.

---
