# Construit le livrable Windows : un paquet zip "portable", autonome.
#
# Contenu du zip :
#   app\          le code de l'application
#   lib\          les dépendances, installées dans le paquet
#   version.json  version et commit (traçabilité)
#   lancer.ps1    script de démarrage
#
# C'est l'équivalent, pour un livrable Windows, de l'image Docker de la
# version Linux. Dans un vrai projet client lourd, on produirait ici un
# MSI ou un MSIX (WiX, MSIX Packaging Tool, Advanced Installer...), signé.
#
# Le paquet cible Python 3.12 64 bits sur Windows (les dépendances
# compilées en dépendent).
. "$PSScriptRoot\common.ps1"

$staging = Join-Path $OutDir 'package'
Write-Step "Préparation du paquet $PackageName"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

Copy-Item -Recurse (Join-Path $RootDir 'app') (Join-Path $staging 'app')
Get-ChildItem -Path $staging -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force

Write-Step 'Installation des dépendances dans le paquet'
Invoke-Native python @('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check',
    '--no-compile', '--target', (Join-Path $staging 'lib'),
    '-r', (Join-Path $RootDir 'requirements.txt'))

@{ version = $AppVersion; commit = $GitSha } | ConvertTo-Json |
    Set-Content -Encoding UTF8 (Join-Path $staging 'version.json')

@'
# Démarre l'application sur le port 8080.
# Prérequis : Python 3.12 64 bits dans le PATH.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$info = Get-Content (Join-Path $here 'version.json') -Raw | ConvertFrom-Json
$env:PYTHONPATH = "$here;$(Join-Path $here 'lib')"
$env:APP_VERSION = $info.version
$env:GIT_SHA = $info.commit
# Serveur de développement Flask : suffisant pour l'atelier. En production
# sous Windows, on utiliserait par exemple waitress, ou IIS.
python -m flask --app app.main run --host 127.0.0.1 --port 8080
'@ | Set-Content -Encoding UTF8 (Join-Path $staging 'lancer.ps1')

Write-Step "Création de $PackageZip"
if (Test-Path $PackageZip) { Remove-Item -Force $PackageZip }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $PackageZip
Get-Item $PackageZip | Select-Object Name, @{ n = 'Taille (Mo)'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table | Out-String | Write-Host
