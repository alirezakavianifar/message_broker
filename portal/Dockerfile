FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY portal/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the portal and main_server packages
COPY portal/ portal/
# portal might need main_server for shared logic/models if any
COPY main_server/ main_server/

# Set Python path to include the root directory
ENV PYTHONPATH=/app

# Expose the portal port
EXPOSE 8080

# Start the portal
CMD ["uvicorn", "portal.app:app", "--host", "0.0.0.0", "--port", "8080"]
