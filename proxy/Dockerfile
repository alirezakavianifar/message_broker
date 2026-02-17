FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY proxy/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the proxy package
COPY proxy/ proxy/

# Set Python path to include the root directory
ENV PYTHONPATH=/app

# Expose the proxy port
EXPOSE 8001

# Start the proxy
CMD ["uvicorn", "proxy.app:app", "--host", "0.0.0.0", "--port", "8001"]
