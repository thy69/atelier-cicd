#!/usr/bin/env bash
# Variables et fonctions communes à tous les scripts CI.
#
# Chaque variable peut être surchargée par l'outil de CI (GitHub Actions,
# GitLab CI, Azure DevOps, Jenkins...) ou en local. C'est ce qui rend les
# scripts portables : l'outil de CI fournit le contexte, les scripts font
# le travail.
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$CI_DIR/.." && pwd)"
# shellcheck source=versions.env
source "$CI_DIR/versions.env"

# Identité du build
GIT_SHA="${GIT_SHA:-$(git -C "$ROOT_DIR" rev-parse --short=8 HEAD 2>/dev/null || echo local)}"
APP_VERSION="${APP_VERSION:-0.0.0-dev}"

# Nom de l'image : ghcr.io/mon-org/mon-repo, registry.gitlab.com/..., monacr.azurecr.io/...
# Les registres imposent des minuscules.
IMAGE_NAME="$(echo "${IMAGE_NAME:-atelier-cicd}" | tr '[:upper:]' '[:lower:]')"
IMAGE_TAG="${IMAGE_TAG:-sha-$GIT_SHA}"

# Version de Python utilisée pour construire l'image (cf. bonus "matrix")
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

# Politique de sécurité : sévérité à partir de laquelle le scan bloque
SCAN_FAIL_ON="${SCAN_FAIL_ON:-high}"

# Dossier des fichiers produits (image exportée, SBOM, rapports)
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
mkdir -p "$OUT_DIR"

log() {
  printf '\n==> %s\n' "$*"
}

# Connexion au registre si des identifiants sont fournis par la CI.
registry_login() {
  if [ -n "${REGISTRY_PASSWORD:-}" ]; then
    log "Connexion au registre ${REGISTRY:?REGISTRY doit être défini}"
    echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "${REGISTRY_USER:?}" --password-stdin
  fi
}
