# Lint + tests unitaires, directement sur l'agent Windows (sans Docker).
#
# Prérequis sur l'agent : la version de Python indiquée dans .python-version
# (installée par la CI, par exemple avec actions/setup-python).
# Les dépendances sont installées dans un environnement virtuel jetable :
# rien n'est installé "en global" sur l'agent.
. "$PSScriptRoot\common.ps1"

$venv = Join-Path $RootDir '.venv-ci'
Write-Step "Environnement virtuel Python ($venv)"
Invoke-Native python @('-m', 'venv', '--clear', $venv)
$py = Join-Path $venv 'Scripts\python.exe'

Write-Step 'Installation des dépendances'
Invoke-Native $py @('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check',
    '-r', (Join-Path $RootDir 'requirements.txt'),
    '-r', (Join-Path $RootDir 'requirements-dev.txt'))

Push-Location $RootDir
try {
    Write-Step 'Lint (ruff)'
    Invoke-Native $py @('-m', 'ruff', 'check', '.')

    Write-Step 'Tests unitaires (pytest)'
    Invoke-Native $py @('-m', 'pytest', '-v', "--junitxml=$(Join-Path $OutDir 'tests.xml')")
}
finally {
    Pop-Location
}

Write-Step 'Lint et tests OK'
