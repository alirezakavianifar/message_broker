"""
Simple Test Demo - Verify test framework is working
"""
import sys

print("\n" + "="*70)
print("MESSAGE BROKER TEST FRAMEWORK - DEMO")
print("="*70 + "\n")

print("Checking test dependencies...\n")

# Check imports
dependencies = {
    "httpx": False,
    "redis": False,
    "pymysql": False,
    "asyncio": False
}

for dep in dependencies:
    try:
        __import__(dep)
        dependencies[dep] = True
        print(f"[OK] {dep:15} - Installed")
    except ImportError:
        print(f"[FAIL] {dep:15} - NOT FOUND")

print("\n" + "-"*70)

all_installed = all(dependencies.values())
if all_installed:
    print("\n[SUCCESS] All test dependencies are installed!")
    print("\nTest framework is ready.")
    print("\nNext steps:")
    print("  1. Install MySQL and Redis")
    print("  2. Initialize database (alembic upgrade head)")
    print("  3. Generate certificates (init_ca.bat)")
    print("  4. Start all services")
    print("  5. Run: .\\run_all_tests.ps1")
    sys.exit(0)
else:
    print("\n[FAIL] Some dependencies are missing")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)

