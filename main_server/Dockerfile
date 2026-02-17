FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for MySQL and healthchecks
RUN apt-get update && apt-get install -y \
    default-libmysqlclient-dev \
    build-essential \
    pkg-config \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY main_server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the main_server package
COPY main_server/ main_server/

# Set Python path to include the root directory
ENV PYTHONPATH=/app

# Expose the server port
EXPOSE 8000

# Script to handle migrations and start the server
RUN chmod +x main_server/docker-entrypoint.sh

ENTRYPOINT ["main_server/docker-entrypoint.sh"]
