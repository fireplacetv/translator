# Development image only. translator is not deployed as a container.
# PYTHON_VERSION defaults to the oldest supported version so that code which
# needs a newer Python fails here first.
ARG PYTHON_VERSION=3.8
FROM python:${PYTHON_VERSION}-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends sdcv \
    && rm -rf /var/lib/apt/lists/*

# Dev-only tooling; the app itself has no runtime dependencies.
RUN pip install --no-cache-dir pytest

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    STARDICT_DATA_DIR=/data \
    LANG=C.UTF-8 \
    TERM=xterm-256color

WORKDIR /app
CMD ["python", "-m", "translator"]
