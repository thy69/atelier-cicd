# Smoke test du paquet Windows : on l'installe (décompression) dans un
# dossier vierge, on le démarre et on vérifie qu'il répond.
#
# On teste le zip produit, pas le code source : c'est le livrable qui
# compte. Pour un MSI, on ferait de même avec une installation silencieuse
# (msiexec /i paquet.msi /qn) sur une VM propre.
. "$PSScriptRoot\common.ps1"

$zip = Get-ChildItem -Path $OutDir -Filter 'atelier-cicd-*-win-x64.zip' | Select-Object -First 1
if (-not $zip) { throw "ECHEC : aucun paquet atelier-cicd-*-win-x64.zip dans $OutDir (lancer package.ps1)" }

$installDir = Join-Path ([IO.Path]::GetTempPath()) ("smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
Write-Step "Installation de $($zip.Name) dans $installDir"
Expand-Archive -Path $zip.FullName -DestinationPath $installDir

$info = Get-Content (Join-Path $installDir 'version.json') -Raw | ConvertFrom-Json
$env:PYTHONPATH = "$installDir;$(Join-Path $installDir 'lib')"
$env:APP_VERSION = $info.version
$env:GIT_SHA = $info.commit
$env:APP_ENV = Get-EnvOrDefault 'APP_ENV' 'smoke'
# Port configurable : sur certains postes, 8080 est réservé (Hyper-V, WSL).
$port = Get-EnvOrDefault 'SMOKE_PORT' '8080'
$baseUrl = "http://127.0.0.1:$port"

Write-Step "Démarrage sur le port $port (APP_ENV=$env:APP_ENV)"
$logOut = Join-Path $OutDir 'smoke-stdout.log'
$logErr = Join-Path $OutDir 'smoke-stderr.log'
$process = Start-Process -FilePath python -PassThru -NoNewWindow `
    -WorkingDirectory $installDir `
    -ArgumentList '-m', 'flask', '--app', 'app.main', 'run', '--host', '127.0.0.1', '--port', $port `
    -RedirectStandardOutput $logOut -RedirectStandardError $logErr

try {
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 2 | Out-Null
            $ready = $true
            break
        }
        catch { Start-Sleep -Seconds 1 }
    }
    if (-not $ready) {
        Get-Content $logErr -ErrorAction SilentlyContinue | Write-Host
        throw 'ECHEC : /health ne répond pas après 30 s'
    }

    foreach ($route in '/health', '/version', '/') {
        $body = Invoke-RestMethod -Uri "$baseUrl$route" -TimeoutSec 2 | ConvertTo-Json -Compress
        Write-Host "GET $route -> $body"
    }
    Write-Step 'Smoke test OK'
}
finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Remove-Item -Recurse -Force $installDir -ErrorAction SilentlyContinue
}
