================================================================================
MESSAGE BROKER TEST KIT
================================================================================

This package contains everything you need to test the Message Broker System.

CONTENTS:
---------
1. test_message_broker.py    - Comprehensive test script
2. TEST_SCRIPT_GUIDE.md      - Complete user guide and documentation

QUICK START:
-----------
1. Extract this zip file to a directory
2. Read TEST_SCRIPT_GUIDE.md for detailed instructions
3. Ensure Python 3.8+ is installed
4. Install dependencies: pip install httpx redis
5. Run: python test_message_broker.py --direct

BASIC USAGE:
-----------
# Simple test (no certificates needed)
python test_message_broker.py --direct

# Custom message
python test_message_broker.py --direct --message "Your test message"

# Full test with certificates
python test_message_broker.py --message "Test message"

REQUIREMENTS:
------------
- Python 3.8+
- httpx package: pip install httpx
- redis package: pip install redis
- Message Broker services running (Main Server, Proxy, Worker, Portal)
- MySQL and Redis running

For detailed instructions, see TEST_SCRIPT_GUIDE.md

================================================================================
Version: 1.0.0
Last Updated: November 2025
================================================================================

