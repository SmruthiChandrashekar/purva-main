# Backend API (FastAPI) for Azure Container Apps.
# The website (frontend/) stays on Vercel and is not part of this image.
#
# Build:  docker build --platform linux/amd64 -t purva-main .
# Run:    docker run --rm -p 8080:8080 --env-file backend/.env purva-main
# Check:  curl http://localhost:8080/health

# ---- Stage 1: install Python dependencies into a virtualenv ----
FROM python:3.11-slim-bookworm AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Same light dependency list Render uses (no PyTorch)
COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

# ---- Stage 2: small runtime image ----
FROM python:3.11-slim-bookworm

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

# Non-root user
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /home/app --create-home app

COPY --from=build /opt/venv /opt/venv

WORKDIR /app
COPY backend ./backend
COPY agents ./agents
COPY rag ./rag

# Code stays root-owned (read-only for the app). The app may write only:
#  - /app itself (backend/main.py appends to debug_error.log in the working directory)
#  - rag/chroma_final (Chroma opens its SQLite index read/write)
# Both are local disk: anything written there is lost on every deploy or restart.
RUN chown app:app /app \
 && chown -R app:app /app/rag/chroma_final

USER app

EXPOSE 8080

# Reads $PORT (default 8080, the same port as the placeholder image Azure starts with).
# --proxy-headers so client IPs and https come from the Container Apps ingress (X-Forwarded-*).
CMD ["sh", "-c", "exec uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8080} --proxy-headers --forwarded-allow-ips='*'"]
