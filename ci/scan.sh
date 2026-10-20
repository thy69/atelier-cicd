#!/usr/bin/env bash
# Analyse de vulnérabilités de la SBOM avec Grype : c'est une "quality gate".
#
# Le script échoue (code retour non nul) si au moins une vulnérabilité de
# sévérité >= $SCAN_FAIL_ON possède un correctif disponible (--only-fixed).
# Les vulnérabilités sans correctif sont affichées mais ne bloquent pas :
# on ne bloque que ce que l'équipe peut réellement corriger.
#
# Entrée : out/sbom.cdx.json (produit par sbom.sh)
# Sortie : out/vulnerabilites.txt
source "$(dirname "$0")/common.sh"

if [ ! -f "$OUT_DIR/sbom.cdx.json" ]; then
  echo "ECHEC : $OUT_DIR/sbom.cdx.json introuvable (lancer sbom.sh d'abord)" >&2
  exit 1
fi

log "Scan de vulnérabilités (Grype $GRYPE_VERSION, blocage à partir de : $SCAN_FAIL_ON)"
# La SBOM est envoyée sur l'entrée standard (pas de montage de fichier).
# La base de vulnérabilités est gardée dans un volume Docker nommé : elle
# n'est téléchargée qu'une fois par machine (utile en local et sur les
# agents permanents ; un runner GitHub, éphémère, la télécharge à chaque fois).
docker run --rm -i \
  -e GRYPE_DB_CACHE_DIR=/grype-db \
  -v grype-db:/grype-db \
  "anchore/grype:$GRYPE_VERSION" \
  --only-fixed \
  --fail-on "$SCAN_FAIL_ON" \
  -o table \
  < "$OUT_DIR/sbom.cdx.json" | tee "$OUT_DIR/vulnerabilites.txt"

log "Aucune vulnérabilité corrigeable de sévérité >= $SCAN_FAIL_ON"
