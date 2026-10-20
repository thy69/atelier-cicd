#!/usr/bin/env bash
# Construit l'image finale puis l'exporte en fichier .tar.
# Ce fichier est l'ARTEFACT transmis aux étapes suivantes du pipeline :
# on construit une seule fois, on teste, scanne et publie ce même binaire.
source "$(dirname "$0")/common.sh"

# Lien image -> dépôt de code source (traçabilité, et rattachement du package
# au dépôt sur GitHub Container Registry). Fourni par la CI si disponible.
labels=()
if [ -n "${SOURCE_URL:-}" ]; then
  labels+=(--label "org.opencontainers.image.source=$SOURCE_URL")
fi

log "Construction de $IMAGE_NAME:$IMAGE_TAG (version $APP_VERSION, commit $GIT_SHA)"
docker build \
  --target runtime \
  --build-arg PYTHON_VERSION="$PYTHON_VERSION" \
  --build-arg APP_VERSION="$APP_VERSION" \
  --build-arg GIT_SHA="$GIT_SHA" \
  ${labels[@]+"${labels[@]}"} \
  -t "$IMAGE_NAME:$IMAGE_TAG" \
  "$ROOT_DIR"

log "Export de l'image vers $OUT_DIR/image.tar"
docker save "$IMAGE_NAME:$IMAGE_TAG" -o "$OUT_DIR/image.tar"
echo "$IMAGE_NAME:$IMAGE_TAG" > "$OUT_DIR/image-ref.txt"
ls -lh "$OUT_DIR/image.tar"
