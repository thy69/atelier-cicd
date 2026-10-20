# Scan de vulnérabilités de la SBOM avec Grype (exécutable Windows).
#
# Même politique que la version Linux : échec si une vulnérabilité de
# sévérité >= SCAN_FAIL_ON possède un correctif disponible.
#
# Entrée : out\sbom.cdx.json (produit par sbom.ps1)
# Sortie : out\vulnerabilites.txt
. "$PSScriptRoot\common.ps1"

$sbom = Join-Path $OutDir 'sbom.cdx.json'
if (-not (Test-Path $sbom)) { throw "ECHEC : $sbom introuvable (lancer sbom.ps1 d'abord)" }

$grype = Get-AnchoreTool 'grype' $Versions['GRYPE_VERSION']

Write-Step "Scan de vulnérabilités (Grype $($Versions['GRYPE_VERSION']), blocage à partir de : $ScanFailOn)"
& $grype "sbom:$sbom" --only-fixed --fail-on $ScanFailOn -o table |
    Tee-Object -FilePath (Join-Path $OutDir 'vulnerabilites.txt')
if ($LASTEXITCODE -ne 0) {
    throw "ECHEC : vulnérabilités corrigeables de sévérité >= $ScanFailOn (voir le tableau ci-dessus)"
}

Write-Step "Aucune vulnérabilité corrigeable de sévérité >= $ScanFailOn"
