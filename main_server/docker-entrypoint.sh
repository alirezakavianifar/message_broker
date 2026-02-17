#!/bin/bash
set -e

# Run database migrations
echo "Running database migrations..."
python -m alembic upgrade head || echo "Migration failed, but continuing... (check DB connectivity)"

# Start the server
echo "Starting Main Server..."
exec uvicorn main_server.api:app --host 0.0.0.0 --port 8000
