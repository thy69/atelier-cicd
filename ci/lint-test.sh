#!/usr/bin/env bash
# Lint + tests unitaires, exécutés DANS le conteneur (stage "test" du Dockerfile).
# Le runner n'a besoin d'aucun outil Python : seulement Docker.
source "$(dirname "$0")/common.sh"

log "Lint et tests unitaires (Python $PYTHON_VERSION)"
docker build \
  --target test \
  --progress=plain \
  --build-arg PYTHON_VERSION="$PYTHON_VERSION" \
  -t "$IMAGE_NAME:test" \
  "$ROOT_DIR"

log "Lint et tests OK"
