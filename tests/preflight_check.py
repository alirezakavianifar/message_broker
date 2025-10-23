"""
Pre-flight Check - Verify test environment before running tests
"""

import sys
import importlib
from pathlib import Path

# Colors
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
CYAN = '\033[96m'
RESET = '\033[0m'

def print_header(msg):
    print(f"\n{CYAN}{'='*60}{RESET}")
    print(f"{CYAN}{msg:^60}{RESET}")
    print(f"{CYAN}{'='*60}{RESET}\n")

def print_section(msg):
    print(f"\n{BLUE}{msg}{RESET}")
    print(f"{BLUE}{'-'*60}{RESET}")

def print_pass(msg):
    print(f"  {GREEN}✓{RESET} {msg}")

def print_fail(msg):
    print(f"  {RED}✗{RESET} {msg}")

def print_info(msg):
    print(f"  {YELLOW}ℹ{RESET} {msg}")

def check_python_version():
    """Check Python version"""
    print_section("Python Version")
    version = sys.version_info
    if version >= (3, 8):
        print_pass(f"Python {version.major}.{version.minor}.{version.micro}")
        return True
    else:
        print_fail(f"Python {version.major}.{version.minor}.{version.micro} (requires 3.8+)")
        return False

def check_dependencies():
    """Check required Python packages"""
    print_section("Python Dependencies")
    
    required = [
        "httpx",
        "redis",
        "pymysql",
        "asyncio",
        "cryptography",
        "pydantic",
        "sqlalchemy",
        "fastapi",
        "uvicorn"
    ]
    
    all_good = True
    for package in required:
        try:
            mod = importlib.import_module(package)
            version = getattr(mod, "__version__", "unknown")
            print_pass(f"{package:20s} {version}")
        except ImportError:
            print_fail(f"{package:20s} NOT INSTALLED")
            all_good = False
    
    return all_good

def check_mysql_connection():
    """Check MySQL connection"""
    print_section("MySQL Connection")
    
    try:
        import pymysql
        conn = pymysql.connect(
            host='localhost',
            port=3306,
            user='systemuser',
            password='StrongPass123!',
            database='message_system'
        )
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'message_system'")
        count = cursor.fetchone()[0]
        conn.close()
        
        print_pass(f"Connected to message_system database")
        print_pass(f"Found {count} tables")
        return True
    except Exception as e:
        print_fail(f"Cannot connect to MySQL: {e}")
        return False

def check_redis_connection():
    """Check Redis connection"""
    print_section("Redis Connection")
    
    try:
        import redis
        r = redis.Redis(host='localhost', port=6379, decode_responses=True)
        response = r.ping()
        if response:
            print_pass("Connected to Redis (Memurai)")
            
            # Test basic operations
            test_key = "__test_key__"
            r.set(test_key, "test_value")
            value = r.get(test_key)
            r.delete(test_key)
            
            if value == "test_value":
                print_pass("Redis read/write operations work")
                return True
            else:
                print_fail("Redis read/write test failed")
                return False
        else:
            print_fail("Redis PING failed")
            return False
    except Exception as e:
        print_fail(f"Cannot connect to Redis: {e}")
        return False

def check_certificates():
    """Check certificate files"""
    print_section("Certificates")
    
    cert_locations = [
        ("CA Certificate", Path("../main_server/certs/ca.crt")),
        ("Server Certificate", Path("../main_server/certs/server.crt")),
        ("Server Key", Path("../main_server/certs/server.key")),
        ("Proxy Certificate", Path("../proxy/certs/proxy.crt")),
        ("Proxy Key", Path("../proxy/certs/proxy.key")),
        ("Worker Certificate", Path("../worker/certs/worker.crt")),
        ("Worker Key", Path("../worker/certs/worker.key")),
        ("Test Client Certificate", Path("../client-scripts/certs/test_client.crt")),
        ("Test Client Key", Path("../client-scripts/certs/test_client.key")),
    ]
    
    all_good = True
    for name, path in cert_locations:
        if path.exists():
            size = path.stat().st_size
            print_pass(f"{name:30s} ({size} bytes)")
        else:
            print_fail(f"{name:30s} NOT FOUND")
            all_good = False
    
    return all_good

def check_database_schema():
    """Check database tables"""
    print_section("Database Schema")
    
    try:
        import pymysql
        conn = pymysql.connect(
            host='localhost',
            port=3306,
            user='systemuser',
            password='StrongPass123!',
            database='message_system'
        )
        cursor = conn.cursor()
        
        required_tables = ['users', 'clients', 'messages', 'audit_log', 'alembic_version']
        
        cursor.execute("SHOW TABLES")
        tables = [row[0] for row in cursor.fetchall()]
        
        all_good = True
        for table in required_tables:
            if table in tables:
                cursor.execute(f"SELECT COUNT(*) FROM {table}")
                count = cursor.fetchone()[0]
                print_pass(f"Table '{table}' exists ({count} rows)")
            else:
                print_fail(f"Table '{table}' NOT FOUND")
                all_good = False
        
        conn.close()
        return all_good
    except Exception as e:
        print_fail(f"Cannot check schema: {e}")
        return False

def check_project_structure():
    """Check project directory structure"""
    print_section("Project Structure")
    
    directories = [
        Path("../proxy"),
        Path("../main_server"),
        Path("../worker"),
        Path("../portal"),
        Path("../client-scripts"),
        Path("../monitoring"),
    ]
    
    all_good = True
    for directory in directories:
        if directory.exists():
            print_pass(f"{directory.name:20s}")
        else:
            print_fail(f"{directory.name:20s} NOT FOUND")
            all_good = False
    
    return all_good

def main():
    print_header("PRE-FLIGHT CHECK")
    print_info("Verifying test environment before running tests...")
    
    checks = [
        ("Python Version", check_python_version),
        ("Dependencies", check_dependencies),
        ("MySQL Connection", check_mysql_connection),
        ("Redis Connection", check_redis_connection),
        ("Database Schema", check_database_schema),
        ("Certificates", check_certificates),
        ("Project Structure", check_project_structure),
    ]
    
    results = []
    for name, check_func in checks:
        try:
            result = check_func()
            results.append((name, result))
        except Exception as e:
            print_fail(f"Check failed with error: {e}")
            results.append((name, False))
    
    # Summary
    print_section("Summary")
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = f"{GREEN}✓ PASS{RESET}" if result else f"{RED}✗ FAIL{RESET}"
        print(f"  {name:25s} {status}")
    
    print(f"\n{CYAN}{'='*60}{RESET}")
    if passed == total:
        print(f"{GREEN}✓ ALL CHECKS PASSED ({passed}/{total}){RESET}")
        print(f"{GREEN}  Environment is ready for testing!{RESET}")
        sys.exit(0)
    else:
        print(f"{RED}✗ SOME CHECKS FAILED ({passed}/{total}){RESET}")
        print(f"{YELLOW}  Please fix the issues above before running tests.{RESET}")
        sys.exit(1)

if __name__ == "__main__":
    main()

