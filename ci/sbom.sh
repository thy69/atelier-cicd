#!/usr/bin/env bash
# Génère la SBOM (Software Bill of Materials) de l'image avec Syft.
#
# Entrée : out/image.tar (produit par build.sh)
# Sorties : out/sbom.cdx.json  (format CycloneDX)
#           out/sbom.spdx.json (format SPDX)
#           out/sbom.txt       (tableau lisible)
#
# Syft tourne lui-même dans un conteneur : rien à installer sur le runner.
# Les fichiers sont copiés dans et hors du conteneur (docker cp) plutôt que
# montés en volume : ainsi le script marche aussi en Docker-in-Docker.
source "$(dirname "$0")/common.sh"

if [ ! -f "$OUT_DIR/image.tar" ]; then
  echo "ECHEC : $OUT_DIR/image.tar introuvable (lancer build.sh ou récupérer l'artefact)" >&2
  exit 1
fi

log "SBOM de l'image (Syft $SYFT_VERSION)"
cid="$(docker create "anchore/syft:$SYFT_VERSION" \
  docker-archive:/image.tar \
  -o cyclonedx-json=/sbom.cdx.json \
  -o spdx-json=/sbom.spdx.json \
  -o table=/sbom.txt)"
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT

docker cp "$OUT_DIR/image.tar" "$cid:/image.tar"
docker start --attach "$cid"
for f in sbom.cdx.json sbom.spdx.json sbom.txt; do
  docker cp "$cid:/$f" "$OUT_DIR/$f"
done

log "Composants trouvés : $(($(wc -l < "$OUT_DIR/sbom.txt") - 1))"
grep -Ei '^(NAME|flask|werkzeug|jinja2|gunicorn|openssl|libc6) ' "$OUT_DIR/sbom.txt" || true
