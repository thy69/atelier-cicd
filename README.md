# Atelier CI/CD : modèle de départ

Ce dépôt sert de support à l'atelier CI/CD. Il contient une mini API web et
tout ce qu'il faut pour la construire, la tester et la livrer. Il ne contient
**pas encore de pipeline** : c'est vous qui allez l'écrire.

Le guide pas à pas est dans [ATELIER.md](ATELIER.md).

## Ce qu'il y a dedans

| Chemin | Rôle |
|---|---|
| `app/` | L'application (Python / Flask, une poignée de lignes) |
| `tests/` | Tests unitaires (pytest) |
| `Dockerfile` | Build multi-stage : `test` (lint + tests) et `runtime` (image finale) |
| `requirements*.txt` | Dépendances épinglées |
| `ci/*.sh` | Les étapes du pipeline, en scripts portables (Linux, Docker) |
| `ci/windows/*.ps1` | Les mêmes étapes pour un agent Windows, sans Docker (variante) |
| `ci/versions.env` | Versions des outils (Syft, Grype, curl) |
| `.python-version` | Version de Python, pour la variante Windows (toolchain épinglée) |
| `docs/PORTAGE.md` | Correspondance GitHub Actions / GitLab CI / Azure DevOps / Jenkins / TeamCity |
| `docs/ADAPTATION-TEAMCITY.md` | L'atelier sur TeamCity (Kotlin DSL) |

Vous n'avez pas besoin de connaître Python. L'application pourrait être en
Java, .NET ou Node : seul le `Dockerfile` changerait. Le pipeline, lui, ne
connaît que Docker et les scripts de `ci/`.

## Les scripts CI

| Script | Fait quoi | Produit |
|---|---|---|
| `ci/lint-test.sh` | Lint + tests unitaires dans le conteneur | rien (échoue si un test casse) |
| `ci/build.sh` | Construit l'image finale et l'exporte | `out/image.tar` |
| `ci/smoke-test.sh` | Démarre l'image et appelle `/health` | rien (échoue si pas de réponse) |
| `ci/sbom.sh` | Inventaire des composants (Syft) | `out/sbom.cdx.json`, `out/sbom.spdx.json` |
| `ci/scan.sh` | Vulnérabilités connues (Grype) | `out/vulnerabilites.txt` (échoue si vulnérabilité grave corrigeable) |
| `ci/publish.sh` | Pousse l'image dans un registre | `out/image-digest.txt` |
| `ci/deploy.sh` | Déploiement simulé sur un environnement | `out/deploiement-<env>.txt` |

## Lancer en local (facultatif)

Il faut Docker et un shell bash (Linux, macOS, WSL sous Windows).

```bash
bash ci/lint-test.sh
bash ci/build.sh
bash ci/smoke-test.sh
bash ci/sbom.sh
bash ci/scan.sh
```

Le pipeline exécute exactement les mêmes commandes. Ce qui marche sur votre
poste marche sur le runner, et inversement.

Variante Windows, sans Docker (PowerShell, Python 3.12 dans le PATH) :

```powershell
powershell -ExecutionPolicy Bypass -File ci\windows\test.ps1
powershell -ExecutionPolicy Bypass -File ci\windows\package.ps1
powershell -ExecutionPolicy Bypass -File ci\windows\smoke-test.ps1
powershell -ExecutionPolicy Bypass -File ci\windows\sbom.ps1
powershell -ExecutionPolicy Bypass -File ci\windows\scan.ps1
```

## L'API

| Route | Réponse |
|---|---|
| `GET /` | message de bienvenue et nom de l'environnement |
| `GET /hello/<nom>` | message personnalisé |
| `GET /health` | `{"status": "ok"}` |
| `GET /version` | version et commit injectés au build |
