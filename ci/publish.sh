#!/usr/bin/env bash
# Publie l'image dans un registre.
#
# Usage : publish.sh [tag supplémentaire...]
#   ex. publish.sh main          -> pousse :sha-xxxx et :main
#       publish.sh latest        -> pousse :v1.2.0 et :latest (sur un tag git)
#
# Variables attendues (fournies par la CI) :
#   IMAGE_NAME        nom complet, ex. ghcr.io/mon-org/mon-repo
#   REGISTRY          ex. ghcr.io
#   REGISTRY_USER     identifiant
#   REGISTRY_PASSWORD jeton (secret de la CI, jamais en clair dans le dépôt)
#
# Sortie : out/image-digest.txt contient la référence immuable
#          (nom@sha256:...) à utiliser pour déployer.
source "$(dirname "$0")/common.sh"

log "Chargement de l'image depuis l'artefact"
docker load -i "$OUT_DIR/image.tar"

registry_login

log "Publication de $IMAGE_NAME:$IMAGE_TAG"
docker push "$IMAGE_NAME:$IMAGE_TAG"

for extra_tag in "$@"; do
  log "Ajout du tag $extra_tag"
  docker tag "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE_NAME:$extra_tag"
  docker push "$IMAGE_NAME:$extra_tag"
done

digest_ref="$(docker inspect --format '{{index .RepoDigests 0}}' "$IMAGE_NAME:$IMAGE_TAG")"
echo "$digest_ref" > "$OUT_DIR/image-digest.txt"
log "Image publiée : $digest_ref"
