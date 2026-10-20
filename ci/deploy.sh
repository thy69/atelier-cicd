#!/usr/bin/env bash
# Déploiement SIMULÉ sur un environnement.
#
# Usage : deploy.sh <environnement> <image@sha256:...>
#
# Dans la vraie vie, cette étape serait par exemple :
#   kubectl set image deployment/api api=<image>      (Kubernetes)
#   helm upgrade --install api ./chart --set image=<image>
#   az containerapp update --image <image> ...        (Azure)
#   ssh serveur "docker compose pull && docker compose up -d"
#
# Ici, on récupère l'image depuis le registre (preuve que la publication a
# fonctionné), on la démarre avec la configuration de l'environnement et on
# vérifie qu'elle répond. Le principe est identique : déployer une image
# IMMUABLE, identifiée par son digest, déjà testée et scannée.
source "$(dirname "$0")/common.sh"

ENV_NAME="${1:?Usage : deploy.sh <environnement> <image>}"
IMAGE_REF="${2:?Usage : deploy.sh <environnement> <image>}"

registry_login

log "Récupération de $IMAGE_REF depuis le registre"
docker pull "$IMAGE_REF"

log "Déploiement (simulé) sur l'environnement : $ENV_NAME"
bash "$CI_DIR/smoke-test.sh" "$IMAGE_REF" "$ENV_NAME"

{
  echo "environnement=$ENV_NAME"
  echo "image=$IMAGE_REF"
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT_DIR/deploiement-$ENV_NAME.txt"

log "Déploiement $ENV_NAME OK"
