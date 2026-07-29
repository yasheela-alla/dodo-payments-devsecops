# syntax=docker/dockerfile:1
# --- build stage: install deps into an isolated prefix -----------------------
FROM python:3.12-slim-bookworm AS build

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- runtime stage -----------------------------------------------------------
FROM python:3.12-slim-bookworm

# Drop to an unprivileged, well-known UID/GID so the manifest can pin runAsUser.
RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid 10001 --home-dir /app --no-create-home app

WORKDIR /app
COPY --from=build /install /usr/local
COPY app.py .

USER 10001:10001
EXPOSE 8080

# gunicorn: real WSGI server; 2 workers, bind all interfaces inside the pod.
# tmp dir is an emptyDir mount at runtime so the root FS can stay read-only.
ENV GUNICORN_CMD_ARGS="--bind=0.0.0.0:8080 --workers=2 --timeout=30 --worker-tmp-dir=/tmp"
ENTRYPOINT ["gunicorn", "app:app"]
