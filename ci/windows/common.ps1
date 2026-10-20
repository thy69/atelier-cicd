# Variables et fonctions communes aux scripts CI Windows (sans Docker).
#
# Même principe que ci/common.sh : chaque variable peut être surchargée par
# l'outil de CI ou en local. Compatible Windows PowerShell 5.1 et PowerShell 7.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest beaucoup plus rapide
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$CiDir = Split-Path -Parent $PSScriptRoot
$RootDir = Split-Path -Parent $CiDir

# Versions des outils : même fichier que la version Linux
$Versions = @{}
Get-Content (Join-Path $CiDir 'versions.env') | Where-Object { $_ -match '^\s*([A-Z_]+)=(.+)$' } | ForEach-Object {
    $Versions[$Matches[1]] = $Matches[2].Trim()
}

function Get-EnvOrDefault([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) { return $Default }
    return $value
}

# Identité du build
$GitSha = Get-EnvOrDefault 'GIT_SHA' ''
if (-not $GitSha) {
    try { $GitSha = (git -C $RootDir rev-parse --short=8 HEAD 2>$null) } catch { $GitSha = '' }
    if (-not $GitSha) { $GitSha = 'local' }
}
$AppVersion = Get-EnvOrDefault 'APP_VERSION' '0.0.0-dev'
$ScanFailOn = Get-EnvOrDefault 'SCAN_FAIL_ON' 'high'

# Dossiers de travail
$OutDir = Get-EnvOrDefault 'OUT_DIR' (Join-Path $RootDir 'out')
$ToolsDir = Join-Path $RootDir '.tools'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Nom du paquet livré
$PackageName = "atelier-cicd-$AppVersion-win-x64"
$PackageZip = Join-Path $OutDir "$PackageName.zip"

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message"
}

# Lance une commande native et échoue si son code retour n'est pas 0
# (PowerShell ne le fait pas tout seul pour les exécutables).
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @())
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ECHEC : $Command $($Arguments -join ' ') (code $LASTEXITCODE)"
    }
}

# Télécharge (une seule fois) un outil Anchore à la version épinglée.
function Get-AnchoreTool([string]$Name, [string]$Version) {
    $bare = $Version.TrimStart('v')
    $dir = Join-Path $ToolsDir "$Name-$bare"
    $exe = Join-Path $dir "$Name.exe"
    if (-not (Test-Path $exe)) {
        Write-Step "Téléchargement de $Name $Version"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $zip = Join-Path $dir "$Name.zip"
        $url = "https://github.com/anchore/$Name/releases/download/$Version/${Name}_${bare}_windows_amd64.zip"
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        Remove-Item $zip
    }
    return $exe
}
