# Porter le pipeline vers un autre outil de CI

Le pipeline de l'atelier est écrit pour GitHub Actions, mais toute la
logique est dans les scripts `ci/*.sh`. Porter le pipeline revient à
réécrire le fichier qui enchaîne ces scripts, en général 50 à 150 lignes.

Les portages complets (état final de l'atelier) sont dans la branche
`corrige` du dépôt modèle, dossier `ports/` :
https://github.com/thy69/atelier-cicd/tree/corrige/ports

## Table de correspondance des concepts

| Concept | GitHub Actions | GitLab CI | Azure DevOps | Jenkins | TeamCity |
|---|---|---|---|---|---|
| Fichier du pipeline | `.github/workflows/*.yml` | `.gitlab-ci.yml` | `azure-pipelines.yml` | `Jenkinsfile` | `.teamcity/settings.kts` (Kotlin DSL) |
| Déclencheurs | `on: push / pull_request / schedule` | `workflow: rules`, `rules` | `trigger`, `pr`, `schedules` | job multibranch, webhooks, `triggers {}` | `triggers { vcs {...} }`, `schedule`, sur le dernier build de la chaîne |
| Lancement manuel | `workflow_dispatch` | bouton "Run pipeline", `when: manual` | "Run pipeline", `parameters` | "Build with parameters" | bouton "Run", paramètres avec `ParameterDisplay.PROMPT` |
| Grandes phases | (pas d'objet dédié, les jobs suffisent) | `stages` | `stages` | `stages` | build chain (chaîne de build configurations) |
| Unité d'exécution | `job` | `job` | `job` | `stage` | build configuration (`BuildType`) |
| Commande | `step` (`run:` ou `uses:`) | ligne de `script:` | `step` (`script:` ou `task:`) | `steps { sh '...' }` | `steps { script {...} }`, `powerShell {...}` |
| Ordre et dépendances | `needs:` | `needs:` ou ordre des stages | `dependsOn:` | ordre des stages, `parallel {}` | dépendance `snapshot(...)` |
| Machine d'exécution | runner, `runs-on:` | runner, `tags:` | agent, `pool:` | agent, `agent { label }` | agent, `requirements { ... }` |
| Brique réutilisable | action (`uses:`), reusable workflow | `include:`, CI/CD components | task, template | shared library, plugin | template, fonction ou classe Kotlin, meta-runner |
| Condition | `if:` | `rules: - if:` | `condition:` | `when {}` | `branchFilter`, conditions d'étape (`conditions { }`) |
| Variables | `env:` | `variables:` | `variables:` | `environment {}` | `params { param(...) }`, préfixe `env.` pour l'environnement |
| Secrets | `secrets.NOM` (Settings > Secrets) | variables masquées et protégées | variable group secret, Key Vault | Credentials + `withCredentials` | `password(...)` avec jeton `credentialsJSON:...` |
| Jeton fourni par la plateforme | `GITHUB_TOKEN` | `CI_JOB_TOKEN`, `CI_REGISTRY_PASSWORD` | `System.AccessToken` | aucun | aucun |
| Droits du jeton | `permissions:` | réglages du projet | réglages du projet | sans objet | sans objet |
| Artefacts entre jobs | `upload-artifact` / `download-artifact` | `artifacts:` + `needs:` | `publish:` / `download:` | `stash` / `unstash`, `archiveArtifacts` | `artifactRules` + dépendance `artifacts { }` |
| Rétention | `retention-days:` | `expire_in:` | règles de rétention du projet | `buildDiscarder` | règles de nettoyage (Clean-up rules), builds épinglés |
| Variable de sortie d'un job | `$GITHUB_OUTPUT` + `outputs:` | artefact `reports: dotenv` | `##vso[task.setvariable;isOutput=true]` | `env.X = ...` dans `script {}` | `##teamcity[setParameter ...]` + `%dep.<build>.<param>%` |
| Registre d'images intégré | GitHub Container Registry (`ghcr.io`) | GitLab Container Registry | aucun (Azure Container Registry à part) | aucun (Nexus, Harbor, Artifactory) | aucun (registre de l'entreprise) |
| Environnement | `environment:` | `environment:` | job `deployment` + `environment:` | pas de notion native | build configuration de type `DEPLOYMENT` |
| Approbation avant déploiement | règle "Required reviewers" de l'environnement | `when: manual` ou Protected environment | "Approvals and checks" de l'environnement | étape `input` | build feature `approval` |
| Un seul déploiement à la fois | `concurrency:` | `resource_group:` | check "Exclusive lock" | `disableConcurrentBuilds()`, plugin Lockable Resources | `maxRunningBuilds = 1`, Shared resources |
| Matrice | `strategy.matrix` | `parallel: matrix` | `strategy: matrix` | `matrix {}` | build feature `matrix` |
| Cache | `actions/cache` | `cache:` | tâche `Cache@2` | disque de l'agent, plugins | build feature `buildCache` |
| Protection de branche | Rulesets, branch protection | Protected branches, règles de MR | Branch policies | côté hébergeur Git | côté hébergeur Git, statut publié par Commit Status Publisher |
| Résumé lisible du run | `$GITHUB_STEP_SUMMARY` | rapports de MR | onglet Summary, `##vso` | description du build | onglets du build, rapports HTML en artefacts |
| Docker dans le job | disponible sur `ubuntu-latest` | service `docker:dind` | disponible sur `ubuntu-latest` | agent avec Docker installé | agent avec Docker (`-linux-sudo` + `DOCKER_IN_DOCKER=start`) |
| Agent Windows | `runs-on: windows-2025` | runner Windows (hébergé ou auto-hébergé), `tags:` | `pool: vmImage: windows-2025` | agent Windows, `agent { label 'windows' }` | agent Windows, `contains("teamcity.agent.jvm.os.name", "Windows")` |
| Étape PowerShell | `shell: pwsh` | `script:` sur un runner Windows (PowerShell par défaut) | `- pwsh:` ou tâche `PowerShell@2` | `pwsh '...'` ou `powershell '...'` | `powerShell { }` |
| Agent macOS (iOS) | `runs-on: macos-15` | runner macOS (hébergé, offres payantes) ou auto-hébergé | `pool: vmImage: macOS-15` | agent macOS | agent macOS |

## Méthode de portage, en 6 étapes

1. Repérer les scripts appelés par le pipeline actuel. S'il y a de la
   logique dans le YAML (boucles, calculs, appels d'API), la sortir d'abord
   dans un script.
2. Lister les jobs et leurs dépendances (le graphe). Le dessiner.
3. Recréer ce graphe dans l'outil cible avec la table ci-dessus.
4. Recâbler le contexte : variables fournies par la plateforme (nom de
   branche, tag, SHA), secrets, jeton du registre.
5. Recâbler les artefacts entre jobs.
6. Recréer la configuration hors fichier : environnements, approbations,
   protection de branche, secrets. Elle ne se porte pas avec le YAML.

## Points d'attention par outil

GitLab CI

- Docker passe par le service `docker:dind`. Un conteneur lancé par le job
  tourne dans le démon dind, pas dans le job : `localhost` ne le joint pas,
  et un `docker run -v $PWD:...` ne voit pas forcément les fichiers du job.
  Les scripts de l'atelier contournent ces deux pièges (`docker cp`, réseau
  `container:`).
- Les jobs d'un même stage tournent en parallèle ; `needs:` permet de
  démarrer un job sans attendre la fin du stage précédent.
- Les runners partagés de GitLab.com demandent une vérification du compte.
- L'approbation obligatoire sur un environnement protégé est une
  fonctionnalité payante ; `when: manual` est l'alternative gratuite.

Azure DevOps

- Un secret n'est jamais exposé automatiquement à un script : il faut le
  passer explicitement par `env:`.
- Les approbations et les verrous se règlent sur l'environnement, dans
  l'interface, pas dans le YAML.
- Les jobs de type `deployment` ne récupèrent pas le code par défaut :
  ajouter `checkout: self`.
- Les variables de sortie d'un stage se lisent avec
  `stageDependencies.<stage>.<job>.outputs['<step>.<variable>']`.

TeamCity

- Le pipeline s'écrit en Kotlin (`.teamcity/settings.kts`), chargé par les
  "Versioned settings". Guide d'adaptation complet de l'atelier :
  `docs/ADAPTATION-TEAMCITY.md` dans le dépôt modèle.
- On déclenche la fin de la chaîne : TeamCity remonte les dépendances
  snapshot et lance tout sur le même commit.
- Les tags ne sont visibles qu'avec "Use tags as branches" et une
  branch specification du type `+:refs/tags/(v*)`.
- Pas de registre ni de jeton intégré : registre de l'entreprise et
  jetons `credentialsJSON:...`.

Jenkins

- Pas de registre, pas d'environnements, pas de jeton intégré : tout passe
  par des plugins et des Credentials.
- Préférer le pipeline déclaratif et un job "Multibranch Pipeline" (gère
  branches, PR et tags).
- Une étape `input` qui attend sur un agent bloque un exécuteur : déclarer
  `agent none` en tête et un agent par stage.
- L'agent est souvent permanent : penser au nettoyage (`cleanWs()`, images
  Docker, volumes).
