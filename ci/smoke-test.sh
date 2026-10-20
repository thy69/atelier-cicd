#!/usr/bin/env bash
# Smoke test : démarre le conteneur et vérifie qu'il répond.
#
# Usage : smoke-test.sh [image] [environnement]
#
# Les requêtes HTTP partent d'un conteneur curl branché sur le réseau du
# conteneur testé : aucune dépendance au réseau de la machine. Le script
# fonctionne à l'identique sur un runner GitHub, en Docker-in-Docker
# (GitLab), sur un agent Azure DevOps ou Jenkins, et en local.
source "$(dirname "$0")/common.sh"

IMAGE_REF="${1:-$IMAGE_NAME:$IMAGE_TAG}"
APP_ENV="${2:-smoke}"
NAME="smoke-$APP_ENV-$$"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

http() {
  docker run --rm --network "container:$NAME" "curlimages/curl:$CURL_VERSION" \
    -fsS --max-time 2 "http://localhost:8080$1"
}

log "Démarrage de $IMAGE_REF (APP_ENV=$APP_ENV)"
docker run -d --name "$NAME" -e APP_ENV="$APP_ENV" "$IMAGE_REF" >/dev/null

ready=0
for _ in $(seq 1 30); do
  if http /health >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  echo "ECHEC : /health ne répond pas après 30 s. Logs du conteneur :" >&2
  docker logs "$NAME" >&2 || true
  exit 1
fi

echo "GET /health  -> $(http /health)"
echo "GET /version -> $(http /version)"
echo "GET /        -> $(http /)"
log "Smoke test OK"
