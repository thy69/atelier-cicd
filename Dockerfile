# syntax=docker/dockerfile:1
#
# Un seul Dockerfile, trois étages (multi-stage) :
#   base    : Python + dépendances d'exécution
#   test    : base + outils de qualité, lance le lint et les tests unitaires
#   runtime : image finale, minimale, sans outils de test, utilisateur non root
#
# Le pipeline n'a besoin que de Docker : il ne sait pas que l'application est
# en Python. Remplacer Python par Java, .NET ou Node ne change que ce fichier.

ARG PYTHON_VERSION=3.12

FROM python:${PYTHON_VERSION}-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

# ---------------------------------------------------------------- test
FROM base AS test
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt
COPY . .
RUN ruff check . && pytest -v

# ---------------------------------------------------------------- runtime
FROM base AS runtime
ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}
LABEL org.opencontainers.image.title="atelier-cicd" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"
COPY app/ ./app/
RUN useradd --uid 10001 --no-create-home appuser
USER 10001
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app.main:app"]
