# SBOM du paquet Windows avec Syft (exécutable Windows, sans Docker).
#
# Entrée : out\atelier-cicd-*-win-x64.zip (produit par package.ps1)
# Sorties : out\sbom.cdx.json, out\sbom.spdx.json, out\sbom.txt
#
# On analyse le contenu du livrable (le zip décompressé), pas le dépôt :
# la SBOM décrit ce qui est réellement livré.
. "$PSScriptRoot\common.ps1"

$zip = Get-ChildItem -Path $OutDir -Filter 'atelier-cicd-*-win-x64.zip' | Select-Object -First 1
if (-not $zip) { throw "ECHEC : aucun paquet atelier-cicd-*-win-x64.zip dans $OutDir" }

$syft = Get-AnchoreTool 'syft' $Versions['SYFT_VERSION']

$content = Join-Path $OutDir 'sbom-contenu'
if (Test-Path $content) { Remove-Item -Recurse -Force $content }
Expand-Archive -Path $zip.FullName -DestinationPath $content

Write-Step "SBOM de $($zip.Name) (Syft $($Versions['SYFT_VERSION']))"
Invoke-Native $syft @("dir:$content",
    '--source-name', 'atelier-cicd', '--source-version', $AppVersion,
    '-o', "cyclonedx-json=$(Join-Path $OutDir 'sbom.cdx.json')",
    '-o', "spdx-json=$(Join-Path $OutDir 'sbom.spdx.json')",
    '-o', "table=$(Join-Path $OutDir 'sbom.txt')")

$table = Get-Content (Join-Path $OutDir 'sbom.txt')
Write-Step "Composants trouvés : $($table.Count - 1)"
$table | Write-Host
