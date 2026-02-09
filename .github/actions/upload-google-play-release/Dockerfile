FROM python:3.11-slim

# Avoid bytecode + ensure stdout is flushed
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install deps (pinned-ish; adjust as you like)
RUN pip install --no-cache-dir \
    google-api-python-client==2.126.0 \
    google-auth==2.29.0 \
    google-auth-httplib2==0.2.0

WORKDIR /app

COPY play_upload.py /app/play_upload.py
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
