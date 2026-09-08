FROM python:3.12-slim

# System deps: ffmpeg for audio decoding, build tools for native extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install uv via pip — more reliable than multi-stage copy in CI environments
RUN pip install uv

WORKDIR /app

# Install dependencies first so Docker can cache this layer
COPY pyproject.toml uv.lock ./
RUN uv export --frozen --no-dev --no-hashes --no-emit-project -o requirements.txt \
    && pip install -r requirements.txt

# Copy application code
COPY rhotacism/ ./rhotacism/
COPY server.py ./

# Models download to these paths on first run; mount a Railway volume here
# to avoid re-downloading on every redeploy.
ENV WHISPER_CACHE=/cache/whisper
ENV HF_HOME=/cache/huggingface
ENV XDG_CACHE_HOME=/cache

EXPOSE 8000

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
