#!/bin/bash
#
# Message Broker Client - Bash Script Example
# 
# This script demonstrates how to send messages using curl (no Python required).
# 
# Usage:
#   ./send_message.sh "+1234567890" "Hello, world!"
#
# Or with custom certificates:
#   ./send_message.sh "+1234567890" "Hello, world!" \
#     --cert ./certs/client.crt \
#     --key ./certs/client.key \
#     --ca ./certs/ca.crt \
#     --url https://your-server:8001
#

set -euo pipefail

# Default values
PROXY_URL="${PROXY_URL:-https://localhost:8001}"
CERT_FILE="${CERT_FILE:-./certs/client.crt}"
KEY_FILE="${KEY_FILE:-./certs/client.key}"
CA_FILE="${CA_FILE:-./certs/ca.crt}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
SENDER_NUMBER=""
MESSAGE_BODY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --cert)
            CERT_FILE="$2"
            shift 2
            ;;
        --key)
            KEY_FILE="$2"
            shift 2
            ;;
        --ca)
            CA_FILE="$2"
            shift 2
            ;;
        --url|--proxy-url)
            PROXY_URL="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 <sender_number> <message> [options]"
            echo ""
            echo "Arguments:"
            echo "  sender_number    Phone number in E.164 format (e.g., +1234567890)"
            echo "  message          Message body (max 1000 characters)"
            echo ""
            echo "Options:"
            echo "  --cert FILE      Path to client certificate (default: ./certs/client.crt)"
            echo "  --key FILE       Path to client private key (default: ./certs/client.key)"
            echo "  --ca FILE        Path to CA certificate (default: ./certs/ca.crt)"
            echo "  --url URL        Proxy server URL (default: https://localhost:8001)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  PROXY_URL        Proxy server URL"
            echo "  CERT_FILE        Client certificate path"
            echo "  KEY_FILE         Client private key path"
            echo "  CA_FILE          CA certificate path"
            exit 0
            ;;
        *)
            if [[ -z "$SENDER_NUMBER" ]]; then
                SENDER_NUMBER="$1"
            elif [[ -z "$MESSAGE_BODY" ]]; then
                MESSAGE_BODY="$1"
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}" >&2
                echo "Use --help for usage information" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SENDER_NUMBER" ]] || [[ -z "$MESSAGE_BODY" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}" >&2
    echo "Usage: $0 <sender_number> <message> [options]" >&2
    echo "Use --help for more information" >&2
    exit 1
fi

# Validate sender number format (basic check)
if [[ ! "$SENDER_NUMBER" =~ ^\+[0-9]{7,15}$ ]]; then
    echo -e "${RED}Error: Invalid sender number format${NC}" >&2
    echo "Sender number must be in E.164 format: +[country code][number]" >&2
    echo "Example: +1234567890" >&2
    exit 1
fi

# Validate message length
if [[ ${#MESSAGE_BODY} -gt 1000 ]]; then
    echo -e "${RED}Error: Message body exceeds 1000 characters${NC}" >&2
    exit 1
fi

# Check certificate files exist
if [[ ! -f "$CERT_FILE" ]]; then
    echo -e "${RED}Error: Certificate file not found: $CERT_FILE${NC}" >&2
    exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
    echo -e "${RED}Error: Private key file not found: $KEY_FILE${NC}" >&2
    exit 1
fi

if [[ ! -f "$CA_FILE" ]]; then
    echo -e "${RED}Error: CA certificate file not found: $CA_FILE${NC}" >&2
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is not installed${NC}" >&2
    echo "Install curl to use this script, or use another HTTP client" >&2
    exit 1
fi

# Prepare JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg sender "$SENDER_NUMBER" \
    --arg body "$MESSAGE_BODY" \
    '{sender_number: $sender, message_body: $body}')

# If jq is not available, use printf (less safe but works)
if [[ $? -ne 0 ]] || ! command -v jq &> /dev/null; then
    # Escape JSON special characters in message body
    ESCAPED_BODY=$(printf '%s' "$MESSAGE_BODY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    JSON_PAYLOAD="{\"sender_number\":\"$SENDER_NUMBER\",\"message_body\":\"$ESCAPED_BODY\"}"
fi

# Display information
echo -e "${YELLOW}Sending message...${NC}"
echo "  Sender: $SENDER_NUMBER"
echo "  Message: $MESSAGE_BODY"
echo "  Proxy: $PROXY_URL"
echo "  Certificate: $CERT_FILE"
echo "----------------------------------------"

# Send request
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    "$PROXY_URL/api/v1/messages" \
    --cert "$CERT_FILE" \
    --key "$KEY_FILE" \
    --cacert "$CA_FILE" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

# Extract HTTP status code (last line) and body (all but last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Check response
if [[ "$HTTP_CODE" -eq 202 ]]; then
    echo -e "${GREEN}✓ Message sent successfully!${NC}"
    if command -v jq &> /dev/null; then
        echo "$BODY" | jq .
    else
        echo "$BODY"
    fi
    exit 0
else
    echo -e "${RED}✗ Error sending message (HTTP $HTTP_CODE)${NC}" >&2
    echo "$BODY" >&2
    exit 1
fi

