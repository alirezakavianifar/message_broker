FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for MySQL
RUN apt-get update && apt-get install -y \
    default-libmysqlclient-dev \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the worker and main_server packages
COPY worker/ worker/
COPY main_server/ main_server/

# Set Python path to include the root directory
ENV PYTHONPATH=/app

# Start the worker
CMD ["python", "worker/worker.py"]
